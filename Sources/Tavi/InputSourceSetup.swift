import AppKit
import Carbon
import TaviCore

enum InputSourceSetup {
    static let applicationID = "dev.3xhaust.tavi"
    static let bundleID = InputMethodPackage.identifier
    static let connectionName = "dev.3xhaust.inputmethod.tavi_Connection"
    static var isInputMethodProcess: Bool { Bundle.main.bundleIdentifier == bundleID }

    static var isSelected: Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let value = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return false }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String == bundleID
    }

    static func register() -> OSStatus {
        guard isInputMethodProcess else { return OSStatus(paramErr) }
        return TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    }

    private static var source: TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: bundleID] as CFDictionary
        return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
    }

    static var isRegistered: Bool { source != nil }

    /// True once the user has added Tavi in Keyboard Settings; that list is the only
    /// place macOS persists a third-party input method.
    static var isAdded: Bool { source.map(isEnabled) ?? false }

    private static func isEnabled(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }

    /// Returns to Tavi only while the user keeps it in their input sources; never re-adds it.
    @discardableResult
    static func reselect() -> OSStatus {
        guard let source, isEnabled(source) else { return OSStatus(paramErr) }
        return TISSelectInputSource(source)
    }

    /// Selects Tavi. The installer only asks for this after the user added Tavi in
    /// Keyboard Settings, because an enable from here does not persist.
    static func select() -> OSStatus {
        guard let source else { return OSStatus(paramErr) }
        let enabled = TISEnableInputSource(source)
        guard enabled == noErr else { return enabled }
        let selected = TISSelectInputSource(source)
        guard selected == noErr else { return selected }
        return isSelected ? noErr : OSStatus(paramErr)
    }

    private static let previousKey = "previousInputSource"

    /// Remembers the keyboard source the user had before Tavi, so turning Tavi's
    /// automatic input off can hand typing back to it.
    static func rememberCurrentAsPrevious() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let value = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return }
        let id = Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
        guard id != bundleID else { return }
        InputMethodRuntime.preferences.set(id, forKey: previousKey)
    }

    @discardableResult
    static func selectPrevious() -> OSStatus {
        let id = InputMethodRuntime.preferences.string(forKey: previousKey)
        let filter = id.map { [kTISPropertyInputSourceID as String: $0] as CFDictionary }
        let source = filter.flatMap { (TISCreateInputSourceList($0, false)?.takeRetainedValue() as? [TISInputSource])?.first }
            ?? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let source else { return OSStatus(paramErr) }
        return TISSelectInputSource(source)
    }

    static func disable() -> OSStatus {
        guard let source else { return noErr }
        return TISDisableInputSource(source)
    }

    static func migrateLegacyPreferences() {
        guard let legacy = UserDefaults.standard.persistentDomain(forName: applicationID) else { return }
        for key in ["learning", "tutorialCompleted", "compositionEnabled"] {
            if InputMethodRuntime.preferences.object(forKey: key) == nil, let value = legacy[key] {
                InputMethodRuntime.preferences.set(value, forKey: key)
            }
        }
    }

    static func openApplication() -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationID) else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
