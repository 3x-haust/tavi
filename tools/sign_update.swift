import CryptoKit
import Foundation

// Signs update archives with the maintainer's Ed25519 key, kept outside the repository.
//   swift tools/sign_update.swift generate <key-file>
//       Creates the key (mode 0600) and prints the public key for TaviUpdatePublicKey.
//   swift tools/sign_update.swift sign <key-file> <archive> <public-key>
//       Writes <archive>.sig and checks it against the public key the app ships with.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sign_update: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
switch (arguments.first, arguments.count) {
case ("generate", 2):
    let path = arguments[arguments.startIndex + 1]
    guard !FileManager.default.fileExists(atPath: path) else { fail("\(path) already exists") }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true
    )
    guard FileManager.default.createFile(
        atPath: path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: 0o600]
    ) else { fail("cannot write \(path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case ("sign", 4):
    let values = Array(arguments.dropFirst())
    guard let text = try? String(contentsOfFile: values[0], encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("cannot read key \(values[0])") }
    guard key.publicKey.rawRepresentation.base64EncodedString() == values[2] else {
        fail("\(values[0]) does not match TaviUpdatePublicKey; installed copies would reject this release")
    }
    let archive = try Data(contentsOf: URL(fileURLWithPath: values[1]))
    let signature = try key.signature(for: archive)
    guard key.publicKey.isValidSignature(signature, for: archive) else { fail("signature does not verify") }
    try signature.write(to: URL(fileURLWithPath: values[1] + ".sig"))
default:
    fail("usage: generate <key-file> | sign <key-file> <archive> <public-key>")
}
