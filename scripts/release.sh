#!/bin/bash
# Publishes the current build as a GitHub release. Installed copies of Tavi find it
# through the latest-release API and update themselves without a window.
# Before running: bump CFBundleShortVersionString and CFBundleVersion in both
# Resources/Info.plist and Resources/InputMethodInfo.plist. The repository must be public.
# Usage: bash scripts/release.sh ["release notes"]
set -euo pipefail
cd "$(dirname "$0")/.."
plist=Resources/Info.plist
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
repository="$(/usr/libexec/PlistBuddy -c 'Print :TaviUpdateRepository' "$plist")"
if gh release view "v$version" --repo "$repository" >/dev/null 2>&1; then
    printf 'v%s is already released on %s; bump the version first.\n' "$version" "$repository" >&2
    exit 1
fi

bash scripts/build.sh
bash scripts/package-dmg.sh
archive="dist/Tavi-$version.zip"
rm -f "$archive"
ditto -c -k --keepParent dist/Tavi.app "$archive"

gh release create "v$version" "dist/Tavi-$version.dmg" "$archive" \
    --repo "$repository" --title "Tavi $version" --notes "${1:-Tavi $version}"
printf 'Released v%s on %s\n' "$version" "$repository"
