import Foundation
import UIKit
import QuickLook
import Display
import LegacyUI
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData

public func wygramMessageHistoryController(context: AccountContext, messageId: MessageId? = nil, peerId: PeerId? = nil) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    return wygramLocalMessageHistoryController(postbox: context.account.postbox, theme: data.theme, strings: data.strings, messageId: messageId, peerId: peerId)
}

public func wygramLocalMessageHistoryController(postbox: Postbox, theme: PresentationTheme, strings: PresentationStrings, messageId: MessageId? = nil, peerId: PeerId? = nil) -> ViewController {
    let chinese = strings.baseLanguageCode.hasPrefix("zh")
    let wrapper = WyGramSettingsWrapper(theme: theme, strings: strings)
    wrapper.title = chinese ? "消息记录" : "Message History"
    let table = WyGramHistoryList(postbox: postbox, theme: theme, strings: strings, messageId: messageId, peerId: peerId, chinese: chinese)
    table.wrapper = wrapper
    wrapper.bind(controller: table)
    return wrapper
}

private final class WyGramHistoryList: WyGramSettingsTableController, UISearchBarDelegate {
    let postbox: Postbox
    let theme: PresentationTheme
    let strings: PresentationStrings
    let messageId: MessageId?
    let peerId: PeerId?
    let chinese: Bool
    weak var wrapper: LegacyController?
    var entries: [WyGramArchivedMessage] = []
    var search = ""
    var visibleEntries: [WyGramArchivedMessage] = []
    var settingsUpdateDisposable: Disposable?
    let timeFormatter = DateFormatter()
    let dateFormatter = DateFormatter()
    var disposable: Disposable?
    var removalDisposable: Disposable?
    var loaded = false
    var settings = WyGramMessageHistorySettings()
    var settingsLoaded = false
    var settingsDisposable: Disposable?
    var savingFooter: UIView?

