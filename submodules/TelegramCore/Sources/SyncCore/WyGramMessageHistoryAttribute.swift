import Postbox

public final class WyGramMessageHistoryAttribute: MessageAttribute {
    public let deletedAt: Int32?
    public let hasPreviousVersions: Bool
    public init(deletedAt: Int32?, hasPreviousVersions: Bool) {
        self.deletedAt = deletedAt; self.hasPreviousVersions = hasPreviousVersions
    }
    public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeOptionalInt32ForKey("d")
        self.hasPreviousVersions = decoder.decodeBoolForKey("e", orElse: false)
    }
    public func encode(_ encoder: PostboxEncoder) {
        if let deletedAt = self.deletedAt { encoder.encodeInt32(deletedAt, forKey: "d") } else { encoder.encodeNil(forKey: "d") }
        encoder.encodeBool(self.hasPreviousVersions, forKey: "e")
    }
}

public extension Message {
    var wygramHistoryAttribute: WyGramMessageHistoryAttribute? {
        return self.attributes.first { $0 is WyGramMessageHistoryAttribute } as? WyGramMessageHistoryAttribute
    }
}
