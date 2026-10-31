// Adapted from RegramDev/Regram-ios, acb65027922c1f76818309b21ae1996754a29a94.
import Foundation

@main struct UpdateReleaseTests {
    static let hash = String(repeating: "a", count: 64)
    static func fixture(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
        var value: [String: Any] = ["tag_name": "v13.0-b34592", "draft": false, "prerelease": false, "body": "Update notes", "assets": [["name": "WyGram.13.0.ipa", "size": 89000000, "digest": "sha256:" + hash, "browser_download_url": "https://github.com/Wyatt323/WyGram/releases/download/v13.0-b34592/WyGram.13.0.ipa"]]]
        mutate(&value)
        return try JSONSerialization.data(withJSONObject: value)
    }
    static func rejected(_ data: Data) {
        do { _ = try WGUpdateRelease.parseGitHub(data); fatalError("Invalid release accepted") } catch {}
    }
    static func main() throws {
        let release = try WGUpdateRelease.parseGitHub(fixture())
        try release.validateCachedMetadata()
        let spaced = try WGUpdateRelease.parseGitHub(fixture { value in
            var assets = value["assets"] as! [[String: Any]]
            assets[0]["name"] = "WyGram 13.0.ipa"
            assets[0]["browser_download_url"] = "https://github.com/Wyatt323/WyGram/releases/download/v13.0-b34592/WyGram%2013.0.ipa"
            value["assets"] = assets
        })
        assert(spaced.version == release.version && spaced.build == release.build)
        try spaced.validateCachedMetadata()
        rejected(try fixture { value in
            var assets = value["assets"] as! [[String: Any]]
            assets[0]["name"] = "WyGram.13.1.ipa"
            value["assets"] = assets
        })
        for suffix in ["?other=1", "#other"] {
            rejected(try fixture { value in
                var assets = value["assets"] as! [[String: Any]]
                assets[0]["browser_download_url"] = (assets[0]["browser_download_url"] as! String) + suffix
                value["assets"] = assets
            })
        }
        assert(release.isNewer(version: "13.0", build: "34591"))
        assert(!release.isNewer(version: "13.0", build: "34592"))
        assert(!release.isNewer(version: "13.0", build: "34593"))
        assert(!release.isNewer(version: "14.0", build: "1"))
        assert(release.isNewer(version: "12.9", build: "99999"))
        assert(!release.isNewer(version: "unknown", build: "unknown"))
        rejected(try fixture { $0["draft"] = true })
        rejected(try fixture { $0["prerelease"] = true })
        rejected(try fixture { $0["tag_name"] = "v13.0-b99999" })
        rejected(try fixture { value in var assets = value["assets"] as! [[String: Any]]; assets.append(assets[0]); value["assets"] = assets })
        for mutation in ["digest": "sha256:wrong", "browser_download_url": "http://github.com/Wyatt323/WyGram/releases/download/v13.0-b34592/WyGram.13.0.ipa"] {
            rejected(try fixture { value in var assets = value["assets"] as! [[String: Any]]; assets[0][mutation.key] = mutation.value; value["assets"] = assets })
        }
        rejected(try fixture { value in var assets = value["assets"] as! [[String: Any]]; assets[0].removeValue(forKey: "digest"); value["assets"] = assets })
        let withRetiredPackage = try fixture { value in
            var assets = value["assets"] as! [[String: Any]]
            var retired = assets[0]
            retired["name"] = "WyGram-Other-13.0-b34592.ipa"
            retired["browser_download_url"] = "https://github.com/Wyatt323/WyGram/releases/download/v13.0-b34592/WyGram-Other-13.0-b34592.ipa"
            assets.append(retired)
            value["assets"] = assets
        }
        let selectedBase = try WGUpdateRelease.parseGitHub(withRetiredPackage)
        assert(selectedBase.downloadURL == release.downloadURL)
        rejected(try fixture { value in
            var assets = value["assets"] as! [[String: Any]]
            assets[0]["name"] = "WyGram-Other-13.0-b34592.ipa"
            value["assets"] = assets
        })
        rejected(try fixture { value in
            var assets = value["assets"] as! [[String: Any]]
            assets[0]["browser_download_url"] = "https://github.com/Wyatt323/WyGram/releases/download/v13.0-b1/WyGram.13.0.ipa"
            value["assets"] = assets
        })
        let node = WGLCSignNode.fallback[1]
        let manifest = try node.manifestURL(token: "aB1234")
        let url = try WGLCSignNode.installationURL(manifest: manifest)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        assert(url.scheme == "itms-services")
        assert(url.absoluteString.hasPrefix("itms-services://?action=download-manifest&"))
        assert(url.host?.isEmpty != false)
        assert(query.first { $0.name == "url" }?.value == manifest.absoluteString)
        for value in ["http://cf-i.lcsignx.com/ota/m/aB1234", "https://another.example.com/ota/m/aB1234", "https://cf-i.lcsignx.com/other/aB1234", "https://user:pass@cf-i.lcsignx.com/ota/m/aB1234", "https://cf-i.lcsignx.com:9443/ota/m/aB1234"] {
            do { _ = try WGLCSignNode.installationURL(manifest: URL(string: value)!); fatalError("Unsafe installation link accepted") } catch {}
        }
        do { _ = try node.manifestURL(token: "../other"); fatalError("Unsafe token accepted") } catch {}
        let packageURL = URL(string: "http://127.0.0.1:54321/token/WyGram.ipa")!
        let body = try WGLCSignNode.manifestRequest(packageURL: packageURL, bundleId: "com.example.WyGram", build: "34592")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: String]
        assert(json["ipa_url"] == packageURL.absoluteString)
        assert(Set(json.keys) == Set(["ipa_url", "bundle_id", "version", "title"]))
        let manifestBody: [String: Any] = ["items": [["assets": [["kind": "software-package", "url": packageURL.absoluteString]], "metadata": ["bundle-identifier": "com.example.WyGram", "bundle-version": "34592", "kind": "software"]]]]
        let plist = try PropertyListSerialization.data(fromPropertyList: manifestBody, format: .xml, options: 0)
        try WGLCSignNode.validateManifest(plist, bundleId: "com.example.WyGram", build: "34592", packageURL: packageURL)
        do { try WGLCSignNode.validateManifest(plist, bundleId: "com.other.app", build: "34592", packageURL: packageURL); fatalError("Wrong app manifest accepted") } catch {}
        do { try WGLCSignNode.validateManifest(plist, bundleId: "com.example.WyGram", build: "1", packageURL: packageURL); fatalError("Wrong build manifest accepted") } catch {}
        print("Update release checks passed: identity, build ordering, checksum, channel and installation URL boundaries.")
    }
}