    init(postbox: Postbox, theme: PresentationTheme, strings: PresentationStrings, messageId: MessageId?, peerId: PeerId?, chinese: Bool) {
        self.postbox = postbox; self.theme = theme; self.strings = strings; self.messageId = messageId; self.peerId = peerId; self.chinese = chinese
        self.timeFormatter.timeStyle = .short
        self.timeFormatter.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
        self.dateFormatter.locale = self.timeFormatter.locale
        self.dateFormatter.setLocalizedDateFormatFromTemplate("MMMd HHmm")
        super.init(theme: theme)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { self.disposable?.dispose(); self.removalDisposable?.dispose(); self.settingsDisposable?.dispose(); self.settingsUpdateDisposable?.dispose() }
    func text(_ zh: String, _ en: String) -> String { return self.chinese ? zh : en }
    func updateVisibleEntries() {
        let query = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
        self.visibleEntries = query.isEmpty ? self.entries : self.entries.filter { ($0.text + " " + $0.chatName + " " + $0.authorName).localizedCaseInsensitiveContains(query) }
        self.wrapper?.navigationItem.rightBarButtonItem?.isEnabled = !self.entries.isEmpty
        self.tableView.reloadData()
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        let searchBar = UISearchBar()
        searchBar.placeholder = self.text("搜索消息记录", "Search message history")
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        searchBar.tintColor = self.theme.list.itemAccentColor
        searchBar.searchTextField.textColor = self.theme.list.itemPrimaryTextColor
        searchBar.searchTextField.font = .preferredFont(forTextStyle: .body)
        searchBar.searchTextField.adjustsFontForContentSizeCategory = true
        searchBar.searchTextField.backgroundColor = self.theme.list.itemBlocksBackgroundColor
        searchBar.autocapitalizationType = .none
        let header = UIView()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            searchBar.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),
            searchBar.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -2),
            searchBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
        self.tableView.tableHeaderView = header
        self.tableView.register(WyGramHistoryCell.self, forCellReuseIdentifier: "history")
        self.tableView.keyboardDismissMode = .onDrag
        self.tableView.estimatedRowHeight = 100
        self.tableView.rowHeight = UITableView.automaticDimension
        self.refreshControl = UIRefreshControl()
        self.refreshControl?.addTarget(self, action: #selector(reloadHistory), for: .valueChanged)
        self.wrapper?.navigationItem.rightBarButtonItem = UIBarButtonItem(title: self.text("清空", "Clear"), style: .plain, target: self, action: #selector(clearHistory))
        self.settingsDisposable = (wygramMessageHistorySettings(postbox: self.postbox) |> deliverOnMainQueue).start(next: { [weak self] settings in
            guard let self else { return }
            self.settings = settings; self.settingsLoaded = true; self.tableView.reloadData()
        })
        self.reloadHistory()
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); if self.isViewLoaded { self.reloadHistory() } }
    @objc func reloadHistory() {
        self.disposable?.dispose()
        self.disposable = (wygramMessageHistory(postbox: self.postbox, messageId: self.messageId, peerId: self.peerId) |> deliverOnMainQueue).start(next: { [weak self] entries in
            guard let self else { return }
            self.entries = entries; self.loaded = true
            self.refreshControl?.endRefreshing(); self.updateVisibleEntries()
        })
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { self.search = searchText; self.updateVisibleEntries() }
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { searchBar.setShowsCancelButton(true, animated: true) }
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) { searchBar.setShowsCancelButton(false, animated: true) }
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) { searchBar.text = ""; self.search = ""; self.updateVisibleEntries(); self.view.endEditing(true) }
    override func numberOfSections(in tableView: UITableView) -> Int { return 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 3 : max(1, self.visibleEntries.count)
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let title = self.search.isEmpty ? self.text("已保存记录", "Saved records") : self.text("搜索结果", "Search results")
        let count = NumberFormatter.localizedString(from: NSNumber(value: self.visibleEntries.count), number: .decimal)
        return section == 0 ? self.text("自动保存", "Automatically save") : title + " · " + count
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return self.text("记录仅保存在当前账号的本机数据中。图片需完整下载后才可保留。", "Records stay on this device, separately for each account. Photos must be fully downloaded to be retained.")
    }
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 0 else { return nil }
        if let footer = self.savingFooter { return footer }
        let footer = UIView()
        let label = UILabel()
        label.text = self.tableView(tableView, titleForFooterInSection: section)
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = self.theme.list.freeTextColor
        label.numberOfLines = 0
        let button = UIButton(type: .system)
        button.setTitle(self.text("保存说明", "About local saving"), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.tintColor = self.theme.list.itemAccentColor
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(showSavingInfo), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical; stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: footer.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -8),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        self.savingFooter = footer
        return footer
    }
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard section == 0, let footer = self.tableView(tableView, viewForFooterInSection: section) else { return UITableView.automaticDimension }
        // Inset-grouped footers are narrower than the table. Measure the custom
        // label and button together, rather than using the single-line default.
        let width = max(1, tableView.bounds.width - tableView.layoutMargins.left - tableView.layoutMargins.right)
        return ceil(footer.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }
    @objc func showSavingInfo() {
        let message = self.text("记录仅保存在当前账号的本机数据中。开启图片保留后，已完整下载的阅后即焚及仅查看一次照片会保存为本机副本，可重复查看，普通清理缓存不会删除。支持秘密聊天中的倒计时照片；不包括视频、语音和其他自动销毁消息。已经过期或未完整下载的图片无法恢复。关闭开关保留已有记录；删除图片记录会同时移除对应的本机聊天图片。", "Records stay on this device, separately for each account. Fully downloaded timed and view-once photos, including timed secret-chat photos, are kept as local copies for repeated viewing and survive normal cache cleanup. Videos, voice messages and other timed messages are excluded. Expired or incomplete photos cannot be recovered. Turning saving off keeps existing records. Deleting a saved photo record also removes its local chat photo.")
        let alert = UIAlertController(title: self.text("保存说明", "About local saving"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.text("知道了", "OK"), style: .default))
        self.present(alert, animated: true)
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 && !self.visibleEntries.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "history", for: indexPath) as! WyGramHistoryCell
            self.style(cell)
            let entry = self.visibleEntries[indexPath.row]
            let reason = entry.reason == "disappearing" ? self.text("已保留图片", "Saved photo") : entry.reason == "deleted" ? self.text("已删除", "Deleted") : self.text("编辑前", "Before edit")
            let color = entry.reason == "deleted" ? self.theme.list.itemDestructiveColor : self.theme.list.itemAccentColor
            cell.chatLabel.text = entry.chatName.isEmpty ? self.text("未知聊天", "Unknown chat") : entry.chatName
            cell.chatLabel.textColor = self.theme.list.itemPrimaryTextColor
            cell.statusLabel.text = reason
            cell.statusLabel.textColor = color
            cell.statusLabel.backgroundColor = color.withAlphaComponent(0.1)
            cell.authorLabel.text = entry.authorName == entry.chatName ? "" : entry.authorName
            cell.authorLabel.textColor = self.theme.list.itemSecondaryTextColor
            let date = Date(timeIntervalSince1970: TimeInterval(entry.capturedAt))
            cell.dateLabel.text = Calendar.current.isDateInToday(date) ? self.timeFormatter.string(from: date) : self.dateFormatter.string(from: date)
            cell.dateLabel.textColor = self.theme.list.itemSecondaryTextColor
            let preview = entry.text.isEmpty ? entry.attachments.prefix(3).map { $0.name }.joined(separator: " · ") : entry.text
            let compact = String(preview.prefix(600)).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            cell.previewLabel.text = compact.isEmpty ? self.text("媒体消息", "Media message") : compact
            cell.previewLabel.textColor = self.theme.list.itemSecondaryTextColor
            cell.accessibilityLabel = [reason, cell.chatLabel.text ?? "", cell.authorLabel.text ?? "", cell.dateLabel.text ?? "", cell.previewLabel.text ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
            return cell
        }
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        self.style(cell)
        if indexPath.section == 0 {
            cell.textLabel?.text = [self.text("保留被删除的消息", "Keep deleted messages"), self.text("保留编辑前的版本", "Keep previous versions"), self.text("保留阅后即焚图片", "Keep disappearing photos")][indexPath.row]
            let toggle = UISwitch()
            toggle.tag = indexPath.row
            toggle.isEnabled = self.settingsLoaded
            toggle.isOn = [self.settings.keepDeletedMessages, self.settings.keepEditHistory, self.settings.keepDisappearingPhotos][indexPath.row]
            toggle.onTintColor = self.theme.list.itemAccentColor
            toggle.accessibilityLabel = cell.textLabel?.text
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle; cell.selectionStyle = .none
        } else {
            cell.textLabel?.text = self.loaded ? (self.search.isEmpty ? self.text("暂无记录", "No records yet") : self.text("没有找到匹配记录", "No matching records")) : self.text("正在读取…", "Loading…")
            cell.detailTextLabel?.text = self.search.isEmpty ? self.text("删除、编辑前的消息和已保留的图片会显示在这里。", "Deleted messages, previous versions and retained photos appear here.") : self.text("试试其他关键词。", "Try another keyword.")
            cell.selectionStyle = .none
        }
        return cell
    }
    @objc func toggleChanged(_ sender: UISwitch) {
        if sender.tag == 0 { self.settings.keepDeletedMessages = sender.isOn }
        else if sender.tag == 1 { self.settings.keepEditHistory = sender.isOn }
        else { self.settings.keepDisappearingPhotos = sender.isOn }
        self.settingsUpdateDisposable?.dispose()
        self.settingsUpdateDisposable = wygramUpdateMessageHistorySettings(postbox: self.postbox, settings: self.settings).start()
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1, !self.visibleEntries.isEmpty else { return }
        let entry = self.visibleEntries[indexPath.row]
        let wrapper = WyGramSettingsWrapper(theme: self.theme, strings: self.strings)
        wrapper.title = entry.reason == "disappearing" ? self.text("已保留图片", "Saved photo") : self.text("消息旧版本", "Saved version")
        let detail = WyGramHistoryDetail(entry: entry, directory: wygramMessageHistoryDirectory(mediaBox: self.postbox.mediaBox), chinese: self.chinese)
        wrapper.bind(controller: detail)
        (self.wrapper?.navigationController as? NavigationController)?.pushViewController(wrapper)
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, !self.visibleEntries.isEmpty else { return nil }
        let key = self.visibleEntries[indexPath.row].key
        return UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: self.text("删除记录", "Delete record"), handler: { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            self.removalDisposable = (wygramRemoveMessageHistory(postbox: self.postbox, keys: [key]) |> deliverOnMainQueue).start(completed: { [weak self] in self?.reloadHistory(); completion(true) })
        })])
    }
    @objc func clearHistory() {
        let alert = UIAlertController(title: self.text("清空全部消息记录？", "Clear all message history?"), message: self.text("删除本机保存的记录及附件；已保留的阅后即焚图片也会从本机聊天中移除。", "This removes local records and attachments. Retained disappearing photos are also removed from this device’s chats."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: self.text("取消", "Cancel"), style: .cancel))
        let keys = self.entries.map { $0.key }
        alert.addAction(UIAlertAction(title: self.text("清空", "Clear"), style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            self.removalDisposable = (wygramRemoveMessageHistory(postbox: self.postbox, keys: keys) |> deliverOnMainQueue).start(completed: { [weak self] in self?.reloadHistory() })
        }))
        self.present(alert, animated: true)
    }
}

