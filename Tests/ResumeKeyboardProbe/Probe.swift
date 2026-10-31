import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import ChatInputTextNode

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}

private final class Host: StatusBarHost {
    weak var window: UIWindow?
    init(_ window: UIWindow) { self.window = window }
    var statusBarFrame: CGRect { self.window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero }
    // Deliberately unavailable: modern frame handling must not depend on private
    // cross-process keyboard windows or a stale keyboard view.
    var keyboardWindow: UIWindow? { nil }
    var keyboardView: UIView? { nil }
    var isApplicationInForeground: Bool { UIApplication.shared.applicationState == .active }
}

private final class Controller: ViewController {
    let input = ChatInputTextNode()
    var field: ChatInputTextView { self.input.textView }
    let panel = UIView()
    let titleLabel = UILabel()
    var currentLayout: ContainerViewLayout?

    init() {
        super.init(navigationBarPresentationData: nil)
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .systemGroupedBackground
        self.titleLabel.text = "WyGram 键盘与圆角验证"
        self.titleLabel.font = .boldSystemFont(ofSize: 22)
        self.displayNode.view.addSubview(self.titleLabel)
        for (index, image) in [PresentationResourcesSettings.swiftgram, PresentationResourcesSettings.swiftgramPro, PresentationResourcesSettings.wygramContextMenu].enumerated() {
            let view = UIImageView(image: image)
            view.frame = CGRect(x: 30 + index * 90, y: 185, width: 60, height: 60)
            self.displayNode.view.addSubview(view)
        }
        self.panel.backgroundColor = .secondarySystemGroupedBackground
        self.panel.layer.cornerRadius = 20
        self.field.font = .systemFont(ofSize: 17)
        self.field.layer.cornerRadius = 12
        self.field.text = "键盘切换后输入框保持可见"
        self.panel.addSubview(self.field)
        self.displayNode.view.addSubview(self.panel)
    }

    required init(coder: NSCoder) { fatalError() }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.currentLayout = layout
        let bottom = max(layout.inputHeight ?? 0, layout.intrinsicInsets.bottom)
        self.titleLabel.frame = CGRect(x: 25, y: (layout.statusBarHeight ?? 59) + 30, width: layout.size.width - 50, height: 45)
        transition.updateFrame(view: self.panel, frame: CGRect(x: 10, y: layout.size.height - bottom - 58, width: layout.size.width - 20, height: 54))
        self.input.frame = CGRect(x: 10, y: 7, width: layout.size.width - 40, height: 40)
        self.input.updateLayout(size: self.input.frame.size)
    }
}

