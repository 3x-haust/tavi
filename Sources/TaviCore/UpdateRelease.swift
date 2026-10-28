import CryptoKit
import Foundation

/// The newest published release, read from GitHub's "latest release" response.
public struct UpdateRelease: Equatable {
    public let version: String
    public let archive: URL
    /// SHA-256 of the archive as GitHub reports it, when it does.
    public let sha256: String?
    /// The maintainer's detached Ed25519 signature of the archive, `Tavi-<version>.zip.sig`.
    public let signature: URL?

    public init(version: String, archive: URL, sha256: String?, signature: URL? = nil) {
        self.version = version
        self.archive = archive
        self.sha256 = sha256
        self.signature = signature
    }

    /// Tags look like `v1.0.1`; the release must carry `Tavi-1.0.1.zip`.
    public static func parse(_ data: Data) -> UpdateRelease? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
              let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assets = json["assets"] as? [[String: Any]] ?? []
        func secure(_ name: String) -> (asset: [String: Any], url: URL)? {
            guard let asset = assets.first(where: { $0["name"] as? String == name }),
                  let link = asset["browser_download_url"] as? String, let url = URL(string: link),
                  url.scheme == "https" else { return nil }
            return (asset, url)
        }
        guard components(version) != nil, let archive = secure("Tavi-\(version).zip") else { return nil }
        let digest = archive.asset["digest"] as? String
        let sha256 = digest?.hasPrefix("sha256:") == true ? String(digest!.dropFirst(7)).lowercased() : nil
        return UpdateRelease(version: version, archive: archive.url, sha256: sha256,
                             signature: secure("Tavi-\(version).zip.sig")?.url)
    }

    /// Whether the downloaded archive matches GitHub's digest; a release without one never matches.
    public func matchesDigest(_ archive: Data) -> Bool {
        guard let sha256 else { return false }
        return SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined() == sha256
    }

    /// Whether `signature` is the holder of `publicKey` (raw 32-byte Ed25519) signing `archive`.
    public static func isSigned(_ archive: Data, signature: Data, publicKey: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else { return false }
        return key.isValidSignature(signature, for: archive)
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
