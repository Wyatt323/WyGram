import Foundation
import UIKit
import UserNotifications
import Display
import LegacyUI
import TelegramPresentationData
import AccountContext
import SGAppGroupIdentifier

public func wygramPushStatusController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    return wygramPushStatusViewController(theme: data.theme, strings: data.strings, accountId: context.account.id.int64, retry: {
        UIApplication.shared.registerForRemoteNotifications()
        context.sharedContext.updateNotificationTokensRegistration()
    })
}

public func wygramPushStatusViewController(theme: PresentationTheme, strings: PresentationStrings, accountId: Int64, retry: @escaping () -> Void) -> ViewController {
    let wrapper = WyGramSettingsWrapper(theme: theme, strings: strings)
    let chinese = strings.baseLanguageCode.hasPrefix("zh")
    wrapper.title = chinese ? "消息通知状态" : "Notification Status"
    wrapper.bind(controller: WyGramPushList(accountId: accountId, chinese: chinese, theme: theme, retry: retry))
    return wrapper
}

private final class WyGramPushList: WyGramSettingsTableController {
    let accountId: Int64
    let chinese: Bool
    let retry: () -> Void
    var timer: Timer?
    var authorization = ""
    var rows: [(String, String)] = []
    var report = ""
    var authorizationAllowed = false
    var rowColors: [UIColor] = []
    let summary: WyGramStatusSummary
    let capabilities = WyGramPushCapabilities.load(WyGramPushCapabilities.enclosingApplication())
    init(accountId: Int64, chinese: Bool, theme: PresentationTheme, retry: @escaping () -> Void) {
        self.accountId = accountId; self.chinese = chinese; self.retry = retry
        self.summary = WyGramStatusSummary(theme: theme)
        super.init(theme: theme)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.timer?.invalidate() }
    func text(_ zh: String, _ en: String) -> String { self.chinese ? zh : en }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.summary.title.text = self.text("正在检查通知", "Checking notifications")
        self.summary.icon.image = UIImage(systemName: "bell.badge")
        self.summary.icon.tintColor = self.settingsTheme.list.itemAccentColor
        self.tableView.tableHeaderView = self.summary
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "status")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "action")
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.refresh()
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); self.timer?.invalidate(); self.timer = nil }
    func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationAllowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: self.authorization = self.text("已允许", "Allowed")
                case .denied: self.authorization = self.text("未允许，请到系统设置开启", "Denied; enable in system settings")
                default: self.authorization = self.text("尚未请求", "Not requested")
                }
                self.updateRows()
            }
        }
    }
    func updateRows() {
        let capabilities = self.capabilities
        let directory = WyGramPushDirectory.current()
        let apple = WyGramPushStatus.value("apple") ?? "waiting"
        let server = WyGramPushStatus.value("server.\(self.accountId)") ?? "not_registered"
        let last = directory.flatMap { WyGramPushStatus.lastReceived(directory: $0.url) }
        let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .medium
        let identity = capabilities.applicationIdentifier.map { $0.hasSuffix("." + (Bundle.main.bundleIdentifier ?? "")) }
        let identityText = identity.map { $0 ? self.text("与应用一致", "Matches app") : self.text("与应用不一致", "Does not match app") } ?? self.text("无法读取", "Unavailable")
        let appleText = apple == "registered" ? self.text("已取得苹果推送令牌", "Apple token received") : (apple == "waiting" ? self.text("等待苹果注册结果", "Waiting for Apple registration") : self.text("苹果注册失败：", "Apple registration failed: ") + apple)
        let serverText: String
        switch server {
        case "accepted": serverText = self.text("服务器已接受登记，待验证投递", "Registration accepted; delivery unverified")
        case "registering": serverText = self.text("正在登记", "Registering")
        case "not_registered": serverText = self.text("尚未登记", "Not registered")
        default: serverText = self.text("登记失败：", "Registration failed: ") + server
        }
        let bridgeText: String
        if UserDefaults.standard.string(forKey: "wygram.applicationDataStorage") == "local" {
            bridgeText = directory.map { WyGramPushBridge.accounts(directory: $0.url).contains(where: { $0.recordId == self.accountId }) ? self.text("兼容通用提醒已准备", "Generic compatibility alerts ready") : self.text("共享组可访问，等待账号配置", "Shared group available; waiting for account") } ?? self.text("证书共享组不可访问", "Signing shared groups unavailable")
        } else { bridgeText = self.text("使用原有共享账号存储", "Using shared account storage") }
        self.rows = [
            (self.text("系统通知", "System notifications"), self.authorization),
            (self.text("苹果推送注册", "Apple registration"), appleText),
            (self.text("Telegram 登记", "Telegram registration"), serverText),
            (self.text("通知处理", "Notification processing"), bridgeText),
            (self.text("最近收到推送", "Last extension delivery"), last.map { formatter.string(from: $0) } ?? self.text("暂无记录", "No record yet")),
            (self.text("推送环境", "Push environment"), capabilities.environment ?? self.text("未读取到，沿用构建配置", "Unknown; using build setting")),
            (self.text("签名身份", "Signing identity"), identityText)
        ]
        let report = self.rows.map { $0.0 + ": " + $0.1 }.joined(separator: "\n") + "\nWyGram " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + ")"
        guard report != self.report else { return }
        self.report = report
        let accent = self.settingsTheme.list.itemAccentColor
        let secondary = self.settingsTheme.list.itemSecondaryTextColor
        self.rowColors = [self.authorizationAllowed ? .systemGreen : .systemOrange, apple == "registered" ? .systemGreen : .systemOrange, server == "accepted" ? .systemOrange : (server == "registering" || server == "not_registered" ? secondary : .systemRed), accent, last == nil ? secondary : accent, accent, identity == true ? .systemGreen : .systemOrange]
        let summaryTitle: String
        let summaryDetail: String
        let color: UIColor
        if !self.authorizationAllowed {
            summaryTitle = self.text("系统通知尚未开启", "System notifications are off")
            summaryDetail = self.text("先在系统设置中允许通知，再检查下方的推送登记与签名状态。", "Allow notifications in system settings, then check registration and signing below.")
            color = .systemOrange
        } else if server == "APP_PUSH_CERT_MISSING" {
            summaryTitle = self.text("远程推送尚未就绪", "Remote push is not ready")
            summaryDetail = self.text("Telegram 未找到此应用的推送证书配置。重新登记不能单独补齐服务器配置。", "Telegram has no push certificate configured for this application. Registering again cannot supply that server configuration.")
            color = .systemRed
        } else if apple != "registered" {
            summaryTitle = self.text("苹果推送尚未就绪", "Apple registration is not ready")
            summaryDetail = self.text("请检查系统通知权限和签名配置，再尝试重新登记。", "Check system permission and signing, then try registering again.")
            color = .systemOrange
        } else if server == "accepted" {
            summaryTitle = last == nil ? self.text("已登记，等待实际推送", "Registered; awaiting a push") : self.text("已记录最近的推送", "A recent push was recorded")
            summaryDetail = self.text("登记成功不代表消息已送达，请通过实际后台和锁屏通知确认投递。", "Registration does not prove delivery. Verify a real message while the app is in the background and while locked.")
            color = last == nil ? .systemOrange : .systemGreen
        } else {
            summaryTitle = server == "registering" ? self.text("正在登记推送", "Registering for push") : self.text("推送登记未完成", "Push registration incomplete")
            summaryDetail = self.text("查看下方检查结果，确认系统权限、签名与 Telegram 服务配置。", "Review permission, signing and Telegram service configuration below.")
            color = .systemOrange
        }
        self.summary.title.text = summaryTitle
        self.summary.detail.text = summaryDetail
        self.summary.icon.image = UIImage(systemName: color == .systemGreen ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
        self.summary.icon.tintColor = color
        self.tableView.reloadData()
        self.view.setNeedsLayout()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? self.text("通知检查", "Notification checks") : self.text("操作与测试", "Actions and tests")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? self.rows.count : 4 }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            let capabilities = self.capabilities
            if let identity = capabilities.applicationIdentifier, let bundleId = Bundle.main.bundleIdentifier, !identity.hasSuffix("." + bundleId) {
                return self.text("当前签名身份与 WyGram 不一致。请签名提供方为现有应用配置匹配的推送权限和描述文件。Telegram 应用也需要对应的推送服务配置。", "The signing identity does not match WyGram. Ask the signing provider for matching push permissions and profiles for this app. The Telegram application also needs corresponding push-service configuration.")
            }
            return self.text("服务器接受登记不代表已送达。本地存储模式使用通用新消息提醒，不展示原文。", "Accepted registration does not prove delivery. App-local storage uses generic alerts without message previews.")
        }
        return self.text("本机测试会在 5 秒后显示，请先切到后台或锁屏。它只验证系统通知显示，不验证 Telegram 远程推送。复制的状态不包含推送令牌、密钥或消息内容。", "The local test appears after 5 seconds; background or lock the phone first. It tests system presentation, not remote Telegram delivery. Copied status contains no tokens, keys or messages.")
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: indexPath.section == 0 ? "status" : "action", for: indexPath)
        self.style(cell)
        var content = UIListContentConfiguration.subtitleCell()
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.color = self.settingsTheme.list.itemPrimaryTextColor
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = self.settingsTheme.list.itemSecondaryTextColor
        content.secondaryTextProperties.numberOfLines = 0
        content.textToSecondaryTextVerticalPadding = 4
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16)
        content.imageToTextPadding = 14
        content.imageProperties.maximumSize = CGSize(width: 24, height: 24)
        content.imageProperties.reservedLayoutSize = CGSize(width: 24, height: 24)
        if indexPath.section == 0 {
            content.text = self.rows[indexPath.row].0
            content.secondaryText = self.rows[indexPath.row].1
            let symbols = ["bell.badge", "apple.logo", "paperplane", "tray", "clock", "network", "checkmark.shield"]
            content.image = UIImage(systemName: symbols[indexPath.row])
            content.imageProperties.tintColor = self.rowColors[indexPath.row]
            if indexPath.row == 2 && self.rows[indexPath.row].1.contains("APP_PUSH_CERT_MISSING") { content.secondaryTextProperties.color = .systemRed }
            cell.selectionStyle = .none
            cell.accessoryType = .none
        } else {
            content.text = [self.text("重新登记推送", "Register push again"), self.text("测试本机通知", "Test local notification"), self.text("复制通知状态", "Copy notification status"), self.text("打开系统通知设置", "Open system settings")][indexPath.row]
            content.secondaryText = [self.text("重新请求苹果令牌并登记", "Request and register the Apple token"), self.text("5 秒后提醒，仅测试系统通知显示", "Appears in 5 seconds; tests system presentation only"), self.text("复制诊断结果，便于排查", "Copy diagnostic results for troubleshooting"), self.text("管理通知、声音和角标", "Manage alerts, sounds and badges")][indexPath.row]
            content.textProperties.color = self.settingsTheme.list.itemAccentColor
            content.image = UIImage(systemName: ["arrow.clockwise", "bell", "doc.on.doc", "gearshape"][indexPath.row])
            content.imageProperties.tintColor = self.settingsTheme.list.itemAccentColor
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        switch indexPath.row {
        case 0: self.retry(); self.refresh()
        case 1:
            let content = UNMutableNotificationContent(); content.title = "WyGram"
            content.body = self.text("本机通知测试成功。Telegram 远程推送仍需另行验证。", "Local notification test succeeded. Telegram remote delivery needs separate verification.")
            content.sound = .default; content.userInfo = ["wygram_notification_test": true]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "wygram.local-notification-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))) { [weak self] error in
                if let error { DispatchQueue.main.async { self?.show(error.localizedDescription) } }
            }
        case 2: UIPasteboard.general.string = self.report; self.show(self.text("通知状态已复制", "Notification status copied"))
        default:
            let address: String
            if #available(iOS 16.0, *) { address = UIApplication.openNotificationSettingsURLString }
            else { address = UIApplication.openSettingsURLString }
            if let url = URL(string: address) { UIApplication.shared.open(url) }
        }
    }
    func show(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.text("确定", "OK"), style: .default))
        self.present(alert, animated: true)
    }
}
