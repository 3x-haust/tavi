import Foundation

/// The newest published release, read from GitHub's "latest release" response.
public struct UpdateRelease: Equatable {
    public let version: String
    public let archive: URL
    /// SHA-256 of the archive as GitHub reports it, when it does.
    public let sha256: String?

    public init(version: String, archive: URL, sha256: String?) {
        self.version = version
        self.archive = archive
        self.sha256 = sha256
    }

    /// Tags look like `v1.0.1`; the release must carry `Tavi-1.0.1.zip`.
    public static func parse(_ data: Data) -> UpdateRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard components(version) != nil,
              let asset = (json["assets"] as? [[String: Any]])?.first(where: { $0["name"] as? String == "Tavi-\(version).zip" }),
              let link = asset["browser_download_url"] as? String, let archive = URL(string: link),
              archive.scheme == "https" else { return nil }
        let digest = asset["digest"] as? String
        let sha256 = digest?.hasPrefix("sha256:") == true ? String(digest!.dropFirst(7)).lowercased() : nil
        return UpdateRelease(version: version, archive: archive, sha256: sha256)
    }

    public func isNewer(than current: String) -> Bool {
        guard let mine = Self.components(version), let theirs = Self.components(current) else { return false }
        for index in 0..<max(mine.count, theirs.count) {
            let a = index < mine.count ? mine[index] : 0
            let b = index < theirs.count ? theirs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        return parts.map { $0! }
    }
}