@objc(ResumeKeyboardProbeScene)
final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var content: Window1?
    private var controller: Controller?
    private var observer: NSObjectProtocol?
    private var keyboardFrame = CGRect.zero
    private var checks: [[String: Any]] = []
    private var started = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let (window, host) = nativeWindowHostView()
        window.windowScene = scene
        window.frame = scene.coordinateSpace.bounds
        self.window = window
        let content = Window1(hostView: host, statusBarHost: Host(window))
        self.content = content
        let controller = Controller()
        self.controller = controller
        content.viewController = controller
        window.makeKeyAndVisible()
        self.observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let value = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
                  let window = self.window else { return }
            self.keyboardFrame = window.screen.coordinateSpace.convert(value.cgRectValue, to: window)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !self.started else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.sample("return-from-background", expectKeyboard: self.controller?.field.isFirstResponder == true); self.save() }
            return
        }
        self.started = true
        self.geometryChecks()
        self.iconChecks()
        self.step(0)
    }

    private func step(_ index: Int) {
        guard let field = self.controller?.field else { return }
        if index == 6 {
            field.keyboardType = .default
            field.reloadInputViews()
            field.becomeFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.sample("final-visible", expectKeyboard: true)
                self.gestureChecks()
            }
            return
        }
        field.keyboardType = index % 2 == 0 ? .default : .numberPad
        field.reloadInputViews()
        field.becomeFirstResponder()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.sample("keyboard-switch-\(index)", expectKeyboard: true)
            if index % 2 == 1 {
                field.resignFirstResponder()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.sample("keyboard-hide-\(index)", expectKeyboard: false)
                    self.step(index + 1)
                }
            } else { self.step(index + 1) }
        }
    }

    private func gestureChecks() {
        guard let window = self.window,
              let recognizer = self.controller?.view.superview?.gestureRecognizers?.compactMap({ $0 as? WindowPanRecognizer }).first else {
            self.checks.append(["name": "gesture-recognizer-present", "passed": false])
            self.save()
            return
        }
        let top = self.keyboardFrame.minY
        let start = CGPoint(x: window.bounds.midX, y: top - 80)
        let partial = CGPoint(x: start.x, y: top + 60)
        recognizer.began?(start)
        recognizer.moved?(partial)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sample("drag-keeps-composer-above-system-keyboard", expectKeyboard: true)
            recognizer.ended?(partial, nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.sample("cancel-drag-restores-composer", expectKeyboard: true)
                recognizer.began?(start)
                recognizer.moved?(partial)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    recognizer.ended?(CGPoint(x: start.x, y: window.bounds.maxY - 5), CGPoint(x: 0, y: 500))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.sample("swipe-dismiss-finishes", expectKeyboard: false)
                        self.controller?.field.becomeFirstResponder()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.sample("reopen-after-swipe", expectKeyboard: true)
                            self.save()
                        }
                    }
                }
            }
        }
    }

    private func sample(_ name: String, expectKeyboard: Bool) {
        guard let window = self.window, let controller = self.controller, let layout = controller.currentLayout else { return }
        let height = layout.inputHeight ?? 0
        let panel = controller.panel.convert(controller.panel.bounds, to: window)
        let actualHeight = dockedKeyboardHeight(frame: self.keyboardFrame, in: window.bounds, safeBottom: window.safeAreaInsets.bottom)
        let clear = expectKeyboard ? height > 100 && actualHeight > 100 && panel.maxY <= self.keyboardFrame.minY + 1 : height < 1 && !controller.field.isFirstResponder && actualHeight < 1
        self.checks.append(["name": name, "passed": clear, "inputHeight": height, "keyboardFrame": NSCoder.string(for: self.keyboardFrame), "panelFrame": NSCoder.string(for: panel), "firstResponder": controller.field.isFirstResponder, "inputLanguage": controller.field.textInputMode?.primaryLanguage ?? ""])
    }

    private func geometryChecks() {
        let bounds = CGRect(x: 0, y: 0, width: 440, height: 956)
        for (name, frame, expected) in [
            ("glass-bottom-gap", CGRect(x: 0, y: 590, width: 440, height: 354), CGFloat(366)),
            ("candidate-bar-expanded", CGRect(x: 0, y: 470, width: 440, height: 474), CGFloat(486)),
            ("hidden", CGRect(x: 0, y: 956, width: 440, height: 360), CGFloat(0)),
            ("floating-tablet-keyboard", CGRect(x: 100, y: 500, width: 240, height: 250), CGFloat(0)),
            ("empty-frame", CGRect.zero, CGFloat(0))
        ] {
            let actual = dockedKeyboardHeight(frame: frame, in: bounds, safeBottom: 34)
            self.checks.append(["name": name, "passed": actual == expected, "expected": expected, "actual": actual])
        }
    }

    private func iconChecks() {
        for (name, image) in [("settings-logo", PresentationResourcesSettings.swiftgram), ("features-logo", PresentationResourcesSettings.swiftgramPro), ("context-menu-logo", PresentationResourcesSettings.wygramContextMenu)] {
            guard let cgImage = image?.cgImage else { self.checks.append(["name": name, "passed": false]); continue }
            var bytes = [UInt8](repeating: 0, count: 30 * 30 * 4)
            let passed = bytes.withUnsafeMutableBytes { pointer -> Bool in
                guard let context = CGContext(data: pointer.baseAddress, width: 30, height: 30, bitsPerComponent: 8, bytesPerRow: 120, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 30, height: 30))
                let p = pointer.bindMemory(to: UInt8.self)
                return p[3] == 0 && p[(29 * 30 + 29) * 4 + 3] == 0 && p[(15 * 30 + 15) * 4 + 3] == 255
            }
            self.checks.append(["name": name, "passed": passed])
        }
    }

    private func save() {
        let passed = !self.checks.isEmpty && self.checks.allSatisfy { $0["passed"] as? Bool == true }
        let report: [String: Any] = ["passed": passed, "checks": self.checks, "scope": "Production Window1 and nativeWindowHostView with a real system keyboard, production settings icon rendering, and the production ChatInputTextNode rich-text editor in a lightweight panel. Exercises WindowPanRecognizer callbacks with unavailable private keyboard surfaces. No Telegram account or full ChatController."]
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("results.json")
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path)
    }
}
