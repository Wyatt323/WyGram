import UIKit
import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import TelegramPresentationData
import SGAppGroupIdentifier
import SGSettingsUI
import NavigationBarImpl
import LegacyUI

@main final class App: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { initializeAccountManagement(); return true }
}
@objc(SettingsLayoutProbeScene) final class Scene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var display: Window1?
    var disposables: [Disposable] = []
    var postbox: Postbox?
    var checks: [[String: Any]] = []
    var keyboardFrame: CGRect?
    var keyboardObserver: NSObjectProtocol?
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    func check(_ name: String, _ value: Bool, _ details: [String: Any] = [:]) { var d=details;d["name"]=name;d["passed"]=value;checks.append(d) }
    func value<T>(_ s: Signal<T, NoError>) async -> T { await withCheckedContinuation { continuation in self.disposables.append((s |> take(1)).start(next: { continuation.resume(returning:$0) })) } }
    func pause(_ seconds: Double = 0.3) async { try? await Task.sleep(nanoseconds: UInt64(seconds*1e9)) }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        let first = UIWindow(windowScene: scene as! UIWindowScene);first.rootViewController=UIViewController();first.makeKeyAndVisible();window=first
        Task { @MainActor in await self.run(scene as! UIWindowScene) }
    }
    func open() async -> Postbox {
        let encryption=ValueBoxEncryptionParameters(forceEncryptionIfNoSet:false,key:.init(data:Data(repeating:7,count:32))!,salt:.init(data:Data(repeating:9,count:16))!)
        return await value(openPostbox(basePath:documents.appendingPathComponent("fixture/postbox").path,seedConfiguration:telegramPostboxSeedConfiguration,encryptionParameters:encryption,timestampForAbsoluteTimeBasedOperations:Int32(Date().timeIntervalSince1970),isMainProcess:true,isTemporary:false,isReadOnly:false,useCopy:false,useCaches:true,removeDatabaseOnError:false) |> mapToSignal { result -> Signal<Postbox,NoError> in if case let .postbox(postbox)=result { return .single(postbox) };return .complete() })
    }
    func seed(_ postbox: Postbox) async {
        _ = await value(wygramRemoveMessageHistory(postbox:postbox))
        _ = await value(wygramUpdateMessageHistorySettings(postbox:postbox,settings:WyGramMessageHistorySettings()))
        let peer=PeerId(namespace:Namespaces.Peer.CloudChannel,id:PeerId.Id._internalFromInt64Value(2001))
        func message(_ id:Int32,_ text:String,_ date:Int32) -> StoreMessage { StoreMessage(id:MessageId(peerId:peer,namespace:Namespaces.Message.Cloud,id:id),customStableId:nil,globallyUniqueId:nil,groupingKey:nil,threadId:nil,timestamp:date,flags:[.Incoming],tags:[],globalTags:[],localTags:[],forwardInfo:nil,authorId:peer,text:text,attributes:[],media:[]) }
        _ = await value(postbox.transaction { transaction -> Void in
            let user=TelegramUser(id:peer,accessHash:nil,firstName:"SaturDay.Lite Channel · 这是一段很长的聊天名称",lastName:nil,username:nil,phone:nil,photo:[],botInfo:nil,restrictionInfo:nil,flags:[],emojiStatus:nil,usernames:[],storiesHidden:nil,nameColor:nil,backgroundEmojiId:nil,profileColor:nil,profileBackgroundEmojiId:nil,subscriberCount:nil,verificationIconFileId:nil)
            transaction.updatePeersInternal([user],update:{ _,p in p })
            for (i,text) in ["📊 SaturDay.Lite 动态统计 📊\n\n👤 用户：1431\n🎥 实时：7…\n\n"+String(repeating:"这是多行长消息，需要限制预览行数。\n",count:12),"欢迎 A*** ⭐ 加入群组！请完成入群验证。\n请点击“加入频道”按钮后完成验证。", "大佬你在哪里了，我去关注一下", "这是保留的原始版本内容"].enumerated() {
                let id=Int32(101+i), now=Int32(Date().timeIntervalSince1970)-Int32(i*120)
                _ = transaction.addMessages([message(id,text,now)],location:.Random)
                if i==2 { let ids=[MessageId(peerId:peer,namespace:Namespaces.Message.Cloud,id:id)]; _ = wygramPrepareRemoteMessageDeletion(transaction:transaction,mediaBox:postbox.mediaBox,ids:ids) }
                else { wygramArchivePreviousVersion(transaction:transaction,mediaBox:postbox.mediaBox,replacement:message(id,"修改后的消息",now+60)) }
            }
        })
    }
    func descendants(_ v:UIView) -> [UIView] { [v]+v.subviews.flatMap(descendants) }
    func snapshot(_ name:String) {
        guard let window else{return}
        let image=UIGraphicsImageRenderer(bounds:window.bounds).image { _ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true) }
        try? image.pngData()?.write(to:documents.appendingPathComponent(name+".png"))
    }
    func run(_ scene:UIWindowScene) async {
        TempBox.initializeShared(basePath:documents.appendingPathComponent("temp").path,processType:"tests",launchSpecificId:1)
        defaultNavigationBarImpl = { NavigationBarImpl(presentationData:$0) }
        let history=CommandLine.arguments.contains("--history")
        let dark=CommandLine.arguments.contains("--dark")
        let large=CommandLine.arguments.contains("--large")
        let theme=dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme
        let strings=PresentationStrings(primaryComponent:.init(languageCode:"zh-hans",localizedName:"简体中文",pluralizationRulesCode:nil,dict:[:]),secondaryComponent:nil,groupingSeparator:",")
        WyGramPushStatus.record("apple",value:"registered");WyGramPushStatus.record("server.17",value:"APP_PUSH_CERT_MISSING")
        let controller:ViewController
        if history { let p=await open();postbox=p;await seed(p);controller=wygramLocalMessageHistoryController(postbox:p,theme:theme,strings:strings) }
        else { controller=wygramPushStatusViewController(theme:theme,strings:strings,accountId:17,retry:{}) }
        let bar=NavigationBarTheme(overallDarkAppearance:dark,buttonColor:theme.rootController.navigationBar.accentTextColor,disabledButtonColor:.gray,primaryTextColor:theme.rootController.navigationBar.primaryTextColor,backgroundColor:theme.rootController.navigationBar.opaqueBackgroundColor,enableBackgroundBlur:true,separatorColor:.clear,badgeBackgroundColor:.systemBlue,badgeStrokeColor:.white,badgeTextColor:.white,accentButtonColor:.systemBlue,accentDisabledButtonColor:.gray,accentForegroundColor:.white)
        let navigation=NavigationController(mode:.single,theme:NavigationControllerTheme(statusBar:dark ? .white : .black,navigationBar:bar,emptyAreaColor:theme.list.blocksBackgroundColor))
        let root=ViewController(navigationBarPresentationData:NavigationBarPresentationData(theme:bar,strings:NavigationBarStrings(back:"返回",close:"关闭")));root.title="设置"
        navigation.setViewControllers([root],animated:false)
        let (window,host)=nativeWindowHostView();window.windowScene=scene;window.frame=scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle=dark ? .dark : .light
        let display=Window1(hostView:host,statusBarHost:ProbeStatusHost(window:window));display.viewController=navigation;self.display=display
        self.window?.isHidden=true;self.window=window;window.makeKeyAndVisible()
        await pause(0.5)
        navigation.pushViewController(controller)
        if large { navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory:.accessibilityExtraExtraExtraLarge),forChild:controller) }
        keyboardObserver=NotificationCenter.default.addObserver(forName:UIResponder.keyboardDidChangeFrameNotification,object:nil,queue:.main) { [weak self] n in self?.keyboardFrame=(n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue }
        await pause(3)
        guard let legacy=controller as? LegacyController,let table=legacy.legacyController as? UITableViewController else {return}
        table.tableView.layoutIfNeeded()
        let navBottom=controller.navigationLayout(layout:controller.currentlyAppliedLayout!).navigationFrame.maxY
        let tableFrame=table.view.convert(table.view.bounds,to:controller.view)
        check("table-starts-below-navigation",tableFrame.minY >= navBottom-0.5,["tableY":tableFrame.minY,"navBottom":navBottom])
        let row0=table.tableView.rectForRow(at:IndexPath(row:0,section:0));let frame0=table.tableView.convert(row0,to:controller.view)
        check("first-row-not-covered",frame0.minY>=navBottom-0.5,["firstRowY":frame0.minY])
        check("inset-grouped-table",table.tableView.style == .insetGrouped)
        check("no-automatic-double-insets",table.tableView.contentInsetAdjustmentBehavior == .never)
        snapshot(history ? "history" : "push")
        if history {
            check("all-four-fixture-records-visible",table.tableView.numberOfRows(inSection:1)==4)
            table.tableView.scrollToRow(at:IndexPath(row:0,section:1),at:.middle,animated:false);table.tableView.layoutIfNeeded()
            let badges=descendants(table.view).compactMap{$0 as? UILabel}.filter{["编辑前","已删除"].contains($0.text ?? "")}
            check("compact-reason-badges",!badges.isEmpty && badges.allSatisfy{$0.bounds.width <= $0.intrinsicContentSize.width+1})
            let footer=table.tableView.footerView(forSection:0) ?? table.tableView.subviews.first{view in descendants(view).contains{($0 as? UIButton)?.title(for:.normal)=="保存说明"}}
            if let label=footer.flatMap({descendants($0).compactMap{$0 as? UILabel}.first{($0.text ?? "").hasPrefix("记录仅保存")}}) {
                let wanted=label.sizeThatFits(CGSize(width:label.bounds.width,height:10000)).height
                check("saving-footer-text-not-truncated",label.bounds.height >= ceil(wanted)-1,["actualHeight":label.bounds.height,"wantedHeight":wanted,"width":label.bounds.width])
            } else {check("saving-footer-text-not-truncated",false)}
            table.tableView.delegate?.tableView?(table.tableView,didSelectRowAt:IndexPath(row:0,section:1));await pause(0.8)
            if let detail=navigation.viewControllers.last as? LegacyController,detail !== controller {
                let texts=descendants(detail.legacyController.view).compactMap{$0 as? UITextView}
                check("record-detail-keeps-full-body",texts.contains{($0.text ?? "").contains("这是保留的原始版本内容")})
                let frame=detail.legacyController.view.convert(detail.legacyController.view.bounds,to:detail.view)
                check("detail-starts-below-navigation",frame.minY>=navBottom-0.5)
                snapshot("history-detail")
                navigation.setViewControllers([root,controller],animated:false);await pause(0.5)
                check("return-to-list-keeps-navigation-clear",table.view.convert(table.view.bounds,to:controller.view).minY>=navBottom-0.5)
            } else {check("record-detail-keeps-full-body",false)}
            table.tableView.scrollToRow(at:IndexPath(row:1,section:0),at:.top,animated:false);table.tableView.layoutIfNeeded()
            if let toggle=table.tableView.cellForRow(at:IndexPath(row:1,section:0))?.accessoryView as? UISwitch,let postbox {
                toggle.isOn=false;toggle.sendActions(for:.valueChanged);await pause()
                let off=await value(wygramMessageHistorySettings(postbox:postbox) |> take(1))
                check("toggle-persists-setting",!off.keepEditHistory)
                if let restored=table.tableView.cellForRow(at:IndexPath(row:1,section:0))?.accessoryView as? UISwitch {restored.isOn=true;restored.sendActions(for:.valueChanged);await pause()}
                let on=await value(wygramMessageHistorySettings(postbox:postbox) |> take(1));check("toggle-observation-survives-update",on.keepEditHistory)
            } else {check("toggle-persists-setting",false)}
            if let search=descendants(table.view).compactMap({$0 as? UISearchBar}).first {
                check("dynamic-text-size-applied",!large || (search.searchTextField.font?.pointSize ?? 0)>30,["fontSize":search.searchTextField.font?.pointSize ?? 0])
                search.text="原始版本";search.delegate?.searchBar?(search,textDidChange:"原始版本");await pause()
                check("search-filters-history",table.tableView.numberOfRows(inSection:1)==1)
                search.text="不存在的查询";search.delegate?.searchBar?(search,textDidChange:"不存在的查询");await pause()
                check("empty-search-retains-placeholder",table.tableView.numberOfRows(inSection:1)==1)
                search.text="";search.delegate?.searchBar?(search,textDidChange:"");await pause()
                search.searchTextField.becomeFirstResponder();await pause(1)
                let keyboard=keyboardFrame.map{window.convert($0,from:window.screen.coordinateSpace)} ?? .zero
                let f=table.view.convert(table.view.bounds,to:window)
                check("search-keyboard-present",keyboard.height>100,["keyboardHeight":keyboard.height])
                check("keyboard-does-not-cover-list",keyboard.height>100 && f.maxY<=keyboard.minY+1,["listBottom":f.maxY,"keyboardTop":keyboard.minY])
                snapshot("history-keyboard");search.resignFirstResponder()
            }
        } else {
            check("seven-diagnostic-rows",table.tableView.numberOfRows(inSection:0)==7);check("four-action-rows",table.tableView.numberOfRows(inSection:1)==4)
            let first=table.tableView.cellForRow(at:IndexPath(row:0,section:0)).flatMap{descendants($0).compactMap{$0 as? UILabel}.first{$0.text=="系统通知"}}
            check("dynamic-text-size-applied",!large || (first?.font.pointSize ?? 0)>30,["fontSize":first?.font.pointSize ?? 0])
            // Each pass realizes estimated heights around the target; a second
            // pass scrolls using the actual accessibility-sized row heights.
            for _ in 0..<3 {table.tableView.scrollToRow(at:IndexPath(row:3,section:1),at:.bottom,animated:false);await pause(0.2);table.tableView.layoutIfNeeded()}
            let last=table.tableView.convert(table.tableView.rectForRow(at:IndexPath(row:3,section:1)),to:window)
            check("last-action-scrolls-above-home-indicator",last.maxY<=window.bounds.height-controller.currentlyAppliedLayout!.intrinsicInsets.bottom+1,["rowBottom":last.maxY,"viewBottom":window.bounds.height-controller.currentlyAppliedLayout!.intrinsicInsets.bottom])
            snapshot("push-actions")
        }
        let report:[String:Any] = ["passed":checks.allSatisfy{$0["passed"] as? Bool == true},"checks":checks,"mode":history ? "history" : "push","dark":dark,"large":large,"runID":ProcessInfo.processInfo.environment["WYGRAM_SETTINGS_PROBE_RUN_ID"] ?? "none"]
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:documents.appendingPathComponent("results.json"))
    }
}
private final class ProbeStatusHost:StatusBarHost {
    weak var window:UIWindow?;init(window:UIWindow){self.window=window}
    var isApplicationInForeground:Bool{true};var statusBarFrame:CGRect{window?.windowScene?.statusBarManager?.statusBarFrame ?? .zero};var keyboardWindow:UIWindow?{nil};var keyboardView:UIView?{nil}
}
