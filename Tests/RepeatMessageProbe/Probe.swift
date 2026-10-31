import UIKit
import Postbox
import TelegramCore
import ContextUI
import TelegramPresentationData

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
@objc(RepeatMessageProbeScene)
final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let root = UIViewController(); root.view.backgroundColor = .systemBackground
        window.rootViewController = root; self.window = window; window.makeKeyAndVisible()
        let checks = self.exercise()
        let passed = checks.allSatisfy { $0["passed"] as? Bool == true }
        let label = UILabel(frame: window.bounds.insetBy(dx: 20, dy: 100));label.numberOfLines = 0
        label.text = "复读组件检查\n\(passed ? "通过" : "失败")\n\(checks.count) 项（构造消息，无网络发送）"
        root.view.addSubview(label)
        let report: [String: Any] = ["passed":passed,"checks":checks,"scope":"Actual production request builder and menu item with TelegramCore/Postbox models. Synthetic fixtures; no authenticated ChatController, network send or LCSign device validation."]
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("results.json")
        try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: destination)
    }
    func exercise() -> [[String: Any]] {
        var checks: [[String: Any]] = []
        func check(_ value: Bool, _ name: String) { checks.append(["name":name,"passed":value]) }
        func id(_ value: Int64, namespace: PeerId.Namespace = Namespaces.Peer.CloudUser) -> PeerId { .init(namespace: namespace, id: ._internalFromInt64Value(value)) }
        func user(_ value: Int64) -> TelegramUser {
            TelegramUser(id: id(value), accessHash: nil, firstName: "测试", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        }
        let peer = user(101)
        func message(_ number: Int32 = 1, peer: Peer = peer, flags: MessageFlags = [.Incoming], namespace: Int32 = Namespaces.Message.Cloud, attributes: [MessageAttribute] = [], media: [Media] = [], grouping: Int64? = nil) -> Message {
            var peers = SimpleDictionary<PeerId, Peer>(); peers[peer.id] = peer
            return Message(stableId: UInt32(number), stableVersion: 0, id: .init(peerId: peer.id, namespace: namespace, id: number), globallyUniqueId: nil, groupingKey: grouping, groupInfo: nil, threadId: nil, timestamp: 1793430000, flags: flags, tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: user(102), text: "复读文字 😀 **格式**", attributes: attributes, media: media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        }
        func request(_ message: Message, peer: Peer = peer, thread: Int64? = nil, send: Bool = true, forward: Bool = true, protected: Bool = false, bypass: Bool = false) -> EnqueueMessage? {
            wygramRepeatMessageRequest(message: message, peer: peer, threadId: thread, canSend: send, canForward: forward, copyProtected: protected, ignoreDefaultRestrictions: bypass)
        }
        func inspect(_ value: EnqueueMessage?, source: Message, thread: Int64? = nil) -> Bool {
            guard case let .forward(sourceId, targetThread, grouping, attributes, correlation)? = value,
                  sourceId == source.id, targetThread == thread, correlation == nil,
                  case .none = grouping,
                  let options = attributes.first as? ForwardOptionsMessageAttribute else { return false }
            return attributes.count == 1 && options.hideNames && !options.hideCaptions
        }
        let original = message(attributes: [TextEntitiesMessageAttribute(entities: [.init(range: 0..<2, type: .Bold)])])
        check(inspect(request(original), source: original), "Incoming text uses exactly its source ID, no attribution, no caption removal")
        let outgoing = message(2, flags: [])
        check(inspect(request(outgoing), source: outgoing), "Own outgoing message can be repeated")
        check(inspect(request(original, thread: 777), source: original, thread: 777), "Current topic/thread ID is retained")
        check(request(original, peer: user(103)) == nil, "A different destination chat is rejected")
        check(request(original, send: false) == nil, "Read-only chat is rejected")
        check(request(original, forward: false) == nil, "Non-forwardable message is rejected")
        check(request(original, protected: true) == nil, "Protected chat is rejected")
        check(request(message(flags: [.Incoming,.CopyProtected])) == nil, "Protected message is rejected")
        for flags: MessageFlags in [[.Unsent],[.Sending],[.Failed]] {
            check(request(message(flags: flags)) == nil, "Pending/failed message is rejected: \(flags.rawValue)")
        }
        check(request(message(namespace: Namespaces.Message.ScheduledCloud)) == nil, "Scheduled source is rejected")
        check(request(message(namespace: Namespaces.Message.SecretIncoming)) == nil, "Secret message is not sent through cloud forwarding")
        check(request(message(attributes: [WyGramMessageHistoryAttribute(deletedAt: 10, hasPreviousVersions: false)])) == nil, "Locally retained deleted source is rejected")
        let edited = message(attributes: [WyGramMessageHistoryAttribute(deletedAt: nil, hasPreviousVersions: true)])
        check(inspect(request(edited), source: edited), "Existing edit-history marker does not change the selected current message")
        check(request(message(attributes: [WyGramRetainedPhotoAttribute(archiveKey: Data([1]))])) == nil, "Expired locally retained photo is not forwarded from its stale server ID")
        let photo = TelegramMediaImage(imageId: .init(namespace: Namespaces.Media.CloudImage,id: 901), representations: [.init(dimensions: .init(width: 320,height: 240),resource: LocalFileMediaResource(fileId: 902),progressiveSizes: [],immediateThumbnailData: nil)],immediateThumbnailData: nil,reference: nil,partialReference: nil,flags: [])
        let image = message(3, media: [photo], grouping: 99)
        check(inspect(request(image), source: image), "Album photo repeats only pressed message; no automatic grouping or extra images")
        check(image.media.count == 1 && image.text == "复读文字 😀 **格式**", "Building a repeat request leaves the original media, caption and message untouched")
        check(request(message(attributes: [AutoclearTimeoutMessageAttribute(timeout: viewOnceTimeout,countdownBeginTime: nil)],media: [photo])) == nil, "View-once source is rejected")
        func group(_ rights: TelegramChatBannedRightsFlags, member: TelegramGroupMembership = .Member, admin: Bool = false) -> TelegramGroup {
            TelegramGroup(id: id(200,namespace: Namespaces.Peer.CloudGroup),title: "组",photo: [],participantCount: 3,role: admin ? .creator(rank: nil) : .member,membership: member,flags: [],defaultBannedRights: .init(flags: rights,untilDate: Int32.max),migrationReference: nil,creationDate: 0,version: 0)
        }
        let textBan = group([.banSendText]);let textInGroup=message(peer: textBan)
        check(request(textInGroup,peer: textBan) == nil, "Basic-group text permission is respected")
        let photoBan = group([.banSendPhotos]);let imageInGroup=message(peer: photoBan,media: [photo])
        check(request(imageInGroup,peer: photoBan) == nil, "Basic-group photo permission is respected")
        check(request(message(peer: photoBan),peer: photoBan) != nil, "Photo-only ban still permits text")
        let left = group([],member: .Left)
        check(request(message(peer: left),peer: left) == nil, "Left group is rejected")
        let admin = group([.banSendText],admin: true)
        check(request(message(peer: admin),peer: admin) != nil, "Existing group administrator permission is respected")
        for (language,title) in [("zh-hans","复读"),("zh-hant","復讀"),("en","Repeat Message")] {
            var sends=0;var dismissals=0
            let item = wygramRepeatMenuItem(languageCode: language,repeatMessage: { sends += 1 })
            guard case let .action(action) = item else { check(false,"Menu action exists");continue }
            check(action.text == title,"Localized repeat label: \(language)")
            check(action.icon(defaultPresentationData().theme) != nil,"Repeat icon resolves: \(language)")
            let invocation = ContextMenuActionItem.Action(controller: nil,dismissWithResult: { result in
                if case .dismissWithoutContent = result { dismissals += 1 }
            },updateAction: { _,_ in })
            action.action?(invocation);action.action?(invocation)
            check(sends == 1 && dismissals == 1,"One menu activation can send only once and dismisses first: \(language)")
        }
        return checks
    }
}
