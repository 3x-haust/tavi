import AppKit
import Carbon
import TaviCore

/// Reports every switch of the selected keyboard input source, whichever key the user
/// switches with.
final class SourceMonitor {
    deinit { stop() }
    private var observer: NSObjectProtocol?
    private(set) var sourceID: String?
    var changed: ((_ previous: String?, _ current: String?) -> Void)?

    func start() {
        stop()
        sourceID = Self.currentID()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let previous = self.sourceID
            self.sourceID = Self.currentID()
            if previous != self.sourceID { self.changed?(previous, self.sourceID) }
        }
    }

    func stop() {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        sourceID = nil
    }

    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    static func currentLanguage() -> InputLanguage? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return nil }
        let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
        if languages.contains(where: { $0 == "ko" || $0.hasPrefix("ko-") }) { return .korean }
        if languages.contains(where: { $0 == "en" || $0.hasPrefix("en-") }) { return .latin }
        return nil
    }
}
