// Adapted from RegramDev/Regram-ios, acb65027922c1f76818309b21ae1996754a29a94.
import Foundation

@main struct CredentialFileTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = Data([0x30, 0x82, 0x01, 0x00])
        for name in ["certificate.p12", "certificate.P12", "证书.pfx", "profile.mobileprovision"] {
            let url = directory.appendingPathComponent(name)
            try contents.write(to: url)
            let kind: WGUpdateCredentialFileKind = name.hasSuffix("mobileprovision") ? .profiles : .certificate
            let read = try WGUpdateCredentialFile.read(url: url, kind: kind)
            assert(read == contents)
            let mixed = try WGUpdateCredentialFile.read(url: url, kind: .signingMaterials)
            assert(mixed == contents)
        }
        let wrong = directory.appendingPathComponent("certificate.txt")
        try contents.write(to: wrong)
        do { _ = try WGUpdateCredentialFile.read(url: wrong, kind: .certificate); fatalError("Wrong type accepted") } catch WGUpdateCredentialFileError.invalidType {}
        let empty = directory.appendingPathComponent("empty.p12")
        try Data().write(to: empty)
        do { _ = try WGUpdateCredentialFile.read(url: empty, kind: .certificate); fatalError("Empty file accepted") } catch WGUpdateCredentialFileError.empty {}
        let large = directory.appendingPathComponent("large.p12")
        try Data(repeating: 1, count: WGUpdateCredentialFile.maximumBytes + 1).write(to: large)
        do { _ = try WGUpdateCredentialFile.read(url: large, kind: .certificate); fatalError("Oversize file accepted") } catch WGUpdateCredentialFileError.tooLarge {}
        let missing = directory.appendingPathComponent("missing.p12")
        do { _ = try WGUpdateCredentialFile.read(url: missing, kind: .certificate); fatalError("Missing file accepted") } catch WGUpdateCredentialFileError.unreadable {}
        print("Credential file checks passed: P12/PFX, profiles, mixed-case extensions, Unicode, bounded reads and explicit failures.")
    }
}
