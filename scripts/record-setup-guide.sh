#!/bin/bash
# Records the whole Keyboard Settings window while someone adds Tavi by hand, then
# encodes Resources/setup-guide.mp4. Tavi must be installed but not yet added; the
# component is installed from dist/Tavi.app when missing. Recording stops 3 seconds
# after Tavi is added, and the raw take is kept in .build/setup-guide-raw.mp4.
# The encoded guide blurs the Apple Account rows in the Settings sidebar, runs from
# the Keyboard pane appearing to 2 seconds after the last change, and plays at half
# speed so each click can be followed.
# Usage: bash scripts/record-setup-guide.sh [max-seconds]
#        bash scripts/record-setup-guide.sh --encode-only   (re-encode the kept raw take)
set -euo pipefail
cd "$(dirname "$0")/.."
seconds="${1:-120}"
[[ "$seconds" == "--encode-only" ]] && seconds=0
raw=".build/setup-guide-raw.mp4"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
mkdir -p .build

if [[ "${1:-}" == "--encode-only" ]]; then
    [[ -f "$raw" ]] || { printf 'No raw take at %s\n' "$raw" >&2; exit 1; }
    cp "$raw.log" "$log"
else
    component="$HOME/Library/Input Methods/Tavi.app"
    if [[ ! -d "$component" ]]; then
        ditto dist/Tavi.app/Contents/Helpers/TaviInputMethod.app "$component"
        "$component/Contents/MacOS/Tavi" --register-input-source
    fi

    recorder=".build/record-setup"
    [[ "$recorder" -nt tools/record_setup.swift ]] || swiftc -O tools/record_setup.swift -o "$recorder"

    # Settings opens on another pane; the recorder switches to Keyboard once it is writing.
    open "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings"
    sleep 2
    printf 'Recording. Add Tavi in Keyboard Settings: Edit… → + → 한국어 → Tavi → Add → Done.\n'
    "$recorder" "$seconds" "$raw" | tee "$log"
    cp "$log" "$raw.log"
fi
scale="$(sed -n 's/^SCALE=//p' "$log")"

# Sidebar account block, in points from the window's top-left.
read -r ax ay aw ah <<< "$((8 * scale)) $((94 * scale)) $((232 * scale)) $((84 * scale))"
blur="split[base][account];[account]crop=$aw:$ah:$ax:$ay,boxblur=24:4[hidden];[base][hidden]overlay=$ax:$ay"

changes="$(ffmpeg -v info -i "$raw" -vf "select='gt(scene,0.005)',showinfo" -f null - 2>&1 |
    sed -n 's/.*pts_time:\([0-9.]*\).*/\1/p')"
[[ -n "$changes" ]] || { printf 'Nothing changed on screen; nothing was written.\n' >&2; exit 1; }
# The first change is the switch to the Keyboard pane; start once it has drawn.
start="$(awk 'NR==1 { print $1 + 0.8 }' <<< "$changes")"
end="$(awk 'END { print $1 + 2 }' <<< "$changes")"

ffmpeg -v error -y -ss "$start" -to "$end" -i "$raw" \
    -vf "$blur,setpts=2*PTS,fps=24,scale='min(1100,iw)':-2,format=yuv420p" \
    -an -c:v libx264 -preset slow -crf 26 -movflags +faststart \
    Resources/setup-guide.mp4
printf 'Wrote Resources/setup-guide.mp4 (%s–%s s of the recording)\n' "$start" "$end"
