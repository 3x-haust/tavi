#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="$1"
work="$(mktemp -d "${TMPDIR:-/tmp}/tavi-icon.XXXXXX")"
trap 'rm -rf "$work"' EXIT
iconset="$work/Tavi.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/TaviLogo.png \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/TaviLogo.png \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$output"
