#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Universal: Apple silicon and Intel Macs.
arch_flags=(--arch arm64 --arch x86_64)
swift build -c release "${arch_flags[@]}"
bin="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"
app="dist/Tavi.app"
helper="$app/Contents/Helpers/TaviInputMethod.app"
signing_identity="${SIGNING_IDENTITY:--}"
rm -rf "$app"
mkdir -p \
    "$app/Contents/MacOS" \
    "$app/Contents/Resources" \
    "$helper/Contents/MacOS" \
    "$helper/Contents/Resources"
cp "$bin/Tavi" "$app/Contents/MacOS/Tavi"
cp "$bin/Tavi" "$helper/Contents/MacOS/Tavi"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/InputMethodInfo.plist "$helper/Contents/Info.plist"
cp -R "$bin/Tavi_TaviCore.bundle" "$app/Contents/Resources/"
cp -R "$bin/Tavi_TaviCore.bundle" "$helper/Contents/Resources/"
cp Resources/setup-guide.mp4 "$app/Contents/Resources/"
bash scripts/make-icon.sh "$app/Contents/Resources/Tavi.icns"
cp "$app/Contents/Resources/Tavi.icns" "$helper/Contents/Resources/Tavi.icns"
cp Resources/TaviMenuIcon.pdf "$helper/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$helper/Contents/Resources/"
codesign --force --sign "$signing_identity" "$helper"
codesign --force --sign "$signing_identity" "$app"
codesign --verify --strict "$helper"
codesign --verify --deep --strict "$app"
bash scripts/check-package.sh "$app"
if [[ "$signing_identity" == "-" ]]; then
    printf 'Built %s with ad-hoc signing (not Developer ID signed or notarized).\n' "$app"
else
    printf 'Built %s with caller-supplied signing identity: %s\n' "$app" "$signing_identity"
fi
