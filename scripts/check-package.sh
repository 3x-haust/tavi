#!/bin/bash
set -euo pipefail

app="${1:-dist/Tavi.app}"
helper="$app/Contents/Helpers/TaviInputMethod.app"
parent_plist="$app/Contents/Info.plist"
helper_plist="$helper/Contents/Info.plist"
plist_buddy=/usr/libexec/PlistBuddy

fail() {
    printf 'Package check failed: %s\n' "$*" >&2
    exit 1
}

plist_value() {
    "$plist_buddy" -c "Print :$2" "$1" 2>/dev/null
}

expect_value() {
    local plist="$1" key="$2" expected="$3" actual
    actual="$(plist_value "$plist" "$key" || true)"
    [[ "$actual" == "$expected" ]] ||
        fail "$plist $key is '${actual:-<missing>}'; expected '$expected'"
}

expect_absent() {
    local plist="$1" key="$2"
    if plist_value "$plist" "$key" >/dev/null 2>&1; then
        fail "$plist must not contain $key"
    fi
}

expect_file() {
    [[ -f "$1" ]] || fail "missing file: $1"
}

expect_dir() {
    [[ -d "$1" ]] || fail "missing directory: $1"
}

expect_executable() {
    [[ -x "$1" ]] || fail "missing executable: $1"
}

expect_file "$parent_plist"
expect_file "$helper_plist"
# The version comes from the source plist, so a release only bumps it there.
release="$(plist_value "$(dirname "$0")/../Resources/InputMethodInfo.plist" CFBundleShortVersionString)"
build="$(plist_value "$(dirname "$0")/../Resources/InputMethodInfo.plist" CFBundleVersion)"
expect_executable "$app/Contents/MacOS/Tavi"
expect_executable "$helper/Contents/MacOS/Tavi"

expect_value "$parent_plist" CFBundleIdentifier dev.3xhaust.tavi
expect_value "$parent_plist" CFBundleExecutable Tavi
expect_value "$parent_plist" CFBundlePackageType APPL
expect_value "$parent_plist" CFBundleShortVersionString "$release"
expect_value "$parent_plist" CFBundleVersion "$build"
expect_value "$parent_plist" TaviUpdateRepository "$(plist_value "$(dirname "$0")/../Resources/Info.plist" TaviUpdateRepository)"
[[ "$(plist_value "$parent_plist" TaviUpdatePublicKey | base64 -D 2>/dev/null | wc -c | tr -d ' ')" == 32 ]] ||
    fail "$parent_plist TaviUpdatePublicKey must be a base64 Ed25519 public key"
for key in \
    LSUIElement \
    LSBackgroundOnly \
    InputMethodConnectionName \
    InputMethodServerControllerClass \
    TISInputSourceID \
    TISIntendedLanguage \
    tsInputMethodIconFileKey \
    tsInputMethodCharacterRepertoireKey
do
    expect_absent "$parent_plist" "$key"
done

expect_value "$helper_plist" CFBundleIdentifier dev.3xhaust.inputmethod.tavi
expect_value "$helper_plist" CFBundleExecutable Tavi
expect_value "$helper_plist" CFBundlePackageType APPL
expect_value "$helper_plist" CFBundleShortVersionString "$release"
expect_value "$helper_plist" CFBundleVersion "$build"
expect_value "$helper_plist" TaviUpdateRepository "$(plist_value "$(dirname "$0")/../Resources/Info.plist" TaviUpdateRepository)"
expect_value "$helper_plist" InputMethodServerControllerClass TaviInputController
expect_value "$helper_plist" InputMethodConnectionName dev.3xhaust.inputmethod.tavi_Connection
expect_value "$helper_plist" TISInputSourceID dev.3xhaust.inputmethod.tavi
expect_value "$helper_plist" LSUIElement true
expect_value "$helper_plist" LSBackgroundOnly true

for bundle in "$app" "$helper"; do
    expect_file "$bundle/Contents/Resources/Tavi.icns"
    expect_file "$bundle/Contents/Resources/LICENSE"
    expect_file "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
    expect_dir "$bundle/Contents/Resources/Tavi_TaviCore.bundle"
done
expect_file "$app/Contents/Resources/setup-guide.mp4"
[[ ! -e "$helper/Contents/Resources/setup-guide.mp4" ]] ||
    fail "setup-guide.mp4 must only be in the parent app"

case "$("$app/Contents/MacOS/Tavi" --diagnose)" in
    "mode=application"$'\n'*) ;;
    *) fail "parent executable did not start in application mode" ;;
esac
case "$("$helper/Contents/MacOS/Tavi" --diagnose)" in
    "mode=input-method"$'\n'*) ;;
    *) fail "helper executable did not start in input-method mode" ;;
esac

codesign --verify --strict "$helper" ||
    fail "helper signature validation failed"
codesign --verify --deep --strict "$app" ||
    fail "parent or nested signature validation failed"

printf 'Package contracts verified: %s\n' "$app"
