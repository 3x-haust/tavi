import AppKit
import OSLog
import TaviCore

/// Updates Tavi from the GitHub repository's latest release without any window.
/// The input method checks once at launch and then daily; the app replaces itself,
/// relaunches, and the relaunched app updates the input-method component.
enum Updater {
    static let backgroundArgument = "--update"
    /// Posted by the input method when the app is already running.
    static let available = Notification.Name("dev.3xhaust.tavi.update-available")
    private static let log = Logger(subsystem: "dev.3xhaust.tavi", category: "update")

    private enum Failure: Error {
        case download, checksum, unsigned, archive, bundle, signature
    }

    enum Outcome: Equatable {
        case current, installed(String), unreachable, failed
    }

    /// Settings → 자동 업데이트. Shared with the input method, which only checks while it is on.
    static var automatic: Bool {
        get {
            CFPreferencesAppSynchronize(InputSourceSetup.bundleID as CFString)
            return InputMethodRuntime.preferences.object(forKey: "automaticUpdates") as? Bool ?? true
        }
        set {
            InputMethodRuntime.preferences.set(newValue, forKey: "automaticUpdates")
            CFPreferencesAppSynchronize(InputSourceSetup.bundleID as CFString)
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func latest() async -> UpdateRelease? {
        guard let repository = Bundle.main.object(forInfoDictionaryKey: "TaviUpdateRepository") as? String,
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UpdateRelease.parse(data)
    }

    // MARK: Input method

    /// Hands a newer release to the app: a running app is told, otherwise it is opened
    /// in the background.
    static func checkFromInputMethod() async {
        guard automatic, let release = await latest(), release.isNewer(than: currentVersion) else { return }
        log.notice("release \(release.version, privacy: .public) is newer than \(currentVersion, privacy: .public)")
        if !NSRunningApplication.runningApplications(withBundleIdentifier: InputSourceSetup.applicationID).isEmpty {
            DistributedNotificationCenter.default().postNotificationName(available, object: nil, deliverImmediately: true)
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: InputSourceSetup.applicationID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = [backgroundArgument]
        _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }

    // MARK: App

    /// Replaces this app with a newer release and relaunches it; `found` hears the
    /// version before it is downloaded.
    @MainActor
    static func replaceAppIfNewer(background: Bool, found: ((String) -> Void)? = nil) async -> Outcome {
        let app = Bundle.main.bundleURL
        guard let release = await latest() else { return .unreachable }
        guard release.isNewer(than: currentVersion) else { return .current }
        guard InputMethodPackage.isApplicationLocation(app) else { return .failed }
        found?(release.version)
        do {
            let downloaded = try await download(release)
            _ = try FileManager.default.replaceItemAt(app, withItemAt: downloaded)
            try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent())
        } catch {
            log.error("update to \(release.version, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return .failed
        }
        log.notice("updated app to \(release.version, privacy: .public)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = !background
        configuration.arguments = background ? [backgroundArgument] : []
        _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        return .installed(release.version)
    }

    /// The maintainer's Ed25519 public key; only archives it signed are installed.
    private static var publicKey: Data? {
        (Bundle.main.object(forInfoDictionaryKey: "TaviUpdatePublicKey") as? String).flatMap { Data(base64Encoded: $0) }
    }

    /// Downloads, checks and unpacks the release; returns the new Tavi.app.
    private static func download(_ release: UpdateRelease) async throws -> URL {
        guard let signatureURL = release.signature, let publicKey else { throw Failure.unsigned }
        let (signature, signed) = try await URLSession.shared.data(from: signatureURL)
        guard (signed as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        let (file, response) = try await URLSession.shared.download(from: release.archive)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        let archive = try Data(contentsOf: file, options: .mappedIfSafe)
        guard release.matchesDigest(archive) else { throw Failure.checksum }
        guard UpdateRelease.isSigned(archive, signature: signature, publicKey: publicKey) else { throw Failure.unsigned }
        return try unpack(file, version: release.version)
    }

    /// Unpacks a verified archive and checks the bundle inside it.
    static func unpack(_ file: URL, version: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Tavi-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard try run("/usr/bin/ditto", ["-x", "-k", file.path, folder.path]) else { throw Failure.archive }
        let app = folder.appendingPathComponent("Tavi.app")
        let info = Bundle(url: app)?.infoDictionary
        guard info?["CFBundleIdentifier"] as? String == InputSourceSetup.applicationID,
              info?["CFBundleShortVersionString"] as? String == version,
              (try? InputMethodPackage.version(at: app.appendingPathComponent("Contents/Helpers/TaviInputMethod.app")))?
                .release == version else { throw Failure.bundle }
        guard try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else { throw Failure.signature }
        return app
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
