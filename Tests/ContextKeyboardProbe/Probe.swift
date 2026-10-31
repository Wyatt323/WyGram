import UIKit
import AsyncDisplayKit
import Display
import ContextUI
import ContextControllerImpl
import ChatInputTextNode
import SwiftSignalKit
import TelegramPresentationData

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}

private final class Host: StatusBarHost {
    weak var window: UIWindow?
    init(_ window: UIWindow) { self.window = window }
    var statusBarFrame: CGRect { self.window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero }
    // Exercise the modern fallback: no legacy keyboard window/view to overlay.
    var keyboardWindow: UIWindow? { nil }
    var keyboardView: UIView? { nil }
    var isApplicationInForeground: Bool { true }
}

private final class ChatFixture: ViewController {
    let input = ChatInputTextNode()
    let message = ContextExtractedContentContainingNode()
    let avatar = ASDisplayNode()
    var applied: ContainerViewLayout?
    let draft = "这是还未发送的草稿，长按后应保留"
    init() {
        super.init(navigationBarPresentationData: nil)
        displayNode = ASDisplayNode()
        displayNode.backgroundColor = .systemGroupedBackground
        message.contentNode.backgroundColor = .systemGreen
        message.contentNode.cornerRadius = 14
        let text = UILabel()
        text.text = "就这两天特别多"
        text.font = .systemFont(ofSize: 17)
        text.frame = CGRect(x: 12, y: 7, width: 200, height: 30)
        message.contentNode.view.addSubview(text)
        displayNode.addSubnode(message)
        avatar.backgroundColor = .systemBlue
        avatar.cornerRadius = 24
        displayNode.addSubnode(avatar)
        input.textView.text = draft
        input.textView.font = .systemFont(ofSize: 17)
        input.textView.backgroundColor = .white
        input.textView.layer.cornerRadius = 16
        displayNode.view.addSubview(input.textView)
    }
    required init(coder: NSCoder) { fatalError() }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        applied = layout
        let bottom = max(layout.inputHeight ?? 0, layout.intrinsicInsets.bottom)
        transition.updateFrame(view: input.textView, frame: CGRect(x: 15, y: layout.size.height - bottom - 58, width: layout.size.width - 30, height: 50))
        message.frame = CGRect(x: layout.size.width - 236, y: min(360, layout.size.height - bottom - 120), width: 220, height: 44)
        message.contentNode.frame = CGRect(origin: .zero, size: message.frame.size)
        message.contentRect = CGRect(origin: .zero, size: message.frame.size)
        avatar.frame = CGRect(x: 16, y: message.frame.minY - 60, width: 48, height: 48)
    }
}

private final class MessageSource: ContextExtractedContentSource {
    let root: ChatFixture
    var takeCount = 0
    init(_ root: ChatFixture) { self.root = root }
    var keepInPlace: Bool { false }
    var ignoreContentTouches: Bool { false }
    var blurBackground: Bool { true }
    func takeView() -> ContextControllerTakeViewInfo? {
        takeCount += 1
        return .init(containingItem: .node(root.message), contentAreaInScreenSpace: root.view.window!.bounds)
    }
    func putBack() -> ContextControllerPutBackViewInfo? {
        .init(contentAreaInScreenSpace: root.view.window!.bounds)
    }
}

private final class ReferenceSource: ContextReferenceContentSource {
    let root: ChatFixture
    init(_ root: ChatFixture) { self.root = root }
    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        .init(referenceView: root.avatar.view, contentAreaInScreenSpace: root.view.window!.bounds)
    }
}

private final class AvatarSource: ContextControllerContentSource {
    let root: ChatFixture
    let controller: ViewController
    var navigationController: NavigationController? { nil }
    var passthroughTouches: Bool { false }
    init(_ root: ChatFixture) {
        self.root = root
        controller = ViewController(navigationBarPresentationData: nil)
        controller.displayNode = ASDisplayNode()
        controller.displayNode.backgroundColor = .systemBlue
        let label = UILabel()
        label.text = "头像预览"
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 30)
        label.frame = CGRect(x: 40, y: 80, width: 200, height: 50)
        controller.view.addSubview(label)
    }
    func transitionInfo() -> ContextControllerTakeControllerInfo? {
        .init(contentAreaInScreenSpace: root.view.window!.bounds, sourceNode: { [root] in (root.avatar.view, root.avatar.bounds) })
    }
    func animatedIn() {}
}

