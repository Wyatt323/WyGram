import UIKit
import ReplayKit
import Display
import NavigationBarImpl
import MetalEngine
import SGSimpleSettings

// A separate simulator-only component probe. It never links into WyGram.
private func argument(_ name: String, fallback: String) -> String {
    return CommandLine.arguments.first(where: { $0.hasPrefix(name + "=") }).map { String($0.dropFirst(name.count + 1)) } ?? fallback
}

private func record(_ value: [String: Any]) {
    let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("probe.json")
    try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: path)
}

@main
final class ProbeDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }
}

@objc(TopBlurProbeSceneDelegate)
final class ProbeSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var indicatorWindow: UIWindow?
    var telegramWindow: Window1?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        if CommandLine.arguments.contains("--window-probe") {
            defaultNavigationBarImpl = { NavigationBarImpl(presentationData: $0) }
            let (window, host) = nativeWindowHostView()
            if CommandLine.arguments.contains("--attach-first") {
                window.windowScene = scene
                window.frame = scene.coordinateSpace.bounds
            }
            self.window = window
            SGSimpleSettings.shared.customAppBadge = "SkyAppBadge"
            let futurePhone = DeviceMetrics.unknown(screenSize: CGSize(width: 450, height: 980), statusBarHeight: 62, onScreenNavigationHeight: 34, screenCornerRadius: 55)
            precondition(futurePhone.showAppBadge)
            precondition(!DeviceMetrics.iPhone6.showAppBadge && !DeviceMetrics.iPadPro.showAppBadge)
            let telegramWindow = Window1(hostView: host, statusBarHost: ProbeStatusBarHost(window: window))
            self.telegramWindow = telegramWindow
            if !CommandLine.arguments.contains("--no-metal") {
                host.containerView.layer.addSublayer(MetalEngine.shared.rootLayer)
            }
            let mode = argument("--mode", fallback: "glass")
            let theme = NavigationBarTheme(overallDarkAppearance: false, buttonColor: .black, disabledButtonColor: .gray, primaryTextColor: .black, backgroundColor: UIColor.systemGroupedBackground.withAlphaComponent(0.8), enableBackgroundBlur: true, separatorColor: .clear, badgeBackgroundColor: .systemBlue, badgeStrokeColor: .white, badgeTextColor: .white, edgeEffectColor: mode == "no-edge" ? .clear : .systemGroupedBackground, accentButtonColor: .systemBlue, accentDisabledButtonColor: .gray, accentForegroundColor: .white, style: .glass)
            let controller = ViewController(navigationBarPresentationData: NavigationBarPresentationData(theme: theme, strings: NavigationBarStrings(back: "返回", close: "关闭")))
            controller.title = "设备"
            controller.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "编辑", style: .plain, target: nil, action: nil)
            controller.navigationBar?.previousItem = .item(UINavigationItem(title: "设置"))
            controller.displayNode.backgroundColor = .systemGroupedBackground
            var scrollToTopCount = 0
            controller.scrollToTop = { scrollToTopCount += 1 }
            let navigationController = NavigationController(mode: .automaticMasterDetail, theme: NavigationControllerTheme(statusBar: .black, navigationBar: theme, emptyAreaColor: .systemGroupedBackground))
            let root = ViewController(navigationBarPresentationData: NavigationBarPresentationData(theme: theme, strings: NavigationBarStrings(back: "返回", close: "关闭")))
            root.title = "设置"
            navigationController.setViewControllers([root, controller], animated: false)
            telegramWindow.viewController = CommandLine.arguments.contains("--plain-controller") ? controller : navigationController
            telegramWindow.setForceBadgeHidden(false)
            if mode == "badge-zposition" { telegramWindow.badgeView.layer.zPosition = 1000 }
            window.windowScene = scene
            window.frame = scene.coordinateSpace.bounds
            window.makeKeyAndVisible()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if CommandLine.arguments.contains("--disable-proxy-edge-effects"), #available(iOS 26.0, *) {
                    func disable(_ view: UIView) {
                        if let scroll = view as? UIScrollView, String(describing: type(of: scroll)).contains("ScrollToTopView") {
                            scroll.topEdgeEffect.isHidden = true
                            scroll.bottomEdgeEffect.isHidden = true
                            scroll.leftEdgeEffect.isHidden = true
                            scroll.rightEdgeEffect.isHidden = true
                        }
                        for child in view.subviews { disable(child) }
                    }
                    disable(window)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                var proxies: [[String: Any]] = []
                func inspect(_ view: UIView) {
                    if let scroll = view as? UIScrollView, String(describing: type(of: scroll)).contains("ScrollToTopView"), !scroll.isHidden {
                        var proxy: [String: Any] = ["frame": String(describing: scroll.frame), "scrollsToTop": scroll.scrollsToTop]
                        if #available(iOS 26.0, *) {
                            proxy["edgeEffectsHidden"] = [scroll.topEdgeEffect.isHidden, scroll.bottomEdgeEffect.isHidden, scroll.leftEdgeEffect.isHidden, scroll.rightEdgeEffect.isHidden]
                        }
                        _ = scroll.delegate?.scrollViewShouldScrollToTop?(scroll)
                        proxies.append(proxy)
                    }
                    for child in view.subviews { inspect(child) }
                }
                inspect(window)
                record([
                    "scope": "Exact production Window1, nativeWindowHostView, ViewController, NavigationBarImpl and original AppBadge image in an independent test app.",
                    "mode": mode,
                    "badgeHidden": telegramWindow.badgeView.isHidden,
                    "badgeFrame": String(describing: telegramWindow.badgeView.frame),
                    "badgeImageLoaded": telegramWindow.badgeView.image != nil,
                    "badgeImageMatchesDefault": telegramWindow.badgeView.image?.pngData() == UIImage(bundleImageName: "Components/AppBadge")?.pngData(),
                    "badgeImageSize": String(describing: telegramWindow.badgeView.image?.size ?? .zero),
                    "futurePhoneSupported": futurePhone.showAppBadge,
                    "legacyPhoneAndTabletHidden": !DeviceMetrics.iPhone6.showAppBadge && !DeviceMetrics.iPadPro.showAppBadge,
                    "containerSubviews": host.containerView.subviews.map { String(describing: type(of: $0)) },
                    "badgeSubviewIndex": host.containerView.subviews.firstIndex(of: telegramWindow.badgeView) ?? -1,
                    "badgeZPosition": telegramWindow.badgeView.layer.zPosition,
                    "arguments": CommandLine.arguments,
                    "scrollToTopProxies": proxies,
                    "scrollToTopCount": scrollToTopCount,
                ])
            }
            return
        }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = ProbeController()
        self.window = window
        window.makeKeyAndVisible()
        if argument("--marker", fallback: "content") == "overlay" {
            let indicator = UIWindow(windowScene: scene)
            indicator.windowLevel = .statusBar + 1
            indicator.backgroundColor = .clear
            let controller = UIViewController()
            controller.view.backgroundColor = .clear
            let marker = makeMarker()
            marker.frame = CGRect(x: scene.coordinateSpace.bounds.midX - 54, y: 20, width: 108, height: 28)
            controller.view.addSubview(marker)
            indicator.rootViewController = controller
            indicator.isHidden = false
            self.indicatorWindow = indicator
        }
    }
}

