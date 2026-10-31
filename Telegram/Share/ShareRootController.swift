import UIKit
import TelegramUI
import BuildConfig
import ShareExtensionContext
import SwiftSignalKit
import TelegramCore
import SGAppGroupIdentifier

@objc(ShareRootController)
class ShareRootController: UIViewController {
    private var impl: ShareRootControllerImpl?
    private var fallback: WyGramShareFallbackController?
    private var startupTimeout: DispatchWorkItem?
    private var loadingView: UIStackView?
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        self.modalPresentationStyle = .fullScreen
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        super.loadView()
        self.view.backgroundColor = .systemBackground
        let title = UILabel()
        title.text = "正在打开 WyGram…"
        title.textAlignment = .center
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        let cancel = UIButton(type: .system)
        cancel.setTitle("取消", for: .normal)
        cancel.addTarget(self, action: #selector(cancelLoading), for: .touchUpInside)
        let loading = UIStackView(arrangedSubviews: [title, spinner, cancel])
        loading.axis = .vertical
        loading.spacing = 20
        loading.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
            loading.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 24),
            loading.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -24)
        ])
        self.loadingView = loading
        
        if self.impl == nil {
            guard let appBundleIdentifier = Bundle.main.bundleIdentifier,
                  let lastDotRange = appBundleIdentifier.range(of: ".", options: [.backwards]) else {
                self.showFallback()
                return
            }
            
            let baseAppBundleId = String(appBundleIdentifier[..<lastDotRange.lowerBound])
            
            let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
            
            let languagesCategory = "ios"
            
            guard let group = WyGramDirectShare.sharedAccountGroup() else {
                self.showFallback()
                return
            }
            let appGroupUrl = group.accountURL
            
            let rootPath = appGroupUrl.path + "/telegram-data"
            
            let deviceSpecificEncryptionParameters = BuildConfig.deviceSpecificEncryptionParameters(rootPath, baseAppBundleId: baseAppBundleId)
            let encryptionParameters: (Data, Data) = (deviceSpecificEncryptionParameters.key, deviceSpecificEncryptionParameters.salt)
            
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
            
            self.impl = ShareRootControllerImpl(initializationData: ShareRootControllerInitializationData(appBundleId: baseAppBundleId, appBuildType: buildConfig.isAppStoreBuild ? .public : .internal, appGroupPath: appGroupUrl.path, apiId: buildConfig.apiId, apiHash: buildConfig.apiHash, languagesCategory: languagesCategory, encryptionParameters: encryptionParameters, appVersion: appVersion, bundleData: buildConfig.bundleData(withAppToken: nil, tokenType: nil, tokenEnvironment: nil, signatureDict: nil), useBetaFeatures: !buildConfig.isAppStoreBuild, makeTempContext: { accountManager, appLockContext, applicationBindings, InitialPresentationDataAndSettings, networkArguments in
                return makeTempContext(
                    sharedContainerPath: appGroupUrl.path,
                    rootPath: rootPath,
                    appGroupPath: appGroupUrl.path,
                    accountManager: accountManager,
                    appLockContext: appLockContext,
                    encryptionParameters: EngineValueBoxEncryptionParameters(
                        forceEncryptionIfNoSet: false,
                        key: EngineValueBoxEncryptionParameters.Key(data: encryptionParameters.0)!,
                        salt: EngineValueBoxEncryptionParameters.Salt(data: encryptionParameters.1)!
                    ),
                    applicationBindings: applicationBindings,
                    initialPresentationDataAndSettings: InitialPresentationDataAndSettings,
                    networkArguments: networkArguments,
                    buildConfig: buildConfig
                )
            }), getExtensionContext: { [weak self] in
                return self?.extensionContext
            })
            
            self.impl?.openUrl = { [weak self] url in
                guard let self, let url = URL(string: url) else {
                    return
                }
                let _ = self.openURL(url)
            }
            self.impl?.initializationCompleted = { [weak self] in
                self?.startupTimeout?.cancel()
                self?.loadingView?.removeFromSuperview()
                self?.loadingView = nil
            }
            self.impl?.initializationFailed = { [weak self] in self?.showFallback() }
            let timeout = DispatchWorkItem { [weak self] in self?.showFallback() }
            self.startupTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        }
        
        self.impl?.loadView()
    }

    private func showFallback() {
        guard self.fallback == nil else { return }
        self.startupTimeout?.cancel()
        self.loadingView?.removeFromSuperview()
        self.loadingView = nil
        self.impl?.stop()
        self.impl = nil
        let providers = (self.extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let controller = WyGramShareFallbackController(inbox: WyGramShareInbox.preparedForImport(inboxes: WyGramShareInbox.current()), providers: providers, finish: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        })
        self.fallback = controller
        self.addChild(controller)
        controller.view.frame = self.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    deinit { self.startupTimeout?.cancel() }

    @objc private func cancelLoading() {
        self.startupTimeout?.cancel()
        self.impl?.stop()
        self.impl = nil
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.impl?.viewWillAppear()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.impl?.viewWillDisappear()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.impl?.viewWillDisappear()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.impl?.viewDidLayoutSubviews(view: self.view, traitCollection: self.traitCollection)
        if let loadingView = self.loadingView { self.view.bringSubviewToFront(loadingView) }
    }
    
    @objc func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                if #available(iOS 18.0, *) {
                    application.open(url, options: [:], completionHandler: nil)
                    return true
                } else {
                    return application.perform(#selector(openURL(_:)), with: url) != nil
                }
            }
            responder = responder?.next
        }
        return false
    }
}
