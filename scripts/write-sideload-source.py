#!/usr/bin/env python3
"""Write an AltStore / Feather source JSON for an unsigned Hermes Mobile IPA."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

BUNDLE_ID = "me.honcharenko.HermesMobile"
SOURCE_ID = "me.honcharenko.HermesMobile.sideload"
TINT = "#E8752A"
MIN_OS = "18.0"
MAX_HISTORY = 15
ICON_PATH = "HermesMobile/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
SCREENSHOTS = (
    "screenshots/framed/01_chat.png",
    "screenshots/framed/02_work.png",
    "screenshots/framed/03_cron.png",
    "screenshots/framed/04_notify.png",
    "screenshots/framed/05_connect.png",
)
DESCRIPTION = (
    "Hermes Mobile is the native iPhone companion for your self-hosted Hermes agent. "
    "Connect over your dashboard URL, chat with sessions, manage skills and cron, "
    "and approve work from your pocket.\n\n"
    "This build is unsigned. AltStore, SideStore, and Feather re-sign it with your "
    "own certificate on install."
)


def raw_url(repo: str, ref: str, rel: str) -> str:
    return f"https://raw.githubusercontent.com/{repo}/{ref}/{quote(rel)}"


def release_asset_url(repo: str, tag: str, filename: str) -> str:
    return f"https://github.com/{repo}/releases/download/{tag}/{quote(filename)}"


def load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def existing_screenshot_urls(repo: str, ref: str, repo_root: Path) -> list[str]:
    urls: list[str] = []
    for rel in SCREENSHOTS:
        if (repo_root / rel).is_file():
            urls.append(raw_url(repo, ref, rel))
    return urls


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--meta", required=True, type=Path)
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--tag", default="hermes-mobile-sideload")
    parser.add_argument("--ref", default="main", help="git ref for icons and screenshots")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--notes",
        default="Unsigned Hermes Mobile build for AltStore and Feather.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repo root for checking screenshot files exist",
    )
    args = parser.parse_args()

    meta = json.loads(args.meta.read_text(encoding="utf-8"))
    version = str(meta["version"])
    build = str(meta["build"])
    size = int(meta["size"])
    ipa_name = meta["ipaName"]
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    download_url = release_asset_url(args.repo, args.tag, ipa_name)
    source_url = release_asset_url(args.repo, args.tag, "source.json")
    icon_url = raw_url(args.repo, args.ref, ICON_PATH)
    shots = existing_screenshot_urls(args.repo, args.ref, args.repo_root)

    entry = {
        "version": version,
        "buildVersion": build,
        "date": now,
        "localizedDescription": args.notes,
        "downloadURL": download_url,
        "size": size,
        "minOSVersion": MIN_OS,
    }

    existing = load_json(args.output)
    previous = []
    if existing.get("apps"):
        previous = list(existing["apps"][0].get("versions") or [])
    history = [
        item
        for item in previous
        if not (
            str(item.get("version")) == version
            and str(item.get("buildVersion")) == build
        )
    ]
    versions = [entry, *history][:MAX_HISTORY]

    app: dict = {
        "name": "Hermes Mobile",
        "bundleIdentifier": BUNDLE_ID,
        "developerName": "Hermes Mobile",
        "subtitle": "Native iPhone companion for your Hermes agent",
        "localizedDescription": DESCRIPTION,
        "iconURL": icon_url,
        "tintColor": TINT,
        "category": "utilities",
        "appPermissions": {
            "privacy": {
                "NSLocalNetworkUsageDescription": {
                    "usageDescription": (
                        "Hermes Mobile connects to your self-hosted Hermes "
                        "server over your private network or Tailscale."
                    )
                },
                "NSMicrophoneUsageDescription": {
                    "usageDescription": (
                        "Hermes Mobile records your voice so it can be "
                        "transcribed into a message by your Hermes server."
                    )
                },
                "NSCameraUsageDescription": {
                    "usageDescription": (
                        "Hermes Mobile uses the camera so you can attach a "
                        "photo to your message."
                    )
                },
            }
        },
        "versions": versions,
        "version": version,
        "versionDate": now,
        "size": size,
        "downloadURL": download_url,
    }
    if shots:
        app["screenshotURLs"] = shots
        app["screenshots"] = shots

    source = {
        "name": "Hermes Mobile",
        "subtitle": "Unsigned Hermes Mobile builds for AltStore and Feather",
        "description": (
            "Rolling unsigned iPhone builds of Hermes Mobile. Add this source, then "
            "install Hermes Mobile. AltStore and Feather will re-sign the IPA and "
            "offer updates when a newer build is published."
        ),
        "identifier": SOURCE_ID,
        "sourceURL": source_url,
        "website": f"https://github.com/{args.repo}",
        "iconURL": icon_url,
        "tintColor": TINT,
        "featuredApps": [BUNDLE_ID],
        "apps": [app],
        "news": existing.get("news") or [],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.output}")
    print(f"Source URL: {source_url}")
    print(f"IPA URL: {download_url}")


if __name__ == "__main__":
    main()
