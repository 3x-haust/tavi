import Foundation
import XCTest
@testable import TaviCore

final class InputMethodPackageTests: XCTestCase {
    private var root: URL!
    private enum TestFailure: Error { case registration }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testFreshInstallationValidatesAndRegistersCopiedBundle() async throws {
        let source = try fixture("source.app", build: "2")
        let destination = root.appendingPathComponent("Input Methods/Tavi.app")
        var registered = false
        try await InputMethodPackage.install(source: source, destination: destination) { installed in
            XCTAssertEqual(installed, destination)
            XCTAssertEqual(try InputMethodPackage.version(at: installed).build, "2")
            registered = true
        }
        XCTAssertTrue(registered)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path),
                       ["Tavi.app"])
    }

    func testUpdatePreservesDataOutsideComponentBundle() async throws {
        let source = try fixture("source.app", build: "2")
        let destination = try fixture("Tavi.app", build: "1")
        let words = root.appendingPathComponent("words.json")
        let data = Data("personal data".utf8)
        try data.write(to: words)
        try await InputMethodPackage.install(source: source, destination: destination) { _ in }
        XCTAssertEqual(try InputMethodPackage.version(at: destination).build, "2")
        XCTAssertEqual(try Data(contentsOf: words), data)
    }

    func testFailedRegistrationRestoresAndRegistersPreviousBundle() async throws {
        let source = try fixture("source.app", build: "2")
        let destination = try fixture("Tavi.app", build: "1")
        var calls: [String] = []
        do {
            try await InputMethodPackage.install(source: source, destination: destination) { installed in
                let build = try InputMethodPackage.version(at: installed).build
                calls.append(build)
                if build == "2" { throw TestFailure.registration }
            }
            XCTFail("Expected registration failure")
        } catch TestFailure.registration {}
        XCTAssertEqual(calls, ["2", "1"])
        XCTAssertEqual(try InputMethodPackage.version(at: destination).build, "1")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".Tavi") }))
    }

    func testFailedFirstInstallLeavesNoPartialDestination() async throws {
        let source = try fixture("source.app", build: "2")
        let destination = root.appendingPathComponent("Tavi.app")
        do {
            try await InputMethodPackage.install(source: source, destination: destination) { _ in
                throw TestFailure.registration
            }
            XCTFail("Expected registration failure")
        } catch TestFailure.registration {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testForeignBundleIsNotOverwrittenOrRemoved() async throws {
        let source = try fixture("source.app", build: "2")
        let destination = try fixture("Tavi.app", build: "1", identifier: "example.foreign")
        let original = try Data(contentsOf: destination.appendingPathComponent("Contents/Info.plist"))
        do {
            try await InputMethodPackage.install(source: source, destination: destination) { _ in
                XCTFail("Must not register")
            }
            XCTFail("Must not overwrite a foreign bundle")
        } catch InputMethodPackage.Failure.foreignBundle {}
        XCTAssertThrowsError(try InputMethodPackage.remove(at: destination))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Contents/Info.plist")), original)
    }

    func testInvalidSourceCannotReplaceExistingComponent() async throws {
        let source = try fixture("source.app", build: "2")
        let destination = try fixture("Tavi.app", build: "1")
        try FileManager.default.removeItem(at: source.appendingPathComponent("Contents/MacOS/Tavi"))
        do {
            try await InputMethodPackage.install(source: source, destination: destination) { _ in }
            XCTFail("Must reject an incomplete source")
        } catch InputMethodPackage.Failure.invalidBundle {}
        XCTAssertEqual(try InputMethodPackage.version(at: destination).build, "1")
    }

    func testRemovalOnlyRemovesOwnedComponent() throws {
        let destination = try fixture("Tavi.app", build: "2")
        let words = root.appendingPathComponent("words.json")
        try Data("keep".utf8).write(to: words)
        try InputMethodPackage.remove(at: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: words.path))
    }

    func testApplicationsLocationDoesNotAcceptVolumeOrSimilarPrefix() {
        let home = URL(fileURLWithPath: "/Users/test")
        for path in ["/Applications/Tavi.app", "/Applications/Utilities/Tavi.app", "/Users/test/Applications/Tavi.app"] {
            XCTAssertTrue(InputMethodPackage.isApplicationLocation(URL(fileURLWithPath: path), home: home))
        }
        for path in ["/Volumes/Tavi/Tavi.app", "/Applications-other/Tavi.app", "/tmp/Tavi.app"] {
            XCTAssertFalse(InputMethodPackage.isApplicationLocation(URL(fileURLWithPath: path), home: home))
        }
    }

    private func fixture(_ name: String, build: String, identifier: String = "dev.3xhaust.inputmethod.tavi") throws -> URL {
        let app = root.appendingPathComponent(name)
        let executable = app.appendingPathComponent("Contents/MacOS/Tavi")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test executable \(build)".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let info = [
            "CFBundleIdentifier": identifier, "CFBundleExecutable": "Tavi",
            "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": build,
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }
}
