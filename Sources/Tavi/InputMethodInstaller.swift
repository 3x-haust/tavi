import AppKit
import Carbon
import TaviCore

@MainActor
final class InputMethodInstaller {
    var changed: ((InputMethodSetupState) -> Void)?
    private(set) var state = InputMethodSetupState.notInstalled
    private var busy = false
    var isWorking: Bool { busy }
    private let appURL: URL
    private let componentURL: URL
    let destination: URL

    private enum Failure: Error, LocalizedError {
        case process(Int32, String), quitRefused, quitTimedOut, sourceChange(OSStatus), wrongProcess
        var errorDescription: String? {
            switch self {
            case .process(let code, let detail): return "입력기 처리를 완료하지 못했어요. (코드 \(code))\n\(detail)"
            case .quitRefused: return "실행 중인 입력기를 종료하지 못했어요. 다른 입력기로 전환한 뒤 다시 시도해 주세요."
            case .quitTimedOut: return "입력기 종료를 기다리는 시간이 초과됐어요. 다시 시도해 주세요."
            case .sourceChange(let code): return "입력 소스를 전환하지 못했어요. 키보드 설정을 확인해 주세요. (코드 \(code))"
            case .wrongProcess: return "다른 위치의 Tavi 입력기가 실행 중이에요. 해당 입력기를 종료한 뒤 다시 시도해 주세요."
            }
        }
    }

    init(appURL: URL = Bundle.main.bundleURL) {
        self.appURL = appURL
        componentURL = appURL.appendingPathComponent("Contents/Helpers/TaviInputMethod.app")
        destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/Tavi.app")
    }

    func refresh() {
        guard !busy else { return }
        guard InputMethodPackage.isApplicationLocation(appURL) else {
            publish(.moveToApplications)
            return
        }
        do {
            let bundled = try InputMethodPackage.version(at: componentURL)
            guard FileManager.default.fileExists(atPath: destination.path) else {
                publish(.notInstalled)
                return
            }
            guard try InputMethodPackage.version(at: destination) == bundled else {
                publish(.updateAvailable)
                return
            }
            publish(InputSourceSetup.isAdded ? .ready : .needsSelection)
        } catch { publish(.failed(error.localizedDescription)) }
    }

    /// The one setup action: installs or updates the component when needed, selects
    /// Tavi once it is in the user's input sources, and otherwise opens Keyboard
    /// Settings so the user can add it there.
    func start() async {
        guard !busy else { return }
        switch state {
        case .moveToApplications, .working: return
        case .notInstalled, .updateAvailable, .failed: await install()
        case .needsSelection, .ready: await selectInstalled(expectAdded: false)
        }
        if state == .needsSelection { InputSourceSetup.openSettings() }
    }

    /// Replaces the component of a Tavi the user already added, opening nothing. Tavi is
    /// selected again only when it was the selected source.
    func update() async {
        guard !busy, state == .updateAvailable, InputSourceSetup.isAdded else { return }
        await install(reselect: InputSourceSetup.isSelected)
    }

