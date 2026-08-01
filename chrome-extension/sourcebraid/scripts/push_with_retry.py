#!/usr/bin/env python3
"""Push a generated commit while tolerating concurrent branch updates."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time


def synchronize_and_push(
    branch: str,
    *,
    remote: str = "origin",
    attempts: int = 5,
    delay_seconds: float = 2.0,
) -> None:
    if not branch:
        raise ValueError("branch must not be empty")
    if attempts < 1:
        raise ValueError("attempts must be at least 1")
    if delay_seconds < 0:
        raise ValueError("delay_seconds must not be negative")

    for attempt in range(1, attempts + 1):
        subprocess.run(["git", "fetch", remote, branch], check=True)
        subprocess.run(["git", "rebase", "FETCH_HEAD"], check=True)
        result = subprocess.run(
            ["git", "push", remote, f"HEAD:{branch}"],
            check=False,
        )
        if result.returncode == 0:
            print(f"Pushed converted Markdown on attempt {attempt}.")
            return

        if attempt == attempts:
            raise RuntimeError(
                f"Could not push converted Markdown after {attempts} attempts."
            )

        delay = delay_seconds * attempt
        print(
            f"Push attempt {attempt} was rejected; refreshing the branch "
            f"and retrying in {delay:g} seconds."
        )
        time.sleep(delay)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--branch", required=True)
    parser.add_argument("--remote", default="origin")
    parser.add_argument("--attempts", type=int, default=5)
    parser.add_argument("--delay-seconds", type=float, default=2.0)
    args = parser.parse_args()

    try:
        synchronize_and_push(
            args.branch,
            remote=args.remote,
            attempts=args.attempts,
            delay_seconds=args.delay_seconds,
        )
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
