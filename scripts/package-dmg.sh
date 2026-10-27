#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

app="${1:-dist/Tavi.app}"

if [[ ! -d "$app" ]]; then
    printf 'App bundle not found: %s\nBuild it first with: bash scripts/build.sh\n' "$app" >&2
    exit 1
fi

if [[ ! -f "$app/Contents/Info.plist" || ! -f "$app/Contents/MacOS/Tavi" ]]; then
    printf 'Invalid Tavi app bundle: %s\n' "$app" >&2
    exit 1
fi
bash scripts/check-package.sh "$app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
output="${2:-dist/Tavi-$version.dmg}"

mount_point="$(mktemp -d "${TMPDIR:-/tmp}/tavi-dmg-mount.XXXXXX")"
mounted=0

cleanup() {
    if [[ "$mounted" -eq 1 ]]; then
        hdiutil detach "$mount_point" >/dev/null 2>&1 || true
    fi
    rm -rf "$mount_point"
}
trap cleanup EXIT INT TERM

# dmgbuild writes the Finder window layout (.DS_Store) directly instead of
# scripting Finder, so every build gets the same window.
venv=".build/dmgbuild-venv"
if [[ ! -x "$venv/bin/dmgbuild" ]]; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet "dmgbuild==1.6.7"
fi

mkdir -p "$(dirname "$output")"
"$venv/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$app" "Tavi" "$output" >/dev/null

hdiutil verify "$output" >/dev/null
hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "$mount_point" \
    "$output" >/dev/null
mounted=1

[[ -d "$mount_point/Tavi.app" ]]
[[ -L "$mount_point/Applications" ]]
[[ "$(readlink "$mount_point/Applications")" == "/Applications" ]]
bash scripts/check-package.sh "$mount_point/Tavi.app"

[[ "$(find "$mount_point" -mindepth 1 -maxdepth 1 ! -name '.*' -print | wc -l | tr -d ' ')" == "2" ]]
[[ -f "$mount_point/.DS_Store" ]]

hdiutil detach "$mount_point" >/dev/null
mounted=0

output_dir="$(cd "$(dirname "$output")" && pwd)"
printf 'Created and verified %s/%s\n' "$output_dir" "$(basename "$output")"
