import AppKit
import TaviCore

final class InputMethodRuntime {
    // UserDefaults(suiteName:) returns nil for the process's own bundle identifier.
    static let preferences = InputSourceSetup.isInputMethodProcess
        ? UserDefaults.standard : UserDefaults(suiteName: InputSourceSetup.bundleID) ?? .standard
    static let shared = InputMethodRuntime()
    static let changed = Notification.Name("TaviInputMethodRuntimeChanged")
    private static let externalChange = Notification.Name("dev.3xhaust.tavi.shared-state-changed")
    private let processID = String(ProcessInfo.processInfo.processIdentifier)
    private var observer: NSObjectProtocol?
    private let preferences: UserDefaults
    let store: LearningStore?
    private(set) var error: String?

    var enabled: Bool {
        get { preferences.object(forKey: "compositionEnabled") as? Bool ?? true }
        set {
            let changed = newValue != enabled
            preferences.set(newValue, forKey: "compositionEnabled")
            notify()
            guard changed else { return }
            // Off hands typing back to the user's previous source; on brings Tavi back.
            if newValue {
                if !InputSourceSetup.isSelected {
                    InputSourceSetup.rememberCurrentAsPrevious()
                    _ = InputSourceSetup.select()
                }
            } else if InputSourceSetup.isSelected {
                InputSourceSetup.selectPrevious()
            }
        }
    }

    var learning: Bool {
        get { preferences.object(forKey: "learning") as? Bool ?? true }
        set {
            preferences.set(newValue, forKey: "learning")
            notify()
        }
    }

    init(store: LearningStore, preferences: UserDefaults) {
        self.store = store
        self.preferences = preferences
    }

    private init() {
        preferences = Self.preferences
        do { store = try LearningStore() }
        catch {
            store = nil
            self.error = "개인 사전을 읽지 못했어요 · \(error.localizedDescription)"
        }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.externalChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, notification.object as? String != self.processID else { return }
            CFPreferencesAppSynchronize(InputSourceSetup.bundleID as CFString)
            self.reloadWords()
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    func reloadWords() {
        do { try store?.reload() }
        catch { self.error = "개인 사전을 읽지 못했어요 · \(error.localizedDescription)" }
    }

    func confirm(_ evidence: LearnedWord?) {
        guard learning, let evidence else { return }
        do {
            try store?.confirm(evidence)
            error = nil
        } catch {
            self.error = "학습 저장 실패 · \(error.localizedDescription)"
        }
        notify()
    }

    private func notify() {
        CFPreferencesAppSynchronize(InputSourceSetup.bundleID as CFString)
        NotificationCenter.default.post(name: Self.changed, object: self)
        DistributedNotificationCenter.default().postNotificationName(
            Self.externalChange, object: processID, userInfo: nil, deliverImmediately: true
        )
    }
}