private final class ProbeStatusBarHost: StatusBarHost {
    weak var window: UIWindow?
    init(window: UIWindow) { self.window = window }
    var isApplicationInForeground: Bool { return true }
    var statusBarFrame: CGRect { return window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero }
    var keyboardWindow: UIWindow? { return nil }
    var keyboardView: UIView? { return nil }
}

private func makeMarker() -> UILabel {
    let marker = UILabel()
    marker.text = "● 测试提示"
    marker.textAlignment = .center
    marker.font = .boldSystemFont(ofSize: 14)
    marker.textColor = .white
    marker.backgroundColor = .systemRed
    marker.layer.cornerRadius = 14
    marker.clipsToBounds = true
    return marker
}

final class ProbeController: UIViewController {
    private var navigation: NavigationBarImpl!
    private let marker = makeMarker()
    private let details = UILabel()
    private var attemptedRecording = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard CommandLine.arguments.contains("--recording"), !attemptedRecording else { return }
        attemptedRecording = true
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        recorder.startRecording { error in
            let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("recording.json")
            let report: [String: Any] = ["isRecording": recorder.isRecording, "error": error.map { String(describing: $0) } ?? "none"]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]).write(to: path)
            if error == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    recorder.stopRecording { _, _ in recorder.discardRecording {} }
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        if argument("--marker", fallback: "content") == "content" {
            view.addSubview(marker)
        }
        let mode = argument("--mode", fallback: "glass")
        let theme = NavigationBarTheme(
            overallDarkAppearance: false, buttonColor: .black, disabledButtonColor: .gray,
            primaryTextColor: .black, backgroundColor: UIColor.systemGroupedBackground.withAlphaComponent(0.8),
            enableBackgroundBlur: true, separatorColor: .clear, badgeBackgroundColor: .systemBlue,
            badgeStrokeColor: .white, badgeTextColor: .white,
            edgeEffectColor: mode == "no-edge" ? .clear : .systemGroupedBackground,
            accentButtonColor: .systemBlue, accentDisabledButtonColor: .gray, accentForegroundColor: .white,
            style: mode == "legacy" ? .legacy : .glass
        )
        navigation = NavigationBarImpl(presentationData: NavigationBarPresentationData(theme: theme, strings: NavigationBarStrings(back: "返回", close: "关闭")))
        let item = UINavigationItem(title: "设备")
        item.rightBarButtonItem = UIBarButtonItem(title: "编辑", style: .plain, target: nil, action: nil)
        navigation.item = item
        navigation.previousItem = .item(UINavigationItem(title: "设置"))
        view.addSubview(navigation.view)

        details.numberOfLines = 0
        details.textAlignment = .center
        details.font = .systemFont(ofSize: 16)
        details.textColor = .secondaryLabel
        details.text = "原版导航组件对照测试\n\n模式：\(mode)\n标记层：\(argument("--marker", fallback: "content"))\n\n红色标记为测试内容\n不是系统录屏提示"
        view.addSubview(details)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let top = view.safeAreaInsets.top
        let height = top + 56.0
        navigation.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: height)
        navigation.updateLayout(size: navigation.frame.size, defaultHeight: 56, additionalTopHeight: top, additionalContentHeight: 0, additionalBackgroundHeight: 0, additionalCutout: nil, leftInset: 0, rightInset: 0, appearsHidden: false, isLandscape: false, transition: .immediate)
        if argument("--mode", fallback: "glass") == "clip-status-area", let edge = navigation.edgeEffectView {
            // Probe-only comparison: retain the navigation effect below the status area.
            let mask = CAShapeLayer()
            mask.path = UIBezierPath(rect: CGRect(x: 0, y: top - edge.frame.minY, width: edge.bounds.width, height: max(0, edge.bounds.maxY - top + edge.frame.minY))).cgPath
            edge.layer.mask = mask
        }
        marker.frame = CGRect(x: view.bounds.midX - 54, y: 20, width: 108, height: 28)
        details.frame = CGRect(x: 20, y: height + 100, width: view.bounds.width - 40, height: 240)
        record([
            "mode": argument("--mode", fallback: "glass"),
            "marker": argument("--marker", fallback: "content"),
            "safeAreaTop": top,
            "screen": String(describing: view.bounds),
            "replayKitAvailable": RPScreenRecorder.shared().isAvailable,
            "windowLevel": view.window?.windowLevel.rawValue ?? -1,
            "navigationSubviews": navigation.view.subviews.map { String(describing: type(of: $0)) },
            "scope": "Production NavigationBarImpl in a separate simulator component probe; marker is synthetic, not a system recording indicator."
        ])
    }
}
