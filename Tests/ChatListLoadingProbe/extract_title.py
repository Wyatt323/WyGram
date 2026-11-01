from pathlib import Path
import sys

controller = next(Path(p) for p in sys.argv[2:] if p.endswith('/ChatListController.swift'))
source = controller.read_text()
start = source.index('            var checkProxy = false\n            switch networkState {')
end = source.index('\n            if titleContent.hasProxy {', start)
body = source[start:end]
prefix = '''import TelegramCore
import TelegramPresentationData
import ChatListTitleView

// Extracted verbatim from the production chat-list header's state selection.
func productionTitle(networkState: AccountNetworkState, localLoading: WyGramChatListLoading.Phase, presentationData: PresentationData) -> NetworkStatusTitle {
    let defaultTitle = presentationData.strings.DialogList_Title
    let isRoot = true
    let hasProxy = false
    let connectsViaProxy = false
    let isPasscodeSet = false
    let isManuallyLocked = false
    let peerStatus: NetworkStatusTitle.Status? = nil
    var titleContent: NetworkStatusTitle
'''
Path(sys.argv[1]).write_text(prefix + body + '\n    _ = checkProxy\n    return titleContent\n}\n')
