import UIKit
import UniformTypeIdentifiers
import SGAppGroupIdentifier

// Used when the main account lives in the app's private sandbox. Only selected
// files are copied; a normal recipient confirmation still happens in WyGram.
final class WyGramShareFallbackController: UIViewController {
    private let inbox: WyGramShareInbox?
    private let providers: [NSItemProvider]
    private let finish: () -> Void
    private let openApp: (@escaping (Bool) -> Void) -> Void
    private let queue = DispatchQueue(label: "WyGram.ShareImport")
    private let queueKey = DispatchSpecificKey<Bool>()
    private let id = UUID().uuidString
    private var items: [WyGramShareInbox.Item] = []
    private var progress: Progress?
    private var timeout: DispatchWorkItem?
    private var stopped = false
    private var published = false
    private let label = UILabel()
    private let button = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(inbox: WyGramShareInbox?, providers: [NSItemProvider], finish: @escaping () -> Void, openApp: @escaping (@escaping (Bool) -> Void) -> Void) {
        self.inbox = inbox
        self.providers = providers
        self.finish = finish
        self.openApp = openApp
        super.init(nibName: nil, bundle: nil)
        self.queue.setSpecific(key: self.queueKey, value: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "WyGram"
        title.font = .preferredFont(forTextStyle: .title2)
        title.textAlignment = .center
        self.label.numberOfLines = 0
        self.label.textAlignment = .center
        self.label.font = .preferredFont(forTextStyle: .body)
        self.button.setTitle("在 WyGram 中继续", for: .normal)
        self.button.addTarget(self, action: #selector(continueInApp), for: .touchUpInside)
        self.button.isHidden = true
        let cancel = UIButton(type: .system)
        cancel.setTitle("取消", for: .normal)
        cancel.addTarget(self, action: #selector(self.cancel), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [title, self.label, self.spinner, self.button, cancel])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -28)
        ])
        guard let inbox = self.inbox else {
            self.label.text = "当前签名未提供 WyGram 与分享扩展可共同访问的 App Group，系统分享无法读取登录账号或传递文件。\n\n请关闭此面板，在 WyGram 聊天中通过“附件 → 文件”添加。签名时需为主应用及 Share 扩展保留同一个 App Group 权限。"
            return
        }
        guard !self.providers.isEmpty, self.providers.count <= WyGramShareInbox.maximumItems else {
            self.label.text = "没有可导入的文件，或文件数量超过 100 个。请在 WyGram 中添加。"
            return
        }
        self.spinner.startAnimating()
        self.label.text = "正在准备文件…"
        self.queue.async { [weak self] in
            guard let self else { return }
            do {
                try inbox.begin(id: self.id)
                self.load(index: 0, inbox: inbox)
            } catch { self.fail(inbox: inbox) }
        }
    }

    private func load(index: Int, inbox: WyGramShareInbox) {
        guard !self.stopped else { return }
        if index == self.providers.count {
            do {
                _ = try inbox.finish(id: self.id, items: self.items)
                self.published = true
                DispatchQueue.main.async { [weak self] in
                    self?.spinner.stopAnimating()
                    self?.label.text = "文件已准备好。请在 WyGram 中选择聊天并确认发送。\n\n如果无法自动打开，请关闭分享面板后手动打开 WyGram；待发送文件保留一小时。"
                    self?.button.isHidden = false
                }
            } catch { self.fail(inbox: inbox) }
            return
        }
        let provider = self.providers[index]
        let timeout = DispatchWorkItem { [weak self] in self?.fail(inbox: inbox) }
        self.timeout = timeout
        self.queue.asyncAfter(deadline: .now() + 60, execute: timeout)
        let receive: (URL?, Error?) -> Void = { [weak self] url, error in
            guard let self else { return }
            // Copy synchronously within the provider callback. The URL becomes
            // invalid when the callback returns; serialise cancellation with it.
            let copy: () -> Void = {
                guard !self.stopped else { return }
                self.timeout?.cancel()
                guard let url, error == nil else { self.fail(inbox: inbox); return }
                do {
                    let total = self.items.reduce(Int64(0)) { $0 + $1.size }
                    let item = try inbox.copy(source: url, name: provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? url.lastPathComponent : (provider.suggestedName ?? url.lastPathComponent), id: self.id, index: index, remainingBytes: WyGramShareInbox.maximumBytes - total)
                    self.items.append(item)
                    self.queue.async { self.load(index: index + 1, inbox: inbox) }
                } catch { self.fail(inbox: inbox) }
            }
            if DispatchQueue.getSpecific(key: self.queueKey) == true { copy() } else { self.queue.sync(execute: copy) }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                receive(item as? URL, error)
            }
        } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) {
            self.progress = provider.loadFileRepresentation(forTypeIdentifier: type, completionHandler: receive)
        } else {
            self.fail(inbox: inbox)
        }
    }

    private func fail(inbox: WyGramShareInbox) {
        guard !self.stopped else { return }
        self.stopped = true
        self.timeout?.cancel()
        self.progress?.cancel()
        inbox.remove(id: self.id)
        DispatchQueue.main.async { [weak self] in
            self?.spinner.stopAnimating()
            self?.label.text = "无法读取所选文件，可能尚未从 iCloud 下载、文件权限不足或总大小超过 2 GB。\n\n请在“文件”中下载完成后重试，或在 WyGram 聊天中通过“附件 → 文件”添加。"
        }
    }

    @objc private func continueInApp() {
        self.button.isEnabled = false
        self.openApp { [weak self] opened in
            DispatchQueue.main.async {
                guard let self else { return }
                self.button.isEnabled = true
                if opened { self.finish() }
                else { self.label.text = "系统未允许从分享扩展打开应用。请关闭此面板后手动打开 WyGram，继续选择聊天并确认发送。" }
            }
        }
    }

    @objc private func cancel() {
        self.queue.async { [weak self] in
            guard let self else { return }
            self.stopped = true
            self.timeout?.cancel()
            self.progress?.cancel()
            self.inbox?.remove(id: self.id)
            DispatchQueue.main.async { self.finish() }
        }
    }

    deinit {
        self.timeout?.cancel()
        self.progress?.cancel()
        if !self.published { self.inbox?.remove(id: self.id) }
    }
}
