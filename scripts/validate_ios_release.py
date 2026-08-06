#!/usr/bin/env python3
"""Validate the SourceBraid iOS sources and an optional archived app bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PROJECT_FILE = Path("ios/SourceBraid.xcodeproj/project.pbxproj")
APP_INFO = Path("ios/SourceBraid/Resources/Info.plist")
SHARE_INFO = Path("ios/SourceBraidShare/Info.plist")
APP_ENTITLEMENTS = Path("ios/SourceBraid/Resources/SourceBraid.entitlements")
SHARE_ENTITLEMENTS = Path("ios/SourceBraidShare/SourceBraidShare.entitlements")
APP_PRIVACY = Path("ios/SourceBraid/Resources/PrivacyInfo.xcprivacy")
SHARE_PRIVACY = Path("ios/SourceBraidShare/PrivacyInfo.xcprivacy")
APP_ICON_SET = Path("ios/SourceBraid/Resources/Assets.xcassets/AppIcon.appiconset")

APP_BUNDLE_IDENTIFIER = "de.patrickschiller.sourcebraid"
SHARE_BUNDLE_IDENTIFIER = "de.patrickschiller.sourcebraid.share"
TEST_BUNDLE_IDENTIFIER = "de.patrickschiller.sourcebraid.tests"
APP_GROUP = "group.de.patrickschiller.sourcebraid"
KEYCHAIN_GROUP = "$(AppIdentifierPrefix)de.patrickschiller.sourcebraid.shared"
APP_ICON_NAME = "AppIcon"
APP_ICON_FILENAME = "AppIcon-1024.png"

COLLECTED_DATA_TYPES = {
    "NSPrivacyCollectedDataTypeOtherUserContent",
    "NSPrivacyCollectedDataTypeBrowsingHistory",
    "NSPrivacyCollectedDataTypeUserID",
    "NSPrivacyCollectedDataTypeOtherDataTypes",
}
APP_FUNCTIONALITY = "NSPrivacyCollectedDataTypePurposeAppFunctionality"


class ReleaseValidationError(RuntimeError):
    """Raised when an iOS release input is internally inconsistent."""


@dataclass(frozen=True)
class ReleaseReport:
    marketing_version: str
    build_number: str
    icon_sha256: str
    packaged_icon_sha256: tuple[tuple[str, str], ...] = ()


def read_plist(path: Path) -> dict[str, object]:
    try:
        with path.open("rb") as plist_file:
            value = plistlib.load(plist_file)
    except (OSError, plistlib.InvalidFileException) as error:
        raise ReleaseValidationError(f"could not read plist {path}: {error}") from error
    if not isinstance(value, dict):
        raise ReleaseValidationError(f"plist root is not a dictionary: {path}")
    return value


def setting_values(project: str, key: str) -> list[str]:
    values = re.findall(rf"^\s*{re.escape(key)} = ([^;]+);", project, flags=re.MULTILINE)
    return [value.strip().strip('"') for value in values]


def png_properties(path: Path) -> tuple[int, int, bool]:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ReleaseValidationError(f"could not read PNG {path}: {error}") from error
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ReleaseValidationError(f"app icon is not a PNG: {path}")

    offset = 8
    width = height = color_type = None
    has_transparency_chunk = False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        if len(chunk_data) != length:
            raise ReleaseValidationError(f"truncated PNG chunk in {path}")
        if chunk_type == b"IHDR":
            if length != 13:
                raise ReleaseValidationError(f"invalid PNG header in {path}")
            width, height, _bit_depth, color_type = struct.unpack(">IIBB", chunk_data[:10])
        elif chunk_type == b"tRNS":
            has_transparency_chunk = True
        elif chunk_type == b"IEND":
            break
        offset += 12 + length

    if width is None or height is None or color_type is None:
        raise ReleaseValidationError(f"PNG has no valid header: {path}")
    return width, height, color_type in {4, 6} or has_transparency_chunk


def validate_info_plists(root: Path, errors: list[str]) -> None:
    app_info = read_plist(root / APP_INFO)
    share_info = read_plist(root / SHARE_INFO)
    for label, info in (("app", app_info), ("Share Extension", share_info)):
        if info.get("CFBundleDisplayName") != "SourceBraid":
            errors.append(f"{label} display name must be SourceBraid")
        if info.get("CFBundleShortVersionString") != "$(MARKETING_VERSION)":
            errors.append(f"{label} must derive its version from MARKETING_VERSION")
        if info.get("CFBundleVersion") != "$(CURRENT_PROJECT_VERSION)":
            errors.append(f"{label} must derive its build from CURRENT_PROJECT_VERSION")
        if info.get("SourceBraidKeychainAccessGroup") != KEYCHAIN_GROUP:
            errors.append(f"{label} Keychain group is inconsistent")
    if app_info.get("ITSAppUsesNonExemptEncryption") is not False:
        errors.append("app must declare ITSAppUsesNonExemptEncryption=false")


def validate_entitlements(root: Path, errors: list[str]) -> None:
    for relative in (APP_ENTITLEMENTS, SHARE_ENTITLEMENTS):
        entitlements = read_plist(root / relative)
        if entitlements.get("com.apple.security.application-groups") != [APP_GROUP]:
            errors.append(f"unexpected App Group in {relative}")
        if entitlements.get("keychain-access-groups") != [KEYCHAIN_GROUP]:
            errors.append(f"unexpected Keychain group in {relative}")


def validate_privacy_manifest(path: Path, errors: list[str]) -> None:
    manifest = read_plist(path)
    if manifest.get("NSPrivacyTracking") is not False:
        errors.append(f"tracking must be disabled in {path}")
    if manifest.get("NSPrivacyTrackingDomains") != []:
        errors.append(f"tracking domains must be empty in {path}")

    collected = manifest.get("NSPrivacyCollectedDataTypes")
    if not isinstance(collected, list):
        errors.append(f"collected data types must be an array in {path}")
    else:
        actual_types = {
            item.get("NSPrivacyCollectedDataType")
            for item in collected
            if isinstance(item, dict)
        }
        if actual_types != COLLECTED_DATA_TYPES or len(collected) != len(COLLECTED_DATA_TYPES):
            errors.append(f"collected data types are incomplete in {path}")
        for item in collected:
            if not isinstance(item, dict):
                errors.append(f"invalid collected data entry in {path}")
                continue
            if item.get("NSPrivacyCollectedDataTypeLinked") is not True:
                errors.append(f"collected data must be declared linked in {path}")
            if item.get("NSPrivacyCollectedDataTypeTracking") is not False:
                errors.append(f"collected data must not be used for tracking in {path}")
            if item.get("NSPrivacyCollectedDataTypePurposes") != [APP_FUNCTIONALITY]:
                errors.append(f"collected data must be limited to app functionality in {path}")

    accessed = manifest.get("NSPrivacyAccessedAPITypes")
    expected_access = [
        {
            "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
            "NSPrivacyAccessedAPITypeReasons": ["1C8F.1"],
        }
    ]
    if accessed != expected_access:
        errors.append(f"required-reason API declaration is inconsistent in {path}")


def validate_icon(root: Path, errors: list[str]) -> str:
    contents_path = root / APP_ICON_SET / "Contents.json"
    try:
        contents = json.loads(contents_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseValidationError(f"could not read app icon catalog: {error}") from error
    images = contents.get("images")
    expected_image = {
        "filename": APP_ICON_FILENAME,
        "idiom": "universal",
        "platform": "ios",
        "size": "1024x1024",
    }
    if images != [expected_image]:
        errors.append("AppIcon catalog must use the reviewed universal 1024x1024 image")

    icon_path = root / APP_ICON_SET / APP_ICON_FILENAME
    width, height, has_alpha = png_properties(icon_path)
    if (width, height) != (1024, 1024):
        errors.append(f"App Store icon must be 1024x1024, got {width}x{height}")
    if has_alpha:
        errors.append("App Store icon must not contain transparency")
    return hashlib.sha256(icon_path.read_bytes()).hexdigest()


def validate_source(root: Path = REPOSITORY_ROOT) -> ReleaseReport:
    errors: list[str] = []
    try:
        project = (root / PROJECT_FILE).read_text(encoding="utf-8")
    except OSError as error:
        raise ReleaseValidationError(f"could not read Xcode project: {error}") from error

    marketing_versions = setting_values(project, "MARKETING_VERSION")
    build_numbers = setting_values(project, "CURRENT_PROJECT_VERSION")
    if len(marketing_versions) != 4 or len(set(marketing_versions)) != 1:
        errors.append("app and Share Extension marketing versions must match in Debug and Release")
    if len(build_numbers) != 4 or len(set(build_numbers)) != 1:
        errors.append("app and Share Extension build numbers must match in Debug and Release")

    marketing_version = marketing_versions[0] if marketing_versions else ""
    build_number = build_numbers[0] if build_numbers else ""
    if not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", marketing_version):
        errors.append("marketing version must contain three dot-separated integers")
    if not re.fullmatch(r"[1-9]\d*", build_number):
        errors.append("build number must be a positive integer")

    identifiers = setting_values(project, "PRODUCT_BUNDLE_IDENTIFIER")
    expected_identifiers = {
        APP_BUNDLE_IDENTIFIER: 2,
        SHARE_BUNDLE_IDENTIFIER: 2,
        TEST_BUNDLE_IDENTIFIER: 2,
    }
    for identifier, count in expected_identifiers.items():
        if identifiers.count(identifier) != count:
            errors.append(f"expected {count} project configurations for {identifier}")
    if len(identifiers) != sum(expected_identifiers.values()):
        errors.append("Xcode project contains an unexpected bundle identifier")
    if setting_values(project, "ASSETCATALOG_COMPILER_APPICON_NAME") != [
        APP_ICON_NAME,
        APP_ICON_NAME,
    ]:
        errors.append("app target must use the AppIcon catalog in Debug and Release")

    validate_info_plists(root, errors)
    validate_entitlements(root, errors)
    for relative in (APP_PRIVACY, SHARE_PRIVACY):
        validate_privacy_manifest(root / relative, errors)
    icon_sha256 = validate_icon(root, errors)

    if errors:
        raise ReleaseValidationError("\n".join(f"- {error}" for error in errors))
    return ReleaseReport(marketing_version, build_number, icon_sha256)


def validate_app_bundle(app_bundle: Path, source: ReleaseReport) -> ReleaseReport:
    errors: list[str] = []
    app_info = read_plist(app_bundle / "Info.plist")
    extension_bundle = app_bundle / "PlugIns" / "SourceBraidShare.appex"
    extension_info = read_plist(extension_bundle / "Info.plist")

    expected = (
        ("app", app_info, APP_BUNDLE_IDENTIFIER),
        ("Share Extension", extension_info, SHARE_BUNDLE_IDENTIFIER),
    )
    for label, info, identifier in expected:
        if info.get("CFBundleIdentifier") != identifier:
            errors.append(f"packaged {label} bundle identifier is incorrect")
        if info.get("CFBundleShortVersionString") != source.marketing_version:
            errors.append(f"packaged {label} marketing version is incorrect")
        if str(info.get("CFBundleVersion", "")) != source.build_number:
            errors.append(f"packaged {label} build number is incorrect")
    if app_info.get("ITSAppUsesNonExemptEncryption") is not False:
        errors.append("packaged app is missing its encryption exemption declaration")

    primary_icon = (
        app_info.get("CFBundleIcons", {})
        .get("CFBundlePrimaryIcon", {})
        if isinstance(app_info.get("CFBundleIcons"), dict)
        else {}
    )
    if primary_icon.get("CFBundleIconName") != APP_ICON_NAME:
        errors.append("packaged app does not reference the AppIcon catalog")
    packaged_icons = sorted(app_bundle.glob("AppIcon*.png"))
    if not packaged_icons:
        errors.append("packaged app contains no generated AppIcon PNGs")

    for privacy_path in (
        app_bundle / "PrivacyInfo.xcprivacy",
        extension_bundle / "PrivacyInfo.xcprivacy",
    ):
        validate_privacy_manifest(privacy_path, errors)

    if errors:
        raise ReleaseValidationError("\n".join(f"- {error}" for error in errors))
    packaged_hashes = tuple(
        (icon.name, hashlib.sha256(icon.read_bytes()).hexdigest()) for icon in packaged_icons
    )
    return ReleaseReport(
        source.marketing_version,
        source.build_number,
        source.icon_sha256,
        packaged_hashes,
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Validate SourceBraid's iOS App Store release configuration.",
    )
    result.add_argument(
        "--repository-root",
        type=Path,
        default=REPOSITORY_ROOT,
        help="SourceBraid repository root (defaults to the script's checkout)",
    )
    result.add_argument(
        "--app-bundle",
        type=Path,
        help="optional archived SourceBraid.app to validate after xcodebuild archive",
    )
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        report = validate_source(args.repository_root.resolve())
        if args.app_bundle:
            report = validate_app_bundle(args.app_bundle.resolve(), report)
    except ReleaseValidationError as error:
        print(f"error: iOS release validation failed\n{error}", file=sys.stderr)
        return 1

    print("iOS release validation passed")
    print(f"version: {report.marketing_version}")
    print(f"build: {report.build_number}")
    print(f"source app icon sha256: {report.icon_sha256}")
    for name, digest in report.packaged_icon_sha256:
        print(f"packaged app icon sha256 ({name}): {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
