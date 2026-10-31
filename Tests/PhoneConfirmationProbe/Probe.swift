import UIKit
import AsyncDisplayKit
import Display
import TelegramPresentationData
import UserNotifications

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
@objc(PhoneConfirmationProbeSceneDelegate)
final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var field: UITextField!
    var node: ASDisplayNode!
    var keyboardFrame = CGRect.zero
    var observer: NSObjectProtocol?
    var reportAttempts = 0
    let legacy = CommandLine.arguments.contains("--legacy")
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let root = UIViewController(); root.view.backgroundColor = .systemBackground
        window.rootViewController = root; self.window = window; window.makeKeyAndVisible()
        let heading = UILabel(frame: CGRect(x: 30,y: 150,width: 330,height: 50)); heading.text = "Your Phone"; heading.font = .boldSystemFont(ofSize: 28); root.view.addSubview(heading)
        self.field = UITextField(frame: CGRect(x: 30,y: 240,width: 300,height: 55)); self.field.keyboardType = .numberPad; self.field.text = "5550100"; root.view.addSubview(self.field)
        let strings = PresentationStrings(primaryComponent: PresentationStrings.Component(languageCode: "en", localizedName: "English", pluralizationRulesCode: nil, dict: [:]), secondaryComponent: nil, groupingSeparator: "")
        self.node = self.legacy ? LegacyPhoneConfirmationNode(theme: defaultPresentationTheme, strings: strings, code: "+1", number: "555 0100") : FixedPhoneConfirmationNode(theme: defaultPresentationTheme, strings: strings, code: "+1", number: "555 0100")
        self.node.frame = root.view.bounds; root.view.addSubview(self.node.view)
        self.observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let window = self.window, let frame = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            self.keyboardFrame = window.convert(frame, from: window.screen.coordinateSpace)
            self.layout(size: window.bounds.size, input: max(0,window.bounds.maxY-self.keyboardFrame.minY), regular: false)
        }
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        self.field.resignFirstResponder()
        DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { self.field.becomeFirstResponder() }
        DispatchQueue.main.asyncAfter(deadline: .now()+3) { self.report() }
    }
    func layout(size: CGSize, input: CGFloat, regular: Bool) {
        let l = ContainerViewLayout(size: size, metrics: LayoutMetrics(widthClass: regular ? .regular : .compact, heightClass: .regular, orientation: .portrait), deviceMetrics: .iPhone14Pro, intrinsicInsets: UIEdgeInsets(top: 0,left: 0,bottom: 34,right: 0), safeInsets: UIEdgeInsets(top: 59,left: 0,bottom: 34,right: 0), additionalInsets: .zero, statusBarHeight: 59, inputHeight: input, inputHeightIsInteractivellyChanging: false, inVoiceOver: false)
        if let n = self.node as? LegacyPhoneConfirmationNode { n.containerLayoutUpdated(l, transition: .immediate) }
        if let n = self.node as? FixedPhoneConfirmationNode { n.containerLayoutUpdated(l, transition: .immediate) }
    }
    func buttonFrame() -> CGRect { self.node.subnodes!.first { $0.accessibilityIdentifier == "Auth.PhoneConfirm.ContinueButton" }!.frame }
    func report() {
        self.reportAttempts += 1
        if self.keyboardFrame.isEmpty && self.reportAttempts < 30 {
            DispatchQueue.main.asyncAfter(deadline: .now()+0.5) { self.report() }; return
        }
        let size = self.window!.bounds.size
        let height = max(0,size.height-self.keyboardFrame.minY)
        var checks: [[String: Any]] = []
        for (w,h,k,r) in [(393.0,852.0,346.0,false),(440,956,362,false),(375,667,291,false),(393,852,420,false),(440,956,0,false),(1024,1366,420,true)] {
            self.layout(size: CGSize(width:w,height:h), input:k, regular:r)
            let b=self.buttonFrame(); checks.append(["size":"\(w)x\(h)","keyboard_height":k,"button_bottom":b.maxY,"clear":b.maxY <= h-k && b.minY >= 59])
        }
        self.layout(size:size,input:height,regular:false)
        let button = self.buttonFrame()
        let nativeKeyboardShown = !self.keyboardFrame.isEmpty && height > 100 && self.field.isFirstResponder
        let overlap = button.maxY > self.keyboardFrame.minY
        var notificationChecks: [String: Bool] = [:]
        notificationChecks["Current account uses its in-app banner"] = wygramForegroundNotificationOptions(isCurrentAccount:true,hasURL:false).isEmpty
        notificationChecks["Other or unresolved account receives a system banner"] = wygramForegroundNotificationOptions(isCurrentAccount:false,hasURL:false).contains(.banner)
        notificationChecks["URL notification receives a system banner"] = wygramForegroundNotificationOptions(isCurrentAccount:true,hasURL:true).contains(.banner)
        let encrypted = UNMutableNotificationContent(); encrypted.userInfo=["aps":["alert":["title":"","body":""],"mutable-content":1],"p":"encrypted-test-payload"]
        let generic=wygramNotificationWithoutSharedStorage(encrypted)
        notificationChecks["Undecodable alert remains visible with a generic title and body"] = generic.title == "WyGram" && !generic.body.isEmpty
        notificationChecks["Encrypted payload is preserved without exposing message content"] = generic.userInfo["p"] as? String == "encrypted-test-payload" && !generic.body.contains("encrypted-test-payload")
        let silent = UNMutableNotificationContent(); silent.userInfo=["aps":["content-available":1]]
        let silentResult=wygramNotificationWithoutSharedStorage(silent)
        notificationChecks["Silent pushes remain silent"] = silentResult.title.isEmpty && silentResult.body.isEmpty && silentResult.sound == nil
        let visible=UNMutableNotificationContent(); visible.title="Original"; visible.body="Existing preview"
        notificationChecks["Existing previews are preserved"] = wygramNotificationWithoutSharedStorage(visible).body == "Existing preview"
        let passed = nativeKeyboardShown && (self.legacy ? overlap : !overlap && checks.allSatisfy { $0["clear"] as? Bool == true }) && notificationChecks.values.allSatisfy { $0 }
        let report: [String: Any] = ["passed":passed,"legacy":self.legacy,"native_keyboard_shown":nativeKeyboardShown,"keyboard_frame":NSCoder.string(for: self.keyboardFrame),"button_frame":NSCoder.string(for: button),"overlap":overlap,"layouts":checks,"notification_checks":notificationChecks]
        let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("results.json")
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:url)
    }
}
