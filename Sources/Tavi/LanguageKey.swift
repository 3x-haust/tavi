import AppKit

/// Names the key this Mac switches input sources with, which is also Tavi's correction key.
enum LanguageKey {
    /// Keyboard Settings' "Caps Lock switches to and from ABC". macOS stores it only after the
    /// user changes it; until then it is on, as it is by default with a Korean source added.
    static var capsLockSwitches: Bool {
        (UserDefaults.standard.object(forKey: "TISRomanSwitchState") as? Int ?? 1) == 1
    }

    static var name: String {
        if capsLockSwitches { return "한/영(Caps Lock) 키" }
        if UserDefaults(suiteName: "com.apple.HIToolbox")?.integer(forKey: "AppleFnUsageType") == 1 { return "🌐 키" }
        if let shortcut = shortcut(id: 60) ?? shortcut(id: 61) { return shortcut }
        return "입력 소스 전환 키"
    }

    /// "Select the previous/next input source" from Keyboard Shortcuts, when it is on Space.
    private static func shortcut(id: Int) -> String? {
        guard let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
                .dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = hotkeys[String(id)] as? [String: Any], entry["enabled"] as? Bool == true,
              let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int],
              parameters.count == 3, parameters[1] == 49 else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(parameters[2]))
        let symbols = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { flags.contains($0.0) }.map(\.1).joined() + "Space"
    }
}
