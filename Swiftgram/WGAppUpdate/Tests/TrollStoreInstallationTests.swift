// Adapted from RegramDev/Regram-ios, acb65027922c1f76818309b21ae1996754a29a94.
import Foundation

@main struct TrollStoreInstallationTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = directory.appendingPathComponent("WyGram.app")
        assert(WGUpdateInstallationMethod.detected(bundleURL: bundle) == .certificate)
        try Data().write(to: directory.appendingPathComponent("_TrollStore"))
        assert(WGUpdateInstallationMethod.detected(bundleURL: bundle) == .trollStore)
        let package = URL(string: "http://127.0.0.1:39123/random-route/WyGram.ipa")!
        let installation = try WGTrollStoreInstallation.installationURL(packageURL: package)
        let components = URLComponents(url: installation, resolvingAgainstBaseURL: false)!
        assert(installation.absoluteString.hasPrefix("apple-magnifier://install?"))
        assert(components.queryItems == [URLQueryItem(name: "url", value: package.absoluteString)])
        for invalid in ["https://github.com/example/WyGram.ipa", "http://192.168.1.1:123/WyGram.ipa", "http://127.0.0.1/WyGram.ipa", "http://name:password@127.0.0.1:123/WyGram.ipa", "http://127.0.0.1:123/WyGram.ipa?other=1", "http://127.0.0.1:123/WyGram.zip"] {
            do { _ = try WGTrollStoreInstallation.installationURL(packageURL: URL(string: invalid)!); fatalError("Unexpected installer address accepted") }
            catch WGUpdateError.invalidArchive {}
        }
        assert(WGUpdateInstallationMethod(rawValue: "trollStore") == .trollStore)
        print("TrollStore checks passed: own installation marker, certificate fallback, exact scheme/query and local verified-package routes.")
    }
}
