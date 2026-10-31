import Foundation
import UIKit
import Combine
import WGAppUpdate
import AccountContext
import Display
import TelegramPresentationData
import PresentationDataUtils

public func wygramAppUpdateController(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    return wygramAppUpdateViewController(theme: data.theme, strings: data.strings, presentMessage: { title, message in
        context.sharedContext.presentGlobalController(textAlertController(context: context, title: title, text: message, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), nil)
    })
}

public func wygramAppUpdateViewController(theme: PresentationTheme, strings: PresentationStrings, updater: WGAppUpdater? = nil, presentMessage: @escaping (String, String) -> Void) -> ViewController {
    let wrapper = WyGramSettingsWrapper(theme: theme, strings: strings)
    let chinese = strings.baseLanguageCode.hasPrefix("zh")
    wrapper.title = wygramUpdateText("AppUpdate.Title", chinese: chinese)
    let content = WyGramUpdateList(theme: theme, chinese: chinese, updater: updater, presentMessage: presentMessage)
    Task { @MainActor [weak wrapper, weak content] in content?.filePicker.owner = wrapper }
    wrapper.bind(controller: content)
    return wrapper
}

private final class WyGramUpdateList: WyGramSettingsTableController {
    private enum Row {
        case version, check, github, status, notes, prepare, install, cancel
        case automaticCheck, automaticPrepare, certificate, profiles, importMaterials, importProfiles, removeCertificate, node
    }
    private let updater: WGAppUpdater
    let filePicker = WGUpdateCredentialFilePicker()
    private let chinese: Bool
    private let presentMessage: (String, String) -> Void
    private var subscriptions = Set<AnyCancellable>()
    private var credentialBusy = false { didSet { if isViewLoaded { tableView.reloadData() } } }
    private var notesExpanded = false
    private var rows: [[Row]] {
        var status: [Row] = [.version, .check, .github, .status]
        if let release = updater.release, !release.notes.isEmpty { status.append(.notes) }
        if updater.hasPreparedUpdate { status.append(.install) }
        else if updater.release != nil { status.append(.prepare) }
        if updater.stage.isBusy { status.append(.cancel) }
        var certificate: [Row] = [.certificate, .profiles, .importMaterials, .importProfiles]
        if !updater.certificateName.isEmpty { certificate.append(.removeCertificate) }
        return [status, [.automaticCheck, .automaticPrepare], certificate, [.node]]
    }
    init(theme: PresentationTheme, chinese: Bool, updater: WGAppUpdater?, presentMessage: @escaping (String, String) -> Void) {
        self.updater = updater ?? .shared
        self.chinese = chinese
        self.presentMessage = presentMessage
        super.init(theme: theme)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func text(_ key: String) -> String { wygramUpdateText("AppUpdate." + key, chinese: chinese) }
    private var blocked: Bool { updater.stage.isBusy || credentialBusy || filePicker.isPresented }
    override func viewDidLoad() {
        super.viewDidLoad()
        updater.objectWillChange.throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true).sink { [weak self] _ in
            // Published sends before updating its value.
            DispatchQueue.main.async { self?.tableView.reloadData() }
        }.store(in: &subscriptions)
        filePicker.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.tableView.reloadData() } }.store(in: &subscriptions)
        updater.start()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows[section].count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return text("Title")
        case 1: return chinese ? "更新偏好" : "Update Preferences"
        case 2: return text("MethodCertificate")
        default: return text("InstallationNode")
        }
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return chinese ? "从 Wyatt323/WyGram 的正式 GitHub Release 获取更新，下载后校验 SHA-256。安装仍需确认 iOS 的提示。" : "Updates come from official releases in Wyatt323/WyGram and are verified with SHA-256. Confirm the iOS prompt to install."
        case 1: return text("AutomaticNotice")
        case 2: return text("CertificateNotice")
        default: return text("ServiceNotice")
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let currentRows = rows
        guard currentRows.indices.contains(indexPath.section), currentRows[indexPath.section].indices.contains(indexPath.row) else { return UITableViewCell() }
        let row = currentRows[indexPath.section][indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        style(cell)
        cell.selectionStyle = .none
        var enabled = true
        func action(_ title: String, enabled value: Bool = true, destructive: Bool = false) {
            cell.textLabel?.text = title
            cell.textLabel?.textColor = destructive ? settingsTheme.list.itemDestructiveColor : settingsTheme.list.itemAccentColor
            cell.selectionStyle = .default
            enabled = value
        }
        switch row {
        case .version:
            cell.textLabel?.text = "WyGram \(updater.installedVersion) (\(updater.installedBuild))"
            cell.detailTextLabel?.text = text("CurrentVersion")
        case .check: action(text("Check"), enabled: !blocked)
        case .github: action(text("OpenGitHub")); cell.accessoryType = .disclosureIndicator
        case .status:
            cell.textLabel?.text = wygramUpdateText(updater.stage.localizationKey, chinese: chinese)
            var details: [String] = []
            if let release = updater.release { details.append("WyGram \(release.version) (\(release.build))") }
            if updater.stage == .downloading {
                details.append("\(Int(updater.progress * 100))% · \(ByteCountFormatter.string(fromByteCount: updater.downloadedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: updater.release?.size ?? 0, countStyle: .file))")
            }
            if let error = updater.failure {
                if let bundle = error.profileBundle { details.append(String(format: text("ProfileBundle"), bundle)) }
                if let entitlement = error.profileEntitlement { details.append(String(format: text("ProfileEntitlement"), entitlement)) }
            }
            cell.detailTextLabel?.text = details.joined(separator: "\n")
            if updater.stage.isBusy {
                let spinner = UIActivityIndicatorView(style: .medium)
                spinner.startAnimating()
                cell.accessoryView = spinner
            }
        case .notes:
            action(text("ReleaseNotes"))
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = notesExpanded ? updater.release?.notes : nil
        case .prepare: action(text(updater.hasDownloadedUpdate ? "SignCached" : "Prepare"), enabled: !blocked && updater.isConfigured)
            if !updater.isConfigured { cell.detailTextLabel?.text = text("NotConfigured") }
        case .install: action(text("Install"), enabled: !blocked)
        case .cancel: action(text("Cancel"), destructive: true)
        case .automaticCheck, .automaticPrepare:
            let automaticCheck = row == .automaticCheck
            cell.textLabel?.text = text(automaticCheck ? "AutomaticCheck" : "AutomaticPrepare")
            let toggle = UISwitch()
            toggle.isOn = automaticCheck ? updater.automaticallyCheck : updater.automaticallyPrepare
            toggle.isEnabled = !blocked && (automaticCheck || updater.isConfigured)
            toggle.tag = automaticCheck ? 0 : 1
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
        case .certificate:
            cell.textLabel?.text = credentialBusy ? text("Importing") : (updater.certificateName.isEmpty ? text("NotConfigured") : updater.certificateName)
            cell.detailTextLabel?.text = chinese ? "仅保存在本机钥匙串" : "Stored only in this device’s Keychain"
        case .profiles: cell.textLabel?.text = String(format: text("SavedProfiles"), String(updater.savedProfileCount))
        case .importMaterials: action(text("ImportSigningMaterials"), enabled: !blocked)
        case .importProfiles: action(text("ImportProfiles"), enabled: !blocked)
        case .removeCertificate: action(text("RemoveCertificate"), enabled: !blocked, destructive: true)
        case .node:
            action(text("InstallationNode"), enabled: !blocked)
            cell.detailTextLabel?.text = updater.availableNodes.first(where: { $0.code == updater.preferredNode })?.name ?? text("AutomaticNode")
            cell.accessoryType = .disclosureIndicator
        }
        cell.isUserInteractionEnabled = enabled
        cell.contentView.alpha = enabled ? 1.0 : 0.45
        return cell
    }
    @objc private func toggleChanged(_ toggle: UISwitch) {
        if toggle.tag == 0 { updater.automaticallyCheck = toggle.isOn }
        else { updater.automaticallyPrepare = toggle.isOn }
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let currentRows = rows
        guard currentRows.indices.contains(indexPath.section), currentRows[indexPath.section].indices.contains(indexPath.row) else { return }
        switch currentRows[indexPath.section][indexPath.row] {
        case .check: updater.check()
        case .github: UIApplication.shared.open(updater.githubReleaseURL, options: [:])
        case .notes: notesExpanded.toggle(); tableView.reloadData()
        case .prepare: updater.prepare()
        case .install:
            confirm(title: text("Install"), message: chinese ? "确认后将请求系统覆盖安装。系统接收更新包后，请回到主屏幕等待安装完成，再重新打开 WyGram。" : "Confirm to request installation. After iOS receives the update, return to the Home Screen and reopen WyGram when installation finishes.") { self.updater.install() }
        case .cancel: updater.cancel()
        case .importMaterials: selectFiles(kind: .signingMaterials)
        case .importProfiles: selectFiles(kind: .profiles)
        case .removeCertificate:
            confirm(title: text("RemoveCertificate"), message: chinese ? "移除本机保存的更新证书、密码和描述文件？聊天数据不受影响。" : "Remove saved update credentials and profiles? Chats are unaffected.", destructive: true) {
                do { try self.updater.clearCertificate() } catch { self.show(error) }
            }
        case .node:
            let sheet = UIAlertController(title: text("InstallationNode"), message: nil, preferredStyle: .actionSheet)
            for (title, code) in [(text("AutomaticNode"), "")] + updater.availableNodes.map({ ($0.name, $0.code) }) {
                sheet.addAction(UIAlertAction(title: title, style: .default) { _ in self.updater.preferredNode = code })
            }
            sheet.addAction(UIAlertAction(title: text("Cancel"), style: .cancel))
            showNative(sheet)
        default: break
        }
    }
    private func showNative(_ controller: UIViewController) {
        guard var presenter = view.window?.rootViewController else { return }
        while let next = presenter.presentedViewController { presenter = next }
        controller.popoverPresentationController?.sourceView = tableView
        controller.popoverPresentationController?.sourceRect = CGRect(x: tableView.bounds.midX, y: tableView.bounds.midY, width: 1, height: 1)
        presenter.present(controller, animated: true)
    }
    private func confirm(title: String, message: String, destructive: Bool = false, action: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: text("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: title, style: destructive ? .destructive : .default) { _ in action() })
        showNative(alert)
    }
    private func show(_ error: Error) {
        let key = (error as? WGUpdateCredentialFileError)?.localizationKey ?? (error as? WGUpdateError ?? .network).localizationKey
        var message = wygramUpdateText(key, chinese: chinese)
        if let failure = error as? WGUpdateError {
            if let bundle = failure.profileBundle { message += "\n\n" + String(format: text("ProfileBundle"), bundle) }
            if let entitlement = failure.profileEntitlement { message += "\n" + String(format: text("ProfileEntitlement"), entitlement) }
        }
        presentMessage(text("Title"), message)
    }
    private func selectFiles(kind: WGUpdateCredentialFileKind) {
        filePicker.present(kind: kind) { [weak self] urls in
            guard let self, let urls else { return }
            guard !urls.isEmpty, urls.count <= 16 else { self.show(WGUpdateCredentialFileError.unreadable); return }
            let certificateIndex = urls.firstIndex(where: { WGUpdateCredentialFileKind.certificate.acceptsExtension($0.pathExtension) })
            if kind == .signingMaterials, urls.filter({ WGUpdateCredentialFileKind.certificate.acceptsExtension($0.pathExtension) }).count != 1 {
                self.show(WGUpdateCredentialFileError.certificateSelection); return
            }
            self.credentialBusy = true
            Task { @MainActor in
                defer { self.credentialBusy = false }
                do {
                    let data = try await Task.detached(priority: .userInitiated) {
                        try urls.map { try WGUpdateCredentialFile.read(url: $0, kind: kind) }
                    }.value
                    if kind == .profiles { try await self.updater.importProfiles(data) }
                    else if let index = certificateIndex {
                        guard let password = await self.filePicker.requestPassword(fileName: urls[index].lastPathComponent, title: self.text("ImportSigningMaterials"), placeholder: self.text("CertificatePassword"), confirm: self.text("ImportConfirm"), cancel: self.text("Cancel")) else { return }
                        try await self.updater.importCertificate(data[index], password: password, profiles: data.enumerated().filter { $0.offset != index }.map(\.element))
                    }
                    self.presentMessage(self.text("Title"), kind == .profiles ? String(format: self.text("ProfilesImported"), String(data.count)) : self.text("CertificateImported"))
                } catch { self.show(error) }
            }
        }
    }
}
