import Foundation
import UIKit
import TelegramCore
import ChatPresentationInterfaceState

extension ChatControllerImpl {
    func wygramRepeatMessage(_ message: EngineRawMessage) {
        func request(_ controller: ChatControllerImpl) -> EnqueueMessage? {
            let state = controller.presentationInterfaceState
            guard let peer = state.renderedPeer?.peer, !state.isNotAccessible, !state.peerIsBlocked,
                  state.interfaceState.editMessage == nil else { return nil }
            switch state.subject {
            case .scheduledMessages?, .pinnedMessages?, .customChatContents?: return nil
            default: break
            }
            return wygramRepeatMessageRequest(message: message, peer: peer, threadId: controller.chatLocation.threadId,
                canSend: canSendMessagesToChat(state) && canReplyInChat(state, accountPeerId: controller.context.account.peerId),
                canForward: true, copyProtected: state.copyProtectionEnabled || state.myCopyProtectionEnabled,
                ignoreDefaultRestrictions: canBypassRestrictions(chatPresentationInterfaceState: state))
        }
        guard request(self) != nil else { return }
        if self.presentationInterfaceState.slowmodeState != nil {
            self.interfaceInteraction?.displaySlowmodeTooltip(self.chatDisplayNode.view, self.chatDisplayNode.frameForAttachmentButton() ?? self.chatDisplayNode.bounds)
            return
        }
        self.presentPaidMessageAlertIfNeeded(count: 1, completion: { [weak self] postpone in
            guard let self, let message = request(self), self.presentationInterfaceState.slowmodeState == nil else { return }
            self.sendMessages([message], postpone: postpone)
        })
    }
}
