import Postbox
import TelegramCore

func legacyGalleryTags(_ message: Message) -> MessageTags? {
    //TODO:rewrite to take all media (effectiveMedia returns all rich-text media; we stop at the first)
    for media in message.effectiveMedia {
        switch media {
        case _ as TelegramMediaImage:
            return .photoOrVideo
        case let file as TelegramMediaFile:
            if file.isVideo {
                if file.isAnimated {
                    return .gif
                } else {
                    return .photoOrVideo
                }
            } else if file.isVoice {
                return .voiceOrInstantVideo
            } else if file.isSticker {
                return nil
            } else {
                return .file
            }
        default:
            break
        }
    }
    return nil
}

func currentGalleryTags(_ message: Message) -> MessageTags? {
    // Retained disappearing photos keep their original (untagged) history entry.
    // Open that exact message instead of querying the cloud photo/video index,
    // which excludes it and can leave the gallery empty. This also covers copies
    // saved by earlier WyGram versions without rewriting their local records.
    if message.wygramRetainedPhotoAttribute != nil {
        return nil
    }
    //TODO:rewrite to take all media (effectiveMedia returns all rich-text media; we stop at the first)
    for media in message.effectiveMedia {
        switch media {
        case _ as TelegramMediaImage:
            return .photoOrVideo
        case let file as TelegramMediaFile:
            if file.isVideo {
                if file.isAnimated {
                    return .gif
                } else {
                    return .photoOrVideo
                }
            } else if file.isVoice {
                return .voiceOrInstantVideo
            } else if file.isSticker {
                return nil
            } else {
                return .file
            }
        default:
            break
        }
    }
    return nil
}
