import Foundation
import UIKit
import TelegramCore
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit
import SGSimpleSettings
import TelegramPresentationData

// The network is a fixture: no Telegram connection, login or credentials.
final class ProbeNetwork {
    private let records = Atomic(value: [String]())
    var validationCalls=0
    var requests: [String] { self.records.with { $0 } }
    func clear() { _ = self.records.swap([]) }
    func request<T>(_ function: (FunctionDescription, Buffer, DeserializeFunctionResponse<T>)) -> Signal<T, MTRpcError> {
        return Signal { subscriber in
            var label = function.0.name
            if label == "account.updateStatus", let offline = function.0.parameters.first?.1.value as? Api.Bool {
                if case .boolTrue = offline { label += ":offline" } else { label += ":online" }
            }
            _ = self.records.modify { current in var next=current; next.append(label); return next }
            let value: Any
            switch function.0.name {
            case "messages.readHistory", "messages.readMessageContents": value = Api.messages.AffectedMessages.affectedMessages(.init(pts: 1, ptsCount: 0))
            case "stories.readStories": value = [Int32]()
            default: value = Api.Bool.boolTrue
            }
            if let value = value as? T { subscriber.putNext(value); subscriber.putCompletion() }
            else { subscriber.putError(MTRpcError(errorCode: 400, errorDescription: "PROBE_NO_RESPONSE")) }
            return EmptyDisposable
        }
    }
}
enum ProbeUpdate { case updatePts(pts: Int32, ptsCount: Int32) }
enum ProbeStoryUpdate { case read(peerId: PeerId, maxId: Int32) }
final class ProbeStateManager {
    var storyReads = 0
    func addUpdateGroups(_ groups: [ProbeUpdate]) {}
    func addCustomOperation<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
    func injectStoryUpdates(updates: [ProbeStoryUpdate]) { self.storyReads += updates.count }
}
final class ProbeAccount {
    let postbox: Postbox
    let network: ProbeNetwork
    let stateManager = ProbeStateManager()
    init(_ postbox: Postbox, _ network: ProbeNetwork) { self.postbox = postbox; self.network = network }
}
// Validation is unchanged production code and depends on internal API decoding.
// The fixture observes whether the new dispatcher delegates to it, without fetching a dialog.
func validatePeerReadState(network:ProbeNetwork,postbox:Postbox,stateManager:ProbeStateManager,peerId:PeerId) -> Signal<Never,PeerReadStateValidationError> {
    network.validationCalls += 1
    return .complete()
}
private enum Failure: Error { case check(String) }
private let peer = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(2001))
private let channelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(3001))
private let secretId = PeerId(namespace: Namespaces.Peer.SecretChat, id: PeerId.Id._internalFromInt64Value(4001))

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        initializeAccountManagement()
        SGSimpleSettings.shared.storyStealthMode = false
        return true
    }
}
@objc(WyGramGhostModeProbeScene) final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var disposables: [Disposable] = []
    var postboxes: [Postbox] = []
    var checks: [[String: Any]] = []
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    func check(_ label: String, _ value: Bool) throws {
        self.checks.append(["name":label,"passed":value])
        if !value { throw Failure.check(label) }
    }
    func value<T>(_ signal: Signal<T, NoError>) async -> T {
        await withCheckedContinuation { continuation in
            disposables.append((signal |> take(1)).start(next: { continuation.resume(returning: $0) }))
        }
    }
    func complete<T, E>(_ signal: Signal<T, E>) async {
        await withCheckedContinuation { continuation in
            disposables.append(signal.start(error: { _ in continuation.resume() }, completed: { continuation.resume() }))
        }
    }
    func pause() async { try? await Task.sleep(nanoseconds: 200_000_000) }
    func open(_ name: String) async -> Postbox {
        let encryption = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: .init(data: Data(repeating: 7, count: 32))!, salt: .init(data: Data(repeating: 9, count: 16))!)
        let path = documents.appendingPathComponent(ProcessInfo.processInfo.environment["WYGRAM_GHOST_STORE"] ?? "fixture").appendingPathComponent(name).appendingPathComponent("postbox").path
        let signal = openPostbox(basePath: path, seedConfiguration: telegramPostboxSeedConfiguration, encryptionParameters: encryption, timestampForAbsoluteTimeBasedOperations: Int32(Date().timeIntervalSince1970), isMainProcess: true, isTemporary: false, isReadOnly: false, useCopy: false, useCaches: true, removeDatabaseOnError: false)
        |> mapToSignal { result -> Signal<Postbox, NoError> in
            if case let .postbox(postbox) = result { return .single(postbox) }; return .complete()
        }
        let box = await value(signal); postboxes.append(box); return box
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        window?.rootViewController = UIViewController(); window?.makeKeyAndVisible()
        Task { @MainActor in
            do { try await self.run(); self.report(true,nil) }
            catch { self.report(false,String(describing:error)) }
        }
    }
    func run() async throws {
        let a = await open("a"), b = await open("b")
        if CommandLine.arguments.contains("--restart") {
            let saved = await value(FixturewygramGhostModeSettings(postbox:a))
            let other = await value(FixturewygramGhostModeSettings(postbox:b))
            try check("four-account-switches-survive-process-restart", saved == .init(hideStoryViews:true,hideOnline:true,hideInputActivity:true,hideReadReceipts:true))
            try check("other-account-remains-independent-after-restart", other == .init())
            return
        }
        if CommandLine.arguments.contains("--ui") {
            await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideStoryViews=true;$0.hideOnline=true;$0.hideInputActivity=true;$0.hideReadReceipts=true })
            try await showSettings(a)
            return
        }
        let defaults = await value(FixturewygramGhostModeSettings(postbox:a))
        try check("new-account-defaults-all-off", defaults == .init())
        let partial = try JSONDecoder().decode(FixtureWyGramGhostModeSettings.self, from: Data("{\"hideOnline\":true}".utf8))
        try check("missing-new-fields-decode-without-enabling-them", partial == .init(hideOnline:true))
        var observed: [FixtureWyGramGhostModeSettings] = []
        disposables.append(FixturewygramGhostModeSettings(postbox:a).start(next:{ observed.append($0) }))
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideStoryViews=true })
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideOnline=true })
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideInputActivity=true })
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideReadReceipts=true })
        let all = await value(FixturewygramGhostModeSettings(postbox:a))
        try check("independent-transactional-toggles-preserve-earlier-writes", all == .init(hideStoryViews:true,hideOnline:true,hideInputActivity:true,hideReadReceipts:true))
        try check("settings-observer-delivers-saved-change", observed.last==all)
        let other = await value(FixturewygramGhostModeSettings(postbox:b))
        try check("settings-do-not-leak-to-other-account", other == .init())
        let c=await open("legacy")
        SGSimpleSettings.shared.storyStealthMode=true
        let legacy=await value(FixturewygramGhostModeSettings(postbox:c))
        try check("legacy-local-story-choice-migrates",legacy.hideStoryViews && !legacy.hideReadReceipts)
        SGSimpleSettings.shared.canUseStealthMode=false
        let frozenLegacy=await value(FixturewygramGhostModeSettings(postbox:c))
        try check("inherited-story-choice-frozen-before-any-manual-toggle",frozenLegacy.hideStoryViews)
        let savedAfterRemote=await value(FixturewygramGhostModeSettings(postbox:a))
        try check("saved-per-account-choice-independent-of-remote-flag",savedAfterRemote==all)
        SGSimpleSettings.shared.storyStealthMode=false
        SGSimpleSettings.shared.canUseStealthMode=true
        let network = ProbeNetwork()
        let state = ProbeStateManager()
        let account = ProbeAccount(a,network)
        await complete(a.transaction { transaction in
            let user = TelegramUser(id:peer,accessHash:.personal(123),firstName:"Fixture",lastName:nil,username:nil,phone:nil,photo:[],botInfo:nil,restrictionInfo:nil,flags:[],emojiStatus:nil,usernames:[],storiesHidden:nil,nameColor:nil,backgroundEmojiId:nil,profileColor:nil,profileBackgroundEmojiId:nil,subscriberCount:nil,verificationIconFileId:nil)
            let channel=TelegramChannel(id:channelId,accessHash:.personal(321),title:"Fixture group",username:nil,photo:[],creationDate:0,version:0,participationStatus:.member,info:.group(.init(flags:[])),flags:[],restrictionInfo:nil,adminRights:nil,bannedRights:nil,defaultBannedRights:nil,usernames:[],storiesHidden:nil,nameColor:nil,backgroundEmojiId:nil,profileColor:nil,profileBackgroundEmojiId:nil,emojiStatus:nil,approximateBoostLevel:nil,subscriptionUntilDate:nil,verificationIconFileId:nil,sendPaidMessageStars:nil,linkedMonoforumId:nil)
            let secret=TelegramSecretChat(id:secretId,creationDate:0,regularPeerId:peer,accessHash:999,role:.participant,embeddedState:.active,messageAutoremoveTimeout:nil)
            transaction.updatePeersInternal([user,channel,secret],update:{ _,updated in updated })
            transaction.setPeerStoryState(peerId:peer,state:Stories.PeerState(maxReadId:0).postboxRepresentation)
            transaction.updatePeerPresencesInternal(presences:[peer:TelegramUserPresence(status:.present(until:Int32.max),lastActivity:0)], merge:{ _,updated in updated })
        })
        // Real production presence manager: enabling hides immediately; disabling resumes.
        let foreground = ValuePromise<Bool>(true,ignoreRepeated:true)
        var manager: AccountPresenceManager? = AccountPresenceManager(shouldKeepOnlinePresence:foreground.get(),postbox:a,network:network)
        await pause()
        try check("cold-start-hidden-presence-requests-offline", network.requests == ["account.updateStatus:offline"])
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideOnline=false }); await pause()
        try check("disabling-hide-online-resumes-presence", network.requests.last=="account.updateStatus:online")
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideOnline=true }); await pause()
        try check("enabling-hide-online-goes-offline-without-restart", network.requests.last=="account.updateStatus:offline")
        network.clear();foreground.set(false);foreground.set(true);await pause()
        try check("foreground-switch-cannot-send-online-while-hidden", !network.requests.contains("account.updateStatus:online"))
        _ = manager?.isPerformingUpdate(); manager=nil
        network.clear()
        // Exercise actual ordinary and pinned story code; keep local ring state.
        await complete(_internal_markStoryAsSeen(account:account,peerId:peer,id:10,asPinned:false))
        let story = await value(a.transaction { $0.getPeerStoryState(peerId:peer)?.entry.get(Stories.PeerState.self)?.maxReadId })
        let queued = await value(a.mergedOperationLogView(tag:OperationLogTags.SynchronizeViewStories,limit:10))
        try check("hidden-story-still-clears-local-unread-ring", story==10 && account.stateManager.storyReads==1)
        try check("hidden-story-does-not-queue-server-receipt", queued.entries.isEmpty)
        await complete(_internal_markStoryAsSeen(account:account,peerId:peer,id:11,asPinned:true))
        try check("hidden-pinned-story-does-not-increment-view", network.requests.isEmpty)
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideStoryViews=false })
        await complete(_internal_markStoryAsSeen(account:account,peerId:peer,id:12,asPinned:true))
        try check("normal-pinned-story-keeps-server-request", network.requests==["stories.incrementStoryViews"])
        network.clear()
        await complete(_internal_markStoryAsSeen(account:account,peerId:peer,id:13,asPinned:false))
        let pending = await value(a.mergedOperationLogView(tag:OperationLogTags.SynchronizeViewStories,limit:10))
        try check("normal-story-queues-existing-view-operation", pending.entries.count==1)
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideStoryViews=true })
        let worker=managedSynchronizeViewStoriesOperations(postbox:a,network:network,stateManager:state).start()
        await pause()
        let drained = await value(a.mergedOperationLogView(tag:OperationLogTags.SynchronizeViewStories,limit:10))
        try check("pending-story-operation-dropped-when-hiding-enabled", drained.entries.isEmpty && network.requests.isEmpty)
        worker.dispose()
        // Real sender code, including secret typing and the group-call exception.
        for id in [peer,secretId] {
            network.clear()
            await complete(requestActivity(postbox:a,network:network,accountPeerId:channelId,peerId:id,threadId:nil,activity:.typingText))
            try check("hidden-typing-never-requests-\(id.namespace)", network.requests.isEmpty)
        }
        for activity in [PeerInputActivity.recordingVoice,.uploadingFile(progress:50),.uploadingPhoto(progress:50),.uploadingVideo(progress:50),.recordingInstantVideo,.choosingSticker] {
            try check("hidden-activity-\(activity.key)", !wygramGhostInputActivityAllowed(activity,settings:all))
        }
        try check("call-liveness-is-not-suppressed", wygramGhostInputActivityAllowed(.speakingInGroupCall(timestamp:0),settings:all))
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideInputActivity=false })
        network.clear()
        await complete(requestActivity(postbox:a,network:network,accountPeerId:channelId,peerId:peer,threadId:7,activity:.typingText))
        try check("normal-typing-keeps-thread-capable-rpc",network.requests==["messages.setTyping"])
        network.clear()
        await complete(requestActivity(postbox:a,network:network,accountPeerId:channelId,peerId:secretId,threadId:nil,activity:.typingText))
        try check("normal-secret-typing-keeps-encrypted-rpc",network.requests==["messages.setEncryptedTyping"])
        network.clear()
        let space=PeerActivitySpace(peerId:peer,category:.global)
        let activities=Promise<[PeerActivitySpace:[(PeerId,PeerInputActivityRecord)]]>()
        activities.set(.single([space:[(channelId,PeerInputActivityRecord(activity:.typingText,updateId:1))]]))
        let typing=managedLocalTypingActivities(activities:activities.get(),postbox:a,network:network,accountPeerId:channelId).start()
        await pause()
        try check("managed-typing-initially-reports-when-allowed",network.requests==["messages.setTyping"])
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideInputActivity=true });await pause()
        network.clear()
        activities.set(.single([space:[(channelId,PeerInputActivityRecord(activity:.recordingVoice,updateId:2))]]))
        await pause()
        try check("enabling-typing-hide-stops-current-and-future-activities",network.requests.isEmpty)
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideInputActivity=false });await pause()
        try check("disabling-typing-hide-resumes-current-activity",network.requests==["messages.setTyping"])
        typing.dispose()
        // Production read-sync dispatcher must complete without a network operation,
        // retain local read position and remove pending synchronization (no retry loop).
        await complete(a.transaction { t in
            for id in [peer,channelId] {
                t.resetIncomingReadStates([id:[Namespaces.Message.Cloud:.idBased(maxIncomingReadId:10,maxOutgoingReadId:0,maxKnownId:10,count:0,markedUnread:false)]])
                t.setNeedsIncomingReadStateSynchronization(id)
            }
            let incoming=MessageIndex(id:MessageId(peerId:secretId,namespace:Namespaces.Message.SecretIncoming,id:1),timestamp:100)
            let outgoing=MessageIndex(id:MessageId(peerId:secretId,namespace:Namespaces.Message.Local,id:0),timestamp:0)
            t.resetIncomingReadStates([secretId:[Namespaces.Message.SecretIncoming:.indexBased(maxIncomingReadIndex:incoming,maxOutgoingReadIndex:outgoing,count:0,markedUnread:false)]])
            t.setNeedsIncomingReadStateSynchronization(secretId)
        })
        for id in [peer,channelId,secretId] {
            network.clear()
            await complete(synchronizePeerReadState(network:network,postbox:a,stateManager:state,peerId:id,push:true,validate:true))
            try check("hidden-read-push-and-validation-do-not-report-\(id.namespace)",network.requests.isEmpty && network.validationCalls==0)
        }
        let sync = await value(a.synchronizePeerReadStatesView())
        let local = await value(a.transaction { $0.getCombinedPeerReadState(peer) })
        try check("suppressed-read-operations-do-not-stay-in-retry-queue",sync.operations.isEmpty)
        try check("suppressing-receipt-keeps-local-chat-read",local?.count==0 && local?.states.contains(where:{ _,state in
            if case let .idBased(maxRead,_,_,_,_)=state { return maxRead==10 }; return false
        })==true)
        for id in [peer,channelId] {
            network.clear()
            await complete(a.transaction { t -> Signal<Void,NoError> in
                synchronizeConsumeMessageContents(transaction:t,network:network,stateManager:state,peerId:id,operation:SynchronizeConsumeMessageContentsOperation(messageIds:[MessageId(peerId:id,namespace:0,id:10)]))
            } |> switchToLatest)
            try check("hidden-media-consumption-never-reports-\(id.namespace)",network.requests.isEmpty)
        }
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideReadReceipts=false })
        network.clear()
        await complete(synchronizePeerReadState(network:network,postbox:a,stateManager:state,peerId:peer,push:true,validate:false))
        try check("normal-chat-read-retains-original-server-rpc",network.requests==["messages.readHistory"])
        for id in [peer,channelId] {
            network.clear()
            await complete(a.transaction { t -> Signal<Void,NoError> in
                synchronizeConsumeMessageContents(transaction:t,network:network,stateManager:state,peerId:id,operation:SynchronizeConsumeMessageContentsOperation(messageIds:[MessageId(peerId:id,namespace:0,id:10)]))
            } |> switchToLatest)
            try check("normal-media-consumption-reports-\(id.namespace)",network.requests==[id==peer ? "messages.readMessageContents" : "channels.readMessageContents"])
        }
        network.clear()
        await complete(synchronizePeerReadState(network:network,postbox:a,stateManager:state,peerId:channelId,push:true,validate:false))
        try check("normal-channel-read-keeps-original-server-rpc",network.requests==["channels.readHistory"])
        network.clear()
        await complete(synchronizePeerReadState(network:network,postbox:a,stateManager:state,peerId:secretId,push:true,validate:false))
        try check("normal-secret-read-keeps-encrypted-history-rpc",network.requests==["messages.readEncryptedHistory"])
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideStoryViews=true;$0.hideOnline=true;$0.hideInputActivity=true;$0.hideReadReceipts=true })
        try await showSettings(a)
    }
    func showSettings(_ a:Postbox) async throws {
        // Actual settings class and shared table base; no account wrapper is needed.
        let theme=CommandLine.arguments.contains("--dark") ? defaultDarkColorPresentationTheme : defaultPresentationTheme
        let controller=WyGramGhostModeController(postbox:a,theme:theme,chinese:true)
        controller.edgesForExtendedLayout=[]
        controller.title="幽灵模式"
        let navigation=UINavigationController(rootViewController:controller)
        navigation.overrideUserInterfaceStyle=theme.overallDarkAppearance ? .dark : .light
        let appearance=UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor=theme.list.blocksBackgroundColor
        appearance.titleTextAttributes=[.foregroundColor:theme.list.itemPrimaryTextColor]
        navigation.navigationBar.standardAppearance=appearance
        navigation.navigationBar.scrollEdgeAppearance=appearance
        window?.backgroundColor=theme.list.blocksBackgroundColor
        window?.overrideUserInterfaceStyle=navigation.overrideUserInterfaceStyle
        if CommandLine.arguments.contains("--large") { navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory:.accessibilityExtraExtraExtraLarge),forChild:controller) }
        window?.rootViewController=navigation
        await pause()
        try check("settings-page-exposes-exactly-four-switches",controller.tableView(controller.tableView,numberOfRowsInSection:0)==4)
        for i in 0..<4 {
            let cell=controller.tableView(controller.tableView,cellForRowAt:IndexPath(row:i,section:0))
            let control=cell.accessoryView as! UISwitch
            try check("saved-switch-\(i)-enabled-and-visible",control.isEnabled && control.isOn && !(cell.textLabel?.text?.isEmpty ?? true))
            controller.tableView.scrollToRow(at:IndexPath(row:i,section:0),at:.middle,animated:false)
            controller.tableView.layoutIfNeeded()
            if let visible=controller.tableView.cellForRow(at:IndexPath(row:i,section:0)),let label=visible.textLabel,let accessory=visible.accessoryView {
                let textFrame=label.convert(label.bounds,to:visible)
                let switchFrame=accessory.convert(accessory.bounds,to:visible)
                try check("label-and-switch-do-not-overlap-\(i)",!textFrame.intersects(switchFrame) && visible.bounds.height>=switchFrame.height)
            }
        }
        let toggle=controller.tableView(controller.tableView,cellForRowAt:IndexPath(row:3,section:0)).accessoryView as! UISwitch
        toggle.isOn=false;toggle.sendActions(for:.valueChanged);await pause()
        let changed=await value(FixturewygramGhostModeSettings(postbox:a))
        try check("settings-action-persists-only-requested-switch",changed.hideStoryViews && changed.hideOnline && changed.hideInputActivity && !changed.hideReadReceipts)
        await complete(FixturewygramUpdateGhostModeSettings(postbox:a) { $0.hideReadReceipts=true });await pause()
        try check("page-explains-other-devices-and-cumulative-read-limit",controller.tableView(controller.tableView,titleForFooterInSection:1)?.contains("累计已读") ?? false)
        controller.tableView.layoutIfNeeded()
        controller.tableView.scrollToRow(at:IndexPath(row:0,section:0),at:.top,animated:false)
        await pause()
    }
    func report(_ passed:Bool,_ error:String?) {
        let json:[String:Any]=["passed":passed,"checks":checks,"error":error ?? NSNull(),"runID":ProcessInfo.processInfo.environment["WYGRAM_GHOST_RUN_ID"] ?? "none","scope":"Production persistence, presence, typing, stories and read-sync sender functions with real Postbox and recording transport; constructed accounts, no real Telegram login or physical device."]
        try? JSONSerialization.data(withJSONObject:json,options:[.prettyPrinted,.sortedKeys]).write(to:documents.appendingPathComponent("results.json"))
    }
}
