#!/bin/bash
set -euo pipefail

input_methods_dir="${TAVI_INPUT_METHODS_DIR:-$HOME/Library/Input Methods}"
destination="$input_methods_dir/Tavi.app"
expected_bundle_id="dev.3xhaust.inputmethod.tavi"

bundle_id() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null
}

running_installed_pids() {
    local executable="$destination/Contents/MacOS/Tavi"
    [[ -e "$executable" ]] || return 0
    /bin/ps -axo pid=,command= | /usr/bin/awk -v executable="$executable" '
        index($0, executable) {
            pid = $1
            sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", $0)
            if ($0 == executable || index($0, executable " ") == 1) {
                print pid
            }
        }
    '
}

if [[ ! -e "$destination" ]]; then
    printf 'Tavi is not installed at %s\n' "$destination"
    exit 0
fi

if [[ ! -f "$destination/Contents/Info.plist" ]]; then
    printf 'Refusing to remove unrecognized item: %s\n' "$destination" >&2
    exit 1
fi

installed_bundle_id="$(bundle_id "$destination" || true)"
if [[ "$installed_bundle_id" != "$expected_bundle_id" ]]; then
    printf 'Refusing to remove bundle ID "%s" at %s.\n' \
        "${installed_bundle_id:-<missing>}" "$destination" >&2
    exit 1
fi

pids="$(running_installed_pids)"
if [[ -n "$pids" ]]; then
    printf 'Requesting the installed Tavi process to terminate before removal...\n'
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && /bin/kill -TERM "$pid"
    done <<< "$pids"

    deadline=$((SECONDS + 5))
    while [[ "$SECONDS" -lt "$deadline" ]]; do
        [[ -z "$(running_installed_pids)" ]] && break
        /bin/sleep 0.2
    done
    if [[ -n "$(running_installed_pids)" ]]; then
        printf 'The installed Tavi process did not exit. Close it and try again.\n' >&2
        exit 1
    fi
fi

/bin/rm -rf "$destination"
printf 'Removed %s\n' "$destination"
printf 'Preferences and data in ~/Library/Application Support/Tavi were preserved.\n'
printf 'No keyboard shortcuts, permissions, or other input sources were changed.\n'
