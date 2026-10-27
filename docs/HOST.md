# Native input-method integration

Tavi 1.0.0 is distributed as an ordinary Applications app. Its regular
`dev.3xhaust.tavi` process owns settings and guided installation. It embeds
`Contents/Helpers/TaviInputMethod.app`, whose `dev.3xhaust.inputmethod.tavi`
process owns the IMK server and has no separate Dock or status item. Its
input-source menu is Tavi's only menu: the automatic-input switch, and items that
open the app (on the tutorial when asked) or Keyboard Settings.
Until Tavi is in the user's input sources, the app window is a single setup page:
the Keyboard Settings recording plays inline and one button installs the component
into `~/Library/Input Methods/Tavi.app` and opens Keyboard Settings. Adding Tavi
there posts the enabled-sources notification; the app selects Tavi and switches
to the tutorial. It does not require Accessibility or
Input Monitoring permission.

## Event path

1. `IMKServer` creates a `TaviInputController` for each client input session.
2. Each controller owns an independent `InputSession` and composition buffer.
3. Letter/number keys update `CompositionEngine`; `setMarkedText` sends the
   current candidate to the host's native composition area.
4. Space commits the candidate and trailing space in one `insertText` call.
   Enter with an active composition commits only that composition and consumes
   the event. A subsequent Enter with no composition passes to the application.
   In terminals this avoids inadvertently submitting a newly converted command.
5. Backspace removes a raw key and recomposes; with no active raw keys it passes
   through. Escape commits the original literal keys without learning.
6. Shortcuts and navigation finish composition without learning and pass through.
   The host owns selection, committed-text editing, undo and paste.
7. The only correction key is the user's own input-source switch key (Caps Lock with
   "Caps Lock switches to ABC", Globe, ⌃Space or any other shortcut). Tavi does not
   intercept it: macOS switches sources and ends the composition, and that end is
   deferred 80 ms. If the source really changed, the word toggles between its Korean
   reading and its literal keys, uncommitted, and Tavi re-selects itself; otherwise it
   was a focus change and the word commits as usual. Without a composition the key
   keeps its OS meaning. The input-method process also
   undoes per-document source swaps that follow an app activation while Tavi was the
   user's last deliberate choice.
8. Deactivation or a host-requested commit ends the session without learning.

Only native IMK marked-text and insertion methods modify the client.
There is no AX text replacement, synthetic Backspace, clipboard substitution,
event tap, or whole-document read. Tavi does not reinterpret pasted text.
It cannot revise arbitrary text already committed to a terminal.

URL/path syntax keeps the remainder of the token literal. Composition is
bounded to 64 raw keys; reaching the bound commits literal input rather than
dropping subsequent characters. The immutable statistical model is shared.

The in-app tutorial uses its existing native `InlineEditor`; the IMK controller
passes through its own app's events so two composition engines never process the
same practice keystroke.

## Personalization

Both processes share the existing personal-word file and input-method preferences
domain. Distributed change notifications refresh settings without polling.
Each new token uses current personal words. Only a confirmed explicit correction or eligible
direct spelling produces learning evidence. Automatic output does not train
itself; cancellation, focus loss and shortcuts do not add evidence.
One or two observations never affect predictions; three establish a preference.
The store is bounded to 2,000 entries and uses atomic writes.

## Installation and verification

The DMG root shows only Tavi.app and an Applications shortcut; `scripts/package-dmg.sh`
uses dmgbuild with `scripts/dmg-settings.py` and the background rendered by
`tools/render_dmg_background.py`.
The app checks its Applications location, validates the embedded component and
any existing destination, stages a copy, and registers it through the installed
component. A failed activation restores and re-registers the previous bundle.
The app only selects Tavi once the user has added it in Keyboard Settings, the one
place macOS persists a third-party input method; an update of an added Tavi
re-selects it without reopening Keyboard Settings.
An update switches away from the old component and awaits its process-exit event
before replacement; it does not poll. Removal preserves personal data and settings.
macOS launches the selected input method; no separate login item is needed.

Updates come from the repository's latest GitHub release (`Tavi-<version>.zip`).
The input-method process checks at launch and about daily via
NSBackgroundActivityScheduler; it posts `dev.3xhaust.tavi.update-available` to a
running app or opens the app with `--update` (accessory policy, no window or status
item). The app verifies the archive (GitHub SHA-256 digest when present, bundle ID,
version of app and embedded component, `codesign --verify --deep --strict`),
replaces its own bundle, and relaunches. The relaunched app finds the component
out of date and replaces it with the existing install path, reselecting Tavi only
if it was selected; while that runs the window keeps its normal layout.

Core tests are not proof of host compatibility. Ghostty and native AppKit
typing must be exercised using a real selected input method. Record actual
observations, unsupported behavior and untested cases in
[VERIFICATION.md](VERIFICATION.md), not blanket compatibility claims.

Releases are published with `scripts/release.sh` to GitHub; installed copies update
themselves from the latest release as described above.
