import Foundation

// Import-as-copy URLs are already inside the application's sandbox and do not
// require a security scope. A false return from startAccessing is not itself an
// access failure; check whether the file can actually be read as well.
final class ICloudFileAccess {
    let url: URL
    private let hasSecurityScope: Bool

    init?(url: URL) {
        self.url = url
        self.hasSecurityScope = url.startAccessingSecurityScopedResource()
        guard self.hasSecurityScope || FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }
    }

    deinit {
        if self.hasSecurityScope {
            self.url.stopAccessingSecurityScopedResource()
        }
    }
}
