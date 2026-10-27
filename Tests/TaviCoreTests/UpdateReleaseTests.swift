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
          {"name":"Tavi-1.2.0.zip","browser_download_url":"https://example.com/Tavi-1.2.0.zip","digest":"sha256:ABC123"}
        ]}
        """)
        XCTAssertEqual(parsed, UpdateRelease(
            version: "1.2.0", archive: URL(string: "https://example.com/Tavi-1.2.0.zip")!, sha256: "abc123"
        ))
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
