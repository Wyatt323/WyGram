import UIKit
import Display
import AccountContext
import TelegramPresentationData
import SGAppGroupIdentifier

public func wygramDirectShareController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let chinese = data.strings.baseLanguageCode.hasPrefix("zh")
    let wrapper = WyGramSettingsWrapper(theme: data.theme, strings: data.strings)
    wrapper.title = chinese ? "系统分享" : "System Sharing"
    wrapper.bind(controller: WyGramDirectShareSettings(theme: data.theme, chinese: chinese))
    return wrapper
}

private final class WyGramDirectShareSettings: WyGramSettingsTableController {
    private let chinese: Bool
    private var groups: [WyGramDirectShare.Group] = []
    private var destinations: [WyGramDirectShare.Group] = []
    private var pendingFiles = 0
    private var shared = false
    private var pending = false
    private var result: String?
    init(theme: PresentationTheme, chinese: Bool) {
        self.chinese = chinese
        super.init(theme: theme)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func text(_ zh: String, _ en: String) -> String { self.chinese ? zh : en }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); self.refresh() }
    private func refresh() {
        self.groups = WyGramDirectShare.availableGroups()
        self.destinations = WyGramDirectShare.setupGroups(self.groups)
        self.pendingFiles = WyGramShareInbox.current().reduce(0) { $0 + $1.pending().count }
        self.shared = UserDefaults.standard.string(forKey: WyGramDirectShare.selectionKey) == "shared" && WyGramDirectShare.sharedAccountGroup() != nil
        self.pending = UserDefaults.standard.string(forKey: WyGramDirectShare.requestKey) != nil
        self.result = UserDefaults.standard.string(forKey: WyGramDirectShare.resultKey)
        self.tableView.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? self.text("分享方式", "Sharing mode") : nil
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return self.text("启用直接分享后，在其他应用中选择 WyGram，即可在分享面板内选择聊天并发送。分享面板需要访问已登录的账号。", "Direct sharing lets you choose chats and send inside another app's share sheet. The extension needs access to your signed-in accounts.")
        }
        if section == 1 {
            return self.text("必须为主应用与 Share 扩展签入相同且可用的 App Group 权限。在线更新会沿用已安装版的权限，不能补齐缺失的权限；权限不足时仍可在聊天中添加附件。", "The app and Share extension need a common, authorised App Group. Updates preserve installed permissions and cannot grant missing rights. You can still attach files from a chat.")
        }
        if section == 2 {
            return self.text("后备分享完成后，可在这里手动接收待分享文件。附件暂存一小时，只在你选择聊天并确认后发送。", "Receive pending fallback shares here. Attachments are kept for one hour and sent only after you choose a chat and confirm.")
        }
        return nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        self.style(cell)
        cell.selectionStyle = indexPath.section == 0 ? .none : .default
        if indexPath.section == 0 {
            if self.shared {
                cell.textLabel?.text = self.text("直接分享已就绪", "Direct sharing is ready")
                cell.detailTextLabel?.text = self.text("在其他应用的分享菜单中选择 WyGram。", "Choose WyGram in another app's share menu.")
            } else if self.pending {
                cell.textLabel?.text = self.text("等待完整重新启动", "Restart required")
                cell.detailTextLabel?.text = self.text("请先关闭其他应用中的分享面板，再从多任务关闭 WyGram 并重新打开。无需退出账号。", "Close other share sheets, then close WyGram from the app switcher and reopen it. Stay signed in.")
            } else {
                cell.textLabel?.text = self.groups.isEmpty ? self.text("缺少共同共享权限", "Common sharing permission unavailable") : self.text("尚未启用直接分享", "Direct sharing is not enabled")
                cell.detailTextLabel?.text = self.failureText()
            }
        } else if indexPath.section == 1 {
            cell.textLabel?.text = self.shared ? self.text("直接分享已启用", "Direct sharing enabled") : self.pending ? self.text("取消启用", "Cancel setup") : self.text("启用直接分享", "Enable direct sharing")
            cell.textLabel?.textColor = self.settingsTheme.list.itemAccentColor
            cell.isUserInteractionEnabled = !self.shared
            cell.contentView.alpha = cell.isUserInteractionEnabled ? 1 : 0.45
        } else if indexPath.section == 2 {
            cell.textLabel?.text = self.text("接收待分享文件", "Receive pending shares")
            cell.detailTextLabel?.text = self.pendingFiles == 0 ? self.text("当前没有待分享文件", "No pending shares") : self.text("待分享批次：\(self.pendingFiles)", "Pending shares: \(self.pendingFiles)")
            cell.textLabel?.textColor = self.settingsTheme.list.itemAccentColor
        } else {
            cell.textLabel?.text = self.text("复制分享状态", "Copy sharing status")
            cell.textLabel?.textColor = self.settingsTheme.list.itemAccentColor
        }
        return cell
    }
    private func failureText() -> String {
        if self.groups.isEmpty { return self.text("当前签名未提供主应用与 Share 扩展共同可用的接收目录。请向签名提供方确认两者的 App Group 权限。", "This signature provides no common receiving directory for the app and Share extension. Ask your signing provider to check both components' App Group permissions.") }
        if self.destinations.isEmpty {
            return self.text("无法创建 WyGram 的独立共享位置。请检查剩余空间和共享权限，再重新尝试。当前账号和记录已保留。", "A separate WyGram location cannot be prepared. Check free space and sharing permission, then retry. Your current account and records are preserved.")
        }
        switch self.result {
        case "occupied": return self.text("上次目标目录已被占用。现在会为 WyGram 创建独立位置，可重新启用；不会覆盖已有数据。", "The previous destination was occupied. Setup now creates a separate WyGram location; retry without overwriting existing data.")
        case "move", "source", "interrupted", "directory": return self.text("上次启用未完成，当前账号和记录已保留。可重新尝试或复制状态反馈。", "Setup did not finish; your current account and records were preserved. Retry or copy the status for support.")
        default: return self.text("启用后完整重新启动一次，即可在分享面板内选择收件人。", "Enable this and restart once to choose recipients in the share sheet.")
        }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 2 {
            NotificationCenter.default.post(name: WyGramShareInbox.importRequested, object: nil)
            self.refresh()
            return
        }
        if indexPath.section == 3 {
            self.refresh()
            UIPasteboard.general.string = "WyGram \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?"))\n共同共享目录: \(self.groups.count)\n可启用共享目录: \(self.destinations.count)\n待分享批次: \(self.pendingFiles)\n接收状态: \(UserDefaults.standard.string(forKey: WyGramShareInbox.importStatusKey) ?? "none")\n账号存储: \(UserDefaults.standard.string(forKey: WyGramDirectShare.selectionKey) ?? "unknown")\n直接分享: \(self.shared ? "ready" : "unavailable")\n待启用: \(self.pending)\n启用结果: \(self.result ?? "none")"
            return
        }
        guard indexPath.section == 1, !self.shared else { return }
        if self.pending {
            WyGramDirectShare.cancelRequest()
            UserDefaults.standard.synchronize()
            self.refresh()
            return
        }
        self.refresh()
        guard let group = self.destinations.first else {
            let alert = UIAlertController(title: self.text("暂时无法启用", "Cannot enable yet"), message: self.failureText(), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: self.text("知道了", "OK"), style: .default))
            self.present(alert, animated: true)
            return
        }
        let alert = UIAlertController(title: self.text("启用直接分享", "Enable direct sharing"), message: self.text("分享扩展将能读取你已登录的账号。账号和本地消息、保留图片将完整保留；不会退出登录。\n\n请先关闭所有分享面板，然后从多任务关闭 WyGram 并重新打开，完成一次安全切换。", "The Share extension will be able to access your signed-in accounts. Your accounts, local messages and retained photos will be kept and you will stay signed in.\n\nClose all share sheets, then close WyGram from the app switcher and reopen it to complete setup."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.text("取消", "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: self.text("启用", "Enable"), style: .default, handler: { [weak self] _ in
            if !WyGramDirectShare.request(group: group) {
                WyGramDirectShare.cancelRequest()
            }
            self?.refresh()
        }))
        self.present(alert, animated: true)
    }
}
