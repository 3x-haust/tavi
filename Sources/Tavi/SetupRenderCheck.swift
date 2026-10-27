#if DEBUG
import AppKit
import TaviCore

@MainActor
enum SetupRenderCheck {
    static func run(output: URL) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .aqua)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let dataDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataDirectory) }
        let store = try LearningStore(url: dataDirectory.appendingPathComponent("words.json"))
        let controller = PreferencesWindow(
            store: store, onEnabled: { _ in }, onLearning: { _ in }, onInputSettings: {},
            onStart: {}, onOpenApplications: {}, onRemoveInputMethod: {}
        )
        let states: [(String, InputMethodSetupState)] = [
            ("move", .moveToApplications), ("install", .notInstalled),
            ("update", .updateAvailable), ("working", .working("입력기를 준비하고 있어요…")),
            ("select", .needsSelection), ("error", .failed("입력기를 등록하지 못했어요. 기존 입력기와 개인 사전은 유지됩니다. 다시 시도해 주세요.")),
            ("ready", .ready),
        ]
        guard let window = controller.window, let content = window.contentView else {
            preconditionFailure("Setup window unavailable")
        }
        for width in [640.0, 900.0] {
            for (name, state) in states {
                controller.refresh(
                    enabled: true, learning: true,
                    status: state == .ready ? "입력 소스에서 Tavi를 선택해 주세요" : "Tavi 앱에서 Tavi를 추가해 주세요"
                )
                controller.refreshSetup(state)
                window.setContentSize(NSSize(width: width, height: state == .ready ? 560 : 640))
                content.layoutSubtreeIfNeeded()
                guard let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                    preconditionFailure("Setup snapshot unavailable")
                }
                content.cacheDisplay(in: content.bounds, to: image)
                guard let png = image.representation(using: .png, properties: [:]) else {
                    preconditionFailure("Setup PNG unavailable")
                }
                try png.write(to: output.appendingPathComponent("\(name)-\(Int(width)).png"))
            }
        }
        window.close()
        print("SETUP_RENDERED")
    }
}
#endif
