#!/bin/bash
# Publishes the current build as a GitHub release. Installed copies of Tavi find it
# through the latest-release API and update themselves without a window.
# Before running: bump CFBundleShortVersionString and CFBundleVersion in both
# Resources/Info.plist and Resources/InputMethodInfo.plist. The repository must be public.
# The archive is signed with the Ed25519 key at $TAVI_UPDATE_KEY (default
# ~/.config/tavi/update-signing.key); installed copies refuse an unsigned release.
# Usage: bash scripts/release.sh ["release notes"]
set -euo pipefail
cd "$(dirname "$0")/.."
plist=Resources/Info.plist
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
repository="$(/usr/libexec/PlistBuddy -c 'Print :TaviUpdateRepository' "$plist")"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :TaviUpdatePublicKey' "$plist")"
signing_key="${TAVI_UPDATE_KEY:-$HOME/.config/tavi/update-signing.key}"
[[ -f "$signing_key" ]] || { printf 'Missing update signing key: %s\n' "$signing_key" >&2; exit 1; }
if gh release view "v$version" --repo "$repository" >/dev/null 2>&1; then
    printf 'v%s is already released on %s; bump the version first.\n' "$version" "$repository" >&2
    exit 1
fi

bash scripts/build.sh
bash scripts/package-dmg.sh
archive="dist/Tavi-$version.zip"
rm -f "$archive"
ditto -c -k --keepParent dist/Tavi.app "$archive"
swift tools/sign_update.swift sign "$signing_key" "$archive" "$public_key"

gh release create "v$version" "dist/Tavi-$version.dmg" "$archive" "$archive.sig" \
    --repo "$repository" --title "Tavi $version" --notes "${1:-Tavi $version}"
printf 'Released v%s on %s\n' "$version" "$repository"
