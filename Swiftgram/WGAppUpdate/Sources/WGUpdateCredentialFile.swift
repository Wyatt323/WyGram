// Adapted from RegramDev/Regram-ios, acb65027922c1f76818309b21ae1996754a29a94.
// MARK: WyGram — bounded reads work even when a file provider omits file-size metadata.
import Foundation

public enum WGUpdateCredentialFileKind {
    case certificate
    case profiles
    case signingMaterials

    public func acceptsExtension(_ value: String) -> Bool {
        switch self {
        case .certificate: return ["p12", "pfx"].contains(value.lowercased())
        case .profiles: return value.lowercased() == "mobileprovision"
        case .signingMaterials: return WGUpdateCredentialFileKind.certificate.acceptsExtension(value) || WGUpdateCredentialFileKind.profiles.acceptsExtension(value)
        }
    }
}

public enum WGUpdateCredentialFileError: Error {
    case invalidType, tooLarge, empty, unreadable, certificateSelection
    public var localizationKey: String {
        switch self {
        case .invalidType: return "AppUpdate.ImportWrongType"
        case .tooLarge: return "AppUpdate.ImportTooLarge"
        case .empty: return "AppUpdate.ImportEmpty"
        case .unreadable: return "AppUpdate.ImportUnreadable"
        case .certificateSelection: return "AppUpdate.CertificateSelection"
        }
    }
}

public enum WGUpdateCredentialFile {
    public static let maximumBytes = 256 * 1024

    public static func read(url: URL, kind: WGUpdateCredentialFileKind) throws -> Data {
        guard url.isFileURL, kind.acceptsExtension(url.pathExtension) else { throw WGUpdateCredentialFileError.invalidType }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file: FileHandle
        do { file = try FileHandle(forReadingFrom: url) } catch { throw WGUpdateCredentialFileError.unreadable }
        defer { try? file.close() }
        let data: Data
        do { data = try file.read(upToCount: maximumBytes + 1) ?? Data() } catch { throw WGUpdateCredentialFileError.unreadable }
        guard !data.isEmpty else { throw WGUpdateCredentialFileError.empty }
        guard data.count <= maximumBytes else { throw WGUpdateCredentialFileError.tooLarge }
        return data
    }
}
