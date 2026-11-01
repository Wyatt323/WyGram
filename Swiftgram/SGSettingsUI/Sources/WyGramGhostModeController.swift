import UIKit
import Display
import AccountContext
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

public func wygramGhostModeController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let chinese = data.strings.baseLanguageCode.hasPrefix("zh")
    let wrapper = WyGramSettingsWrapper(theme: data.theme, strings: data.strings)
    wrapper.title = chinese ? "幽灵模式" : "Ghost Mode"
    wrapper.bind(controller: WyGramGhostModeController(postbox: context.account.postbox, theme: data.theme, chinese: chinese))
    return wrapper
}

final class WyGramGhostModeController: WyGramSettingsTableController {
    private let postbox: Postbox
    private let chinese: Bool
    private var settings: WyGramGhostModeSettings?
    private let observation = MetaDisposable()
    private let writes = DisposableSet()

    init(postbox: Postbox, theme: PresentationTheme, chinese: Bool) {
        self.postbox = postbox
        self.chinese = chinese
        super.init(theme: theme)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.observation.dispose(); self.writes.dispose() }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.observation.set((wygramGhostModeSettings(postbox: self.postbox)
        |> deliverOnMainQueue).start(next: { [weak self] settings in
            self?.settings = settings
            self?.tableView.reloadData()
        }))
    }
    private func text(_ zh: String, _ en: String) -> String { self.chinese ? zh : en }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 4 : 0 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? self.text("当前账号 · 仅本机生效", "Current account · This installation") : nil
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return self.text("四项可独立开启，保存后生效。快拍仍会在本机消除未读圆环，消息仍可在本机标为已读。", "Each switch is independent and applies when saved. Stories still lose their unread ring locally, and messages can still be marked read on this device.")
        }
        return self.text("仅停止这台 WyGram 的对应上报，不能撤回已发出或已进入秘密聊天发送序列的回执，也不能控制其他客户端。发送消息、互动或其他设备仍可能使你显示在线。关闭隐藏已读后，后续正常阅读会同步累计已读位置，之前的消息也可能随之变为已读。", "Only suppresses reports from this WyGram installation. It cannot undo sent receipts, withdraw receipts already sequenced for secret-chat delivery, or control other clients. Sending, interacting or another device may still make you appear online. After you turn read receipts back on, future normal reading synchronizes the cumulative read position and may mark earlier messages read too.")
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        self.style(cell)
        cell.selectionStyle = .none
        let titles = [self.text("不上报快拍浏览", "Hide Story Views"), self.text("不主动上报在线", "Hide Online Status"), self.text("不发送输入状态", "Hide Typing Activity"), self.text("不发送消息已读状态", "Hide Read Receipts")]
        let details = [self.text("不发送快拍的查看回执，包含置顶快拍。", "Suppress view receipts, including pinned stories."), self.text("停止在线心跳，并主动请求离线状态。", "Stop online heartbeats and request offline status."), self.text("隐藏正在输入、录音、上传和选择贴纸等提示。", "Hide typing, recording, uploading and sticker-selection indicators."), self.text("隐藏聊天和话题的已读，以及语音、视频等内容的已播放回执。", "Suppress chat and topic read receipts and media-playback receipts.")]
        cell.textLabel?.text = titles[indexPath.row]
        cell.detailTextLabel?.text = details[indexPath.row]
        let control = UISwitch()
        control.tag = indexPath.row
        control.accessibilityIdentifier = "wygram.ghost.\(indexPath.row)"
        control.accessibilityLabel = titles[indexPath.row]
        if let settings = self.settings {
            control.isOn = [settings.hideStoryViews, settings.hideOnline, settings.hideInputActivity, settings.hideReadReceipts][indexPath.row]
        }
        control.isEnabled = self.settings != nil
        control.onTintColor = self.settingsTheme.list.itemAccentColor
        control.addTarget(self, action: #selector(self.changed(_:)), for: .valueChanged)
        cell.accessoryView = control
        return cell
    }
    @objc private func changed(_ control: UISwitch) {
        let index = control.tag
        let enabled = control.isOn
        self.writes.add(wygramUpdateGhostModeSettings(postbox: self.postbox, { settings in
            switch index {
            case 0: settings.hideStoryViews = enabled
            case 1: settings.hideOnline = enabled
            case 2: settings.hideInputActivity = enabled
            case 3: settings.hideReadReceipts = enabled
            default: break
            }
        }).start())
    }
}
