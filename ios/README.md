# SourceBraid for iOS

The iOS project contains a SwiftUI configuration app and a native Share Extension. It saves shared URLs, readable Safari content, selected text, PDFs, and other files into the same GitHub repository and URL-hash-sharded `web-clips/index/*.jsonl` format as the Chrome extension.

## Open and sign

1. Open `SourceBraid.xcodeproj` in Xcode.
2. Select the **SourceBraid** project and the **SourceBraid** target.
3. Under **Signing & Capabilities**, select your Apple Developer team.
4. Repeat for the **SourceBraidShare** target.
5. If the bundle identifiers are unavailable, replace `de.patrickschiller.sourcebraid` and `de.patrickschiller.sourcebraid.share` with identifiers owned by your team.
6. Keep the App Group identical in both targets: `group.de.patrickschiller.sourcebraid`.
7. Run the SourceBraid app on your iPhone once and configure GitHub.

The fine-grained GitHub token needs `Contents: Read and write` for the private SourceBraid repository. It is stored in a Keychain access group shared only by the app and extension.

## TestFlight

The project uses automatic distribution signing for Apple Developer team
`H76K2HQUFB`. Before each upload, increment `CURRENT_PROJECT_VERSION` for both
the app and Share Extension. Then archive and upload from Xcode's Organizer, or
run:

```bash
xcodebuild \
  -project SourceBraid.xcodeproj \
  -scheme SourceBraid \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/SourceBraid.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath build/SourceBraid.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

The export options upload the archive directly to App Store Connect. The app
record there must use bundle ID `de.patrickschiller.sourcebraid`.

## Use

In FAZ, Safari, Files, or another app:

1. Tap **Share**.
2. Choose **SourceBraid**. If it is hidden, use **More** to enable it.
3. Edit the title, add optional tags or a note, and tap **Save**.

Apps such as Chrome and FAZ generally share only a URL. SourceBraid loads public web URLs in an isolated web view and converts the readable page content to Markdown before saving. Safari can additionally supply its already visible page text through the extension's preprocessing script. Pages that require an authenticated browser session or block the isolated request are saved as clearly labeled link-only clips.

## Build without signing

```bash
xcodebuild \
  -project SourceBraid.xcodeproj \
  -scheme SourceBraid \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```