@objc(ContextKeyboardProbeScene) final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var display: Window1?
    private var root: ChatFixture?
    private var keyboardFrame = CGRect.zero
    private var observer: NSObjectProtocol?
    private var checks: [[String: Any]] = []
    private let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private func pause(_ seconds: Double = 0.5) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
    private func check(_ name: String, _ passed: Bool, _ data: [String: Any] = [:]) {
        var value = data; value["name"] = name; value["passed"] = passed; checks.append(value)
    }
    // Some production menu stacks attach ASDisplayNode views through UIKit
    // containers, so walking only ASDisplayNode.subnodes misses real actions.
    private func views(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(views) }
    private func snapshot(_ name: String) {
        guard let window else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try? image.pngData()?.write(to: documents.appendingPathComponent(name + ".png"))
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        let (window, host) = nativeWindowHostView()
        window.windowScene = scene as? UIWindowScene
        window.frame = (scene as! UIWindowScene).coordinateSpace.bounds
        let display = Window1(hostView: host, statusBarHost: Host(window))
        let root = ChatFixture()
        display.viewController = root
        self.root = root; self.display = display; self.window = window
        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            guard let value = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
            self?.keyboardFrame = window.screen.coordinateSpace.convert(value.cgRectValue, to: window)
        }
        window.makeKeyAndVisible()
        Task { @MainActor in await self.run() }
    }
    private func run() async {
        guard let root, let display, let window else { return }
        await pause(1)
        let baseline = CommandLine.arguments.contains("--baseline")
        let scenarios = baseline ? ["message"] : ["message", "avatar", "avatar-no-photo", "message-number-pad", "message-no-keyboard", "menu-owns-input"]
        for name in scenarios {
            let noKeyboard = name == "message-no-keyboard"
            root.input.textView.keyboardType = name == "message-number-pad" ? .numberPad : .default
            root.input.textView.text = root.draft
            if !noKeyboard { root.input.textView.becomeFirstResponder() }
            await pause(1)
            let keyboardWasVisible = keyboardFrame.intersects(window.bounds) && keyboardFrame.height > 100
            check(name + "/initial-keyboard", noKeyboard ? !keyboardWasVisible : keyboardWasVisible)
            let source: ContextContentSource
            let messageSource: MessageSource?
            if name == "avatar" { source = .controller(AvatarSource(root)); messageSource = nil }
            else if name == "avatar-no-photo" { source = .reference(ReferenceSource(root)); messageSource = nil }
            else { let s = MessageSource(root); source = .extracted(s); messageSource = s }
            var selected = false
            let items: [ContextMenuItem] = ["编辑于今天 22:22", "2 人已读", "查看消息旧版本", "回复", "拷贝", "编辑", "置顶", "删除"].map { text in
                .action(ContextMenuActionItem(text: text, icon: { _ in nil }, action: { _, completion in selected = true; completion(.default) }))
            }
            let controller = ContextControllerImpl(presentationData: defaultPresentationData(), configuration: .init(sources: [.init(id: 0, title: "", source: source, items: .single(.init(content: .list(items))))], initialId: 0))
            var dismissedInputCount = 0
            var extractedBeforeDismiss = false
            if !baseline && name != "menu-owns-input" {
                controller.dismissInputBeforePresentation = {
                    dismissedInputCount += 1
                    extractedBeforeDismiss = messageSource == nil || messageSource!.takeCount > 0
                    root.input.textView.resignFirstResponder()
                }
            }
            display.presentInGlobalOverlay(controller)
            await pause(1.5)
            let actions = views(controller.view).compactMap { $0.asyncdisplaykit_node as? ContextControllerActionsListActionItemNode }
            check(name + "/all-actions-rendered", actions.count == items.count, ["count": actions.count])
            let overlap = actions.contains { action in
                let rect = action.view.convert(action.view.bounds, to: window)
                return rect.intersects(keyboardFrame) && rect.intersects(window.bounds)
            }
            if baseline {
                check("baseline/overlap-reproduced", root.input.textView.isFirstResponder && overlap, ["keyboardY": keyboardFrame.minY])
            } else if name == "menu-owns-input" {
                check(name + "/keyboard-not-dismissed-without-opt-in", root.input.textView.isFirstResponder && dismissedInputCount == 0)
                root.input.textView.resignFirstResponder()
                await pause()
            } else {
                check(name + "/keyboard-dismissed", !root.input.textView.isFirstResponder && !keyboardFrame.intersects(window.bounds))
                check(name + "/no-keyboard-overlap", !overlap)
                check(name + "/callback-once-after-source-capture", dismissedInputCount == 1 && extractedBeforeDismiss)
                controller.viewWillAppear(false)
                check(name + "/callback-not-repeated", dismissedInputCount == 1 && controller.dismissInputBeforePresentation == nil)
            }
            check(name + "/draft-preserved", root.input.textView.text == root.draft)
            snapshot(name)
            await pause(1)
            if let last = actions.last {
                let rect = last.view.convert(last.view.bounds, to: window)
                if !baseline && name != "menu-owns-input" {
                    check(name + "/last-action-visible", rect.minY >= 0 && rect.maxY <= window.bounds.height, ["actionBottom": rect.maxY])
                }
                last.performAction()
            } else { controller.dismiss(completion: nil) }
            await pause(1)
            check(name + "/action-executes-and-menu-closes", selected && controller.view.superview == nil)
            root.input.textView.becomeFirstResponder()
            await pause(0.7)
            check(name + "/typing-resumes", root.input.textView.isFirstResponder && (root.applied?.inputHeight ?? 0) > 100)
            root.input.textView.resignFirstResponder()
            await pause()
        }
        let result: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "baseline": baseline, "checks": checks, "runID": ProcessInfo.processInfo.environment["WYGRAM_CONTEXT_PROBE_RUN_ID"] ?? ""]
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: documents.appendingPathComponent("results.json"))
    }
}
