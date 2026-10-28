# 1.1.3 build 8 development verification

Environment: Apple M5, arm64, macOS 27.0 (26A428), October 27, 2026.

## Automated checks

- `swift test`: **72 tests passed**.
- `swift run Tavi --check-editor`: `EDITOR_CHECK_PASSED`.
- Release compilation and strict ad-hoc signature verification passed.
- Eight isolated installation tests cover fresh install, update, registration
  rollback, failed first install, foreign-bundle refusal, incomplete-source
  refusal, removal/data preservation, and allowed Applications locations.
- The regular Applications app is `dev.3xhaust.tavi`. Its nested IME component is
  `dev.3xhaust.inputmethod.tavi`; only the component uses background/IMK metadata.
- The package gate checks both process roles, bundle metadata, resources and
  nested code signatures. The DMG contains only Tavi.app and an Applications link.
- Six setup states were rendered internally at two widths without operating
  the user's desktop. Installation, update and removal actions were not invoked
  against the user's actual Applications or Input Methods directories.
- Standalone SourceKit lacks some SwiftPM module context; actual package
  compilation is the type-checking authority for those diagnostics.

The tests also cover Hangul composition, mixed words, three-confirmation learning,
independent input sessions, correction, deletion, Escape, Enter
confirmation, shortcuts, paths, token bounds, tutorial progress and storage.
The native editor check covers AppKit insertion, whole-token correction,
selection and table multi-selection.

## Real-app testing

**Ghostty and other app typing tests are reserved for the user.** Hands-on
typing verification was stopped at their request. Neither core tests nor source
registration establish that every host application's editing behavior works.

The native input-method version does not use the former accessibility helper's
text replacement, permission prompts, event tap or login-item setup.

## Setup video

The video plays inline on the app's first-run setup page, next to three step
labels; there is no separate guide window. It is a recording of the whole
Keyboard Settings window (sheet included, nothing cropped) made with
`scripts/record-setup-guide.sh` while Tavi was added by hand: Edit… → + →
Korean → Tavi → Add → Done. The Apple Account rows in the sidebar are blurred.
It is **17.29 seconds** at half speed, 1100 × 1378, H.264, no audio,
**579,347 bytes**. Key frames were inspected after encoding.
The player starts when the setup page is shown and releases its item when Tavi
is added or the window closes.

## Size and latency scope

The immutable model contains 176,422 decoded bytes / 238,328 bundled base64 bytes.
It is loaded once and does not require a neural runtime or network service.

Earlier release-core measurements on this machine recorded a warm p95 of
0.020625 ms for normal decisions and 0.182500 ms with a 2,000-entry dictionary
and 64-key token. These measure the core, **not** IMK communication, host rendering,
or the final application's memory footprint.

## Updates

Release parsing, version ordering, the required GitHub digest and the Ed25519
signature check (tampered archive, another key, empty signature) are unit-tested.
`tools/sign_update.swift` refuses a key that does not match `TaviUpdatePublicKey`.
A zip made with `ditto -c -k --keepParent dist/Tavi.app` unpacked and passed the bundle and
signature checks (`--check-update-archive`); a mismatched version was rejected.
A background `--update` launch with nothing to update exited at once without UI.
Settings shows the current version, an automatic-update switch (stored in the
input method's preferences, so the daily check honors it) and an
“업데이트 확인” button; the page was rendered with `--render-setup`.
The full path — a published release replacing an installed copy — has **not**
been exercised, because no GitHub repository or release exists yet.

## Password prompts

Pass-through under Secure Event Input is built but has **not** been exercised with a
real `sudo` prompt in Ghostty, Terminal or iTerm2.

## Release status

Releases are published on GitHub (`3x-haust/tavi`) with `scripts/release.sh`.
They are ad-hoc signed; Developer ID signing and notarization have not been done.