private final class WyGramHistoryDetail: UIViewController, QLPreviewControllerDataSource {
    let entry: WyGramArchivedMessage
    let directory: URL
    let chinese: Bool
    let previewUrls: [URL]
    init(entry: WyGramArchivedMessage, directory: URL, chinese: Bool) {
        self.entry = entry; self.directory = directory; self.chinese = chinese
        self.previewUrls = entry.attachments.compactMap { attachment in attachment.localFileName.map { directory.appendingPathComponent($0) } }.filter { FileManager.default.fileExists(atPath: $0.path) }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        let textView = UITextView()
        textView.isEditable = false; textView.isSelectable = true
        textView.font = .systemFont(ofSize: 17)
        textView.backgroundColor = .systemBackground
        let date = DateFormatter(); date.dateStyle = .medium; date.timeStyle = .medium
        let reason = self.entry.reason == "disappearing" ? (self.chinese ? "已保留的阅后即焚图片" : "Saved disappearing photo") : self.entry.reason == "deleted" ? (self.chinese ? "已删除的消息" : "Deleted message") : (self.chinese ? "编辑前的版本" : "Previous version")
        var text = "\(reason)\n\(self.entry.chatName)\n\(self.entry.authorName)\n\(date.string(from: Date(timeIntervalSince1970: TimeInterval(self.entry.versionTimestamp))))\n\n\(self.entry.text)"
        for attachment in self.entry.attachments {
            text += "\n\n📎 \(attachment.name)" + (attachment.localFileName == nil ? (self.chinese ? "（本机未保存文件）" : " (file unavailable)") : "")
        }
        for media in self.entry.media {
            if let contact = media as? TelegramMediaContact { text += "\n\n👤 \(contact.firstName) \(contact.lastName)\n\(contact.phoneNumber)" }
            else if let location = media as? TelegramMediaMap { text += "\n\n📍 \(location.latitude), \(location.longitude)" + (location.venue.map { "\n" + $0.title } ?? "") }
            else if let poll = media as? TelegramMediaPoll { text += "\n\n📊 \(poll.text)\n" + poll.options.map { "• " + $0.text }.joined(separator: "\n") }
        }
        let rendered = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label])
        let prefix = "\(reason)\n\(self.entry.chatName)\n\(self.entry.authorName)\n\(date.string(from: Date(timeIntervalSince1970: TimeInterval(self.entry.versionTimestamp))))\n\n"
        let offset = (prefix as NSString).length
        for entity in self.entry.entities {
            let range = NSRange(location: offset + entity.range.lowerBound, length: entity.range.upperBound - entity.range.lowerBound)
            guard range.location >= offset && NSMaxRange(range) <= offset + (self.entry.text as NSString).length else { continue }
            switch entity.type {
            case .Bold: rendered.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 17), range: range)
            case .Italic: rendered.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 17), range: range)
            case .Code, .Pre: rendered.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular), range: range)
            case let .TextUrl(url): rendered.addAttribute(.link, value: url, range: range)
            default: break
            }
        }
        textView.attributedText = rendered
        textView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(textView)
        let button = UIButton(type: .system)
        button.setTitle(self.chinese ? "查看已保存的附件" : "Open saved attachments", for: .normal)
        button.isHidden = self.previewUrls.isEmpty
        button.addTarget(self, action: #selector(openAttachments), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(button)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor), textView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 12), textView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -8), button.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor), button.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), button.heightAnchor.constraint(equalToConstant: self.previewUrls.isEmpty ? 0 : 48)
        ])
    }
    @objc func openAttachments() { let preview = QLPreviewController(); preview.dataSource = self; self.present(preview, animated: true) }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { return self.previewUrls.count }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { return self.previewUrls[index] as NSURL }
}
