import Foundation
import UIKit
import Postbox
import TelegramCore
import ContextUI
import Display

let wygramRepeatMessageMode = "wygramRepeatMessage"

func wygramRepeatMessageRequest(message: EngineRawMessage, peer: Peer, threadId: Int64?, canSend: Bool, canForward: Bool, copyProtected: Bool, ignoreDefaultRestrictions: Bool) -> EnqueueMessage? {
    guard canSend, canForward, !copyProtected, peer.id == message.id.peerId,
          message.id.namespace == Namespaces.Message.Cloud,
          message.flags.intersection([.Failed, .Unsent]).isEmpty, !message.flags.isSending,
          !message.isCopyProtected(), !message.containsSecretMedia,
          message.wygramHistoryAttribute?.deletedAt == nil, message.wygramRetainedPhotoAttribute == nil else {
        return nil
    }
    var rights: [TelegramChatBannedRightsFlags] = []
    var hasMedia = false
    for media in message.media {
        if media is TelegramMediaAction || media is TelegramMediaExpiredContent {
            return nil
        } else if media is TelegramMediaImage {
            hasMedia = true
            rights.append(.banSendPhotos)
        } else if let file = media as? TelegramMediaFile {
            hasMedia = true
            if file.isSticker {
                rights.append(.banSendStickers)
            } else if file.isAnimated {
                rights.append(.banSendGifs)
            } else if file.isInstantVideo {
                rights.append(.banSendInstantVideos)
            } else if file.isVoice {
                rights.append(.banSendVoice)
            } else if file.isMusic {
                rights.append(.banSendMusic)
            } else if file.isVideo {
                rights.append(.banSendVideos)
            } else {
                rights.append(.banSendFiles)
            }
        } else if media is TelegramMediaPoll {
            hasMedia = true
            rights.append(.banSendPolls)
        } else if !(media is TelegramMediaWebpage) {
            hasMedia = true
        }
    }
    rights.append(hasMedia ? .banSendMedia : .banSendText)
    if let channel = peer as? TelegramChannel {
        if rights.contains(where: { channel.hasBannedPermission($0, ignoreDefault: ignoreDefaultRestrictions) != nil }) {
            return nil
        }
        // A forum overview has no destination topic. Repeat from an open topic.
        if channel.isForumOrMonoForum && threadId == nil {
            return nil
        }
    } else if let group = peer as? TelegramGroup {
        guard case .Member = group.membership, !rights.contains(where: group.hasBannedPermission) else {
            return nil
        }
    }
    // Exactly the pressed message, including its text/entities/caption/media.
    // The normal forward-as-copy path removes attribution; do not copy draft,
    // reply, edit or album selection state into the outgoing request.
    return .forward(source: message.id, threadId: threadId, grouping: .none, attributes: [ForwardOptionsMessageAttribute(hideNames: true, hideCaptions: false)], correlationId: nil)
}

func wygramRepeatMenuItem(languageCode: String, repeatMessage: @escaping () -> Void) -> ContextMenuItem {
    let title: String
    if languageCode.hasPrefix("zh") {
        title = languageCode.lowercased().contains("hant") ? "復讀" : "复读"
    } else {
        title = "Repeat Message"
    }
    var requested = false
    return .action(ContextMenuActionItem(text: title, icon: { theme in
        return generateTintedImage(image: UIImage(systemName: "repeat", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)), color: theme.actionSheet.primaryTextColor)
    }, action: { _, dismiss in
        guard !requested else { return }
        requested = true
        dismiss(.dismissWithoutContent)
        repeatMessage()
    }))
}
