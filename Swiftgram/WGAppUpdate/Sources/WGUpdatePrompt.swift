// Adapted from RegramDev/Regram-ios, acb65027922c1f76818309b21ae1996754a29a94.
// MARK: WyGram — discovery and installation are different foreground prompts.
import Foundation

public struct WGUpdatePrompt: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case available, ready, failed(String)
        var identifier: String {
            switch self { case .available: return "available"; case .ready: return "ready"; case .failed: return "failed" }
        }
    }
    public let release: WGUpdateRelease
    public let kind: Kind
    public init(release: WGUpdateRelease, kind: Kind) { self.release = release; self.kind = kind }
}

public struct WGUpdatePromptPolicy {
    private var claimed = Set<String>()
    public init() {}
    public mutating func claim(_ prompt: WGUpdatePrompt, enabled: Bool, busy: Bool, currentRelease: WGUpdateRelease?, currentKind: WGUpdatePrompt.Kind?) -> Bool {
        guard enabled, !busy, currentKind == prompt.kind, currentRelease?.hasSameArtifact(as: prompt.release) == true else { return false }
        let key = prompt.release.version + ":" + String(prompt.release.build) + ":" + prompt.release.sha256 + ":" + prompt.kind.identifier
        return claimed.insert(key).inserted
    }
}
