import CryptoKit
import XCTest
@testable import TaviCore

final class UpdateReleaseTests: XCTestCase {
    private func release(_ json: String) -> UpdateRelease? {
        UpdateRelease.parse(Data(json.utf8))
    }

    func testReadsTheVersionedArchiveAndDigest() {
        let parsed = release("""
        {"tag_name":"v1.2.0","draft":false,"prerelease":false,"assets":[
          {"name":"Tavi-1.2.0.dmg","browser_download_url":"https://example.com/Tavi-1.2.0.dmg"},
          {"name":"Tavi-1.2.0.zip","browser_download_url":"https://example.com/Tavi-1.2.0.zip","digest":"sha256:ABC123"},
          {"name":"Tavi-1.2.0.zip.sig","browser_download_url":"https://example.com/Tavi-1.2.0.zip.sig"}
        ]}
        """)
        XCTAssertEqual(parsed, UpdateRelease(
            version: "1.2.0", archive: URL(string: "https://example.com/Tavi-1.2.0.zip")!, sha256: "abc123",
            signature: URL(string: "https://example.com/Tavi-1.2.0.zip.sig")!
        ))
    }

    func testLeavesAMissingOrInsecureSignatureUnset() {
        let unsigned = release(#"{"tag_name":"v1.2.0","assets":[{"name":"Tavi-1.2.0.zip","browser_download_url":"https://e.com/a.zip"}]}"#)
        XCTAssertNil(unsigned?.signature)
        XCTAssertNil(unsigned?.sha256)
        let plain = release(#"{"tag_name":"v1.2.0","assets":[{"name":"Tavi-1.2.0.zip","browser_download_url":"https://e.com/a.zip"},{"name":"Tavi-1.2.0.zip.sig","browser_download_url":"http://e.com/a.sig"}]}"#)
        XCTAssertNil(plain?.signature)
    }

    func testRequiresTheDigestToMatch() {
        let archive = Data("archive".utf8)
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        func release(_ sha256: String?) -> UpdateRelease {
            UpdateRelease(version: "1.2.0", archive: URL(string: "https://e.com")!, sha256: sha256)
        }
        XCTAssertTrue(release(digest).matchesDigest(archive))
        XCTAssertFalse(release(digest).matchesDigest(Data("other".utf8)))
        XCTAssertFalse(release(nil).matchesDigest(archive))
    }

    func testAcceptsOnlyTheKeyHoldersSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let archive = Data("archive".utf8)
        let signature = try key.signature(for: archive)
        let publicKey = key.publicKey.rawRepresentation
        XCTAssertTrue(UpdateRelease.isSigned(archive, signature: signature, publicKey: publicKey))
        XCTAssertFalse(UpdateRelease.isSigned(Data("tampered".utf8), signature: signature, publicKey: publicKey))
        let stranger = try Curve25519.Signing.PrivateKey().signature(for: archive)
        XCTAssertFalse(UpdateRelease.isSigned(archive, signature: stranger, publicKey: publicKey))
        XCTAssertFalse(UpdateRelease.isSigned(archive, signature: Data(), publicKey: publicKey))
        XCTAssertFalse(UpdateRelease.isSigned(archive, signature: signature, publicKey: Data([1, 2, 3])))
    }

    func testIgnoresReleasesWithoutAMatchingSecureArchive() {
        XCTAssertNil(release(#"{"tag_name":"v1.2.0","assets":[{"name":"Tavi-1.1.0.zip","browser_download_url":"https://e.com/a.zip"}]}"#))
        XCTAssertNil(release(#"{"tag_name":"v1.2.0","assets":[{"name":"Tavi-1.2.0.zip","browser_download_url":"http://e.com/a.zip"}]}"#))
        XCTAssertNil(release(#"{"tag_name":"v1.2.0","prerelease":true,"assets":[{"name":"Tavi-1.2.0.zip","browser_download_url":"https://e.com/a.zip"}]}"#))
        XCTAssertNil(release(#"{"tag_name":"nightly","assets":[]}"#))
        XCTAssertNil(release("not json"))
    }

    func testComparesVersionsNumerically() {
        func newer(_ candidate: String, _ current: String) -> Bool {
            UpdateRelease(version: candidate, archive: URL(string: "https://e.com")!, sha256: nil).isNewer(than: current)
        }
        XCTAssertTrue(newer("1.0.10", "1.0.9"))
        XCTAssertTrue(newer("1.1", "1.0.9"))
        XCTAssertFalse(newer("1.0", "1.0.0"))
        XCTAssertFalse(newer("1.0.0", "1.0.1"))
        XCTAssertFalse(newer("1.0.0-beta", "0.9"))
    }
}