    private func install(reselect: Bool = true) async {
        guard InputMethodPackage.isApplicationLocation(appURL) else { publish(.moveToApplications); return }
        busy = true
        publish(.working("입력기를 준비하고 있어요…"))
        let wasSelected = InputSourceSetup.isSelected
        let wasAdded = InputSourceSetup.isAdded
        InputSourceSetup.rememberCurrentAsPrevious()
        do {
            _ = try InputMethodPackage.version(at: componentURL)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try InputMethodPackage.version(at: destination)
            }
            try switchAwayIfSelected()
            try await stopInstalledComponent()
            try await InputMethodPackage.install(source: componentURL, destination: destination) { installed in
                try await self.run(installed, arguments: ["--register-input-source"])
                try await self.run(installed, arguments: ["--input-source-registered"])
            }
            busy = false
            if reselect {
                await selectInstalled(expectAdded: wasAdded)
            } else {
                publish(wasAdded ? .ready : .needsSelection)
            }
            return
        } catch {
            var message = error.localizedDescription
            if wasSelected, FileManager.default.fileExists(atPath: destination.path) {
                do {
                    _ = try InputMethodPackage.version(at: destination)
                    try await run(destination, arguments: ["--select-input-source"])
                }
                catch { message += "\n입력 소스는 키보드 설정에서 다시 선택해 주세요." }
            }
            publish(.failed(message))
        }
        busy = false
    }

    func select() async {
        guard !busy else { return }
        await selectInstalled(expectAdded: false)
    }

    /// Until the user adds Tavi in Keyboard Settings there is nothing to select, so
    /// that case asks for the addition instead of reporting a failed install.
    private func selectInstalled(expectAdded: Bool) async {
        busy = true
        do {
            _ = try InputMethodPackage.version(at: destination)
            // A freshly registered source can take a moment before macOS lets it be
            // selected, so an added source gets a few spaced attempts.
            let delays = expectAdded || InputSourceSetup.isAdded ? [0.0, 0.5, 1.0, 2.0] : []
            for delay in delays {
                try? await Task.sleep(for: .seconds(delay))
                if (try? await run(destination, arguments: ["--select-input-source"])) != nil {
                    publish(.ready)
                    busy = false
                    return
                }
            }
            publish(.needsSelection)
        } catch { publish(.failed(error.localizedDescription)) }
        busy = false
    }

    func remove() async {
        guard !busy else { return }
        busy = true
        publish(.working("입력기를 제거하고 있어요…"))
        do {
            _ = try InputMethodPackage.version(at: destination)
            try switchAwayIfSelected()
            try await stopInstalledComponent()
            let disabled = InputSourceSetup.disable()
            guard disabled == noErr else { throw Failure.sourceChange(disabled) }
            try InputMethodPackage.remove(at: destination)
            publish(.notInstalled)
        } catch { publish(.failed(error.localizedDescription)) }
        busy = false
    }

    private func switchAwayIfSelected() throws {
        guard InputSourceSetup.isSelected else { return }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        else { throw Failure.sourceChange(OSStatus(paramErr)) }
        let result = TISSelectInputSource(source)
        guard result == noErr else { throw Failure.sourceChange(result) }
    }

    private func stopInstalledComponent() async throws {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: InputSourceSetup.bundleID) {
            guard let runningURL = app.bundleURL?.standardizedFileURL,
                  [destination.standardizedFileURL, appURL.standardizedFileURL].contains(runningURL)
            else { throw Failure.wrongProcess }
            guard !app.isTerminated else { continue }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let source = DispatchSource.makeProcessSource(identifier: app.processIdentifier, eventMask: .exit, queue: .main)
                var finished = false
                var timeout: DispatchWorkItem?
                func finish(_ result: Result<Void, Error>) {
                    guard !finished else { return }
                    finished = true
                    timeout?.cancel()
                    source.setEventHandler(handler: nil)
                    source.setRegistrationHandler(handler: nil)
                    source.cancel()
                    continuation.resume(with: result)
                }
                timeout = DispatchWorkItem { finish(.failure(Failure.quitTimedOut)) }
                source.setEventHandler { finish(.success(())) }
                source.setRegistrationHandler {
                    guard !finished else { return }
                    if app.isTerminated { finish(.success(())) }
                    else if !app.terminate() { finish(.failure(Failure.quitRefused)) }
                }
                source.resume()
                if let timeout, !finished { DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout) }
            }
        }
    }

    private func run(_ bundle: URL, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = bundle.appendingPathComponent("Contents/MacOS/Tavi")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() }
            catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard status == 0 else { throw Failure.process(status, String(text.suffix(2_048))) }
    }

    private func publish(_ state: InputMethodSetupState) {
        self.state = state
        changed?(state)
    }
}
