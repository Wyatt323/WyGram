import Foundation
import Postbox

public final class WyGramRetainedPhotoAttribute: MessageAttribute {
    public let archiveKey: Data

    public init(archiveKey: Data) {
        self.archiveKey = archiveKey
    }

    public init(decoder: PostboxDecoder) {
        self.archiveKey = decoder.decodeDataForKey("k") ?? Data()
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeData(self.archiveKey, forKey: "k")
    }
}

public extension Message {
    var wygramRetainedPhotoAttribute: WyGramRetainedPhotoAttribute? {
        return self.attributes.first { $0 is WyGramRetainedPhotoAttribute } as? WyGramRetainedPhotoAttribute
    }
}
