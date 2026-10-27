import Foundation

public enum InputMethodPackage {
    public static let identifier = "dev.3xhaust.inputmethod.tavi"

    public struct Version: Equatable {
        public let release: String
        public let build: String
    }

    public enum Failure: Error, LocalizedError {
        case invalidBundle, foreignBundle
        case recoveryFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidBundle: return "입력기 구성 요소가 올바르지 않아요. Tavi 앱을 다시 복사해 주세요."
            case .foreignBundle: return "설치 위치에 다른 앱이 있어 덮어쓰지 않았어요."
            case .recoveryFailed(let detail): return "이전 입력기를 복구하지 못했어요. \(detail)"
            }
        }
    }

    public static func version(at app: URL) throws -> Version {
        let infoURL = app.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoURL.path),
              let info = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: infoURL), options: [], format: nil
              ) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String else { throw Failure.invalidBundle }
        guard bundleID == identifier else { throw Failure.foreignBundle }
        guard info["CFBundleExecutable"] as? String == "Tavi",
              let release = info["CFBundleShortVersionString"] as? String, !release.isEmpty,
              let build = info["CFBundleVersion"] as? String, !build.isEmpty,
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/Tavi").path)
        else { throw Failure.invalidBundle }
        return Version(release: release, build: build)
    }

    public static func isApplicationLocation(_ app: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard app.pathExtension == "app" else { return false }
        let path = app.standardizedFileURL.path
        return path.hasPrefix("/Applications/")
            || path.hasPrefix(home.appendingPathComponent("Applications").standardizedFileURL.path + "/")
    }

    public static func install(
        source: URL, destination: URL,
        activate: (URL) async throws -> Void
    ) async throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { throw Failure.invalidBundle }
        _ = try version(at: source)
        let manager = FileManager.default
        let existed = manager.fileExists(atPath: destination.path)
        if existed { _ = try version(at: destination) }
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let token = UUID().uuidString
        let staging = parent.appendingPathComponent(".Tavi.installing.\(token).app")
        let backup = parent.appendingPathComponent(".Tavi.previous.\(token).app")
        var movedOld = false
        var installedNew = false
        do {
            try manager.copyItem(at: source, to: staging)
            if existed {
                try manager.moveItem(at: destination, to: backup)
                movedOld = true
            }
            try manager.moveItem(at: staging, to: destination)
            installedNew = true
            try await activate(destination)
        } catch {
            let failure = error
            do {
                if installedNew { try manager.removeItem(at: destination) }
                if movedOld {
                    try manager.moveItem(at: backup, to: destination)
                    try await activate(destination)
                }
                if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
            } catch {
                throw Failure.recoveryFailed(error.localizedDescription)
            }
            throw failure
        }
        if movedOld { try manager.removeItem(at: backup) }
    }

    public static func remove(at destination: URL) throws {
        guard FileManager.default.fileExists(atPath: destination.path) else { return }
        _ = try version(at: destination)
        try FileManager.default.removeItem(at: destination)
    }
}
