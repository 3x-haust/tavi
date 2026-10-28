import AppKit
import Carbon
import InputMethodKit

final class InputMethodServiceDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// The user's last deliberate choice. macOS's per-document input source swaps
    /// sources when another app activates; those swaps are undone while Tavi is preferred.
    private var taviPreferred = InputSourceSetup.isSelected
    private var lastActivation = Date.distantPast
    private static let activationWindow: TimeInterval = 0.7
    private let updateCheck = NSBackgroundActivityScheduler(identifier: "dev.3xhaust.inputmethod.tavi.update")

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = IMKServer(name: InputSourceSetup.connectionName, bundleIdentifier: InputSourceSetup.bundleID)
        if CommandLine.arguments.contains("--settings") { _ = InputSourceSetup.openApplication() }
        InputSourceSetup.keepOneSourceEverywhereOnce()
        scheduleUpdateChecks()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.lastActivation = Date()
            self?.restoreIfSwapped()
        }))
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Arriving at Tavi is always a deliberate choice; only leaving it right after
            // an app switch can be macOS's per-document swap.
            if InputSourceSetup.isSelected {
                self.taviPreferred = true
            } else if Date().timeIntervalSince(self.lastActivation) < Self.activationWindow {
                self.restoreIfSwapped()
            } else {
                self.taviPreferred = InputSourceSetup.isSelected
                if !self.taviPreferred { InputSourceSetup.rememberCurrentAsPrevious() }
            }
        }))
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach { center, observer in center.removeObserver(observer) }
        updateCheck.invalidate()
    }

    /// The only network access: the latest GitHub release, once at launch and then about
    /// daily when the system finds it convenient.
    private func scheduleUpdateChecks() {
        Task { await Updater.checkFromInputMethod() }
        updateCheck.repeats = true
        updateCheck.interval = 24 * 60 * 60
        updateCheck.tolerance = 60 * 60
        updateCheck.qualityOfService = .utility
        updateCheck.schedule { completion in
            Task {
                await Updater.checkFromInputMethod()
                completion(.finished)
            }
        }
    }

    private func restoreIfSwapped() {
        CFPreferencesAppSynchronize(InputSourceSetup.bundleID as CFString)
        guard taviPreferred, InputMethodRuntime.shared.enabled, !InputSourceSetup.isSelected else { return }
        InputSourceSetup.reselect()
    }
}
