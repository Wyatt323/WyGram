import Foundation
import UIKit
import SwiftSignalKit
import WGAppUpdate
import SGSettingsUI
import AppLock
import Display
import PresentationDataUtils

// Observe only the active account's ready/unlocked root. The updater itself is
// account independent and never accesses chat databases or session keys.
final class WyGramUpdatePresenter {
    private let disposable = MetaDisposable()
    private var presenting = false

    func activate(context: AuthorizedApplicationContext) {
        guard let lock = context.context.sharedContext.appLockContext as? AppLockContextImpl else { return }
        disposable.set((combineLatest(context.isReady.get(), lock.isCurrentlyLocked, wgAppUpdatePrompt.get())
        |> deliverOnMainQueue).start(next: { [weak self, weak context] ready, locked, prompt in
            guard let self, let context, ready, !locked, let prompt,
                  !self.presenting, UIApplication.shared.applicationState == .active,
                  let window = context.rootController.currentWindow else { return }
            Task { @MainActor in
                let updater = WGAppUpdater.shared
                guard updater.claimPrompt(prompt) else { return }
                let chinese = context.context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode.hasPrefix("zh")
                func text(_ key: String) -> String { wygramUpdateText("AppUpdate." + key, chinese: chinese) }
                self.presenting = true
                let message: String
                switch prompt.kind {
                case .available: message = "WyGram \(prompt.release.version) (\(prompt.release.build))\n\n" + String(prompt.release.notes.prefix(600))
                case .ready: message = String(format: text("InstallPrompt"), prompt.release.version)
                case let .failed(key): message = wygramUpdateText(key, chinese: chinese)
                }
                let alert = textAlertController(context: context.context, title: text("Title"), text: message, actions: [
                    TextAlertAction(type: .genericAction, title: text("Later"), action: { self.presenting = false }),
                    TextAlertAction(type: .defaultAction, title: text("Title"), action: {
                        self.presenting = false
                        context.rootController.pushViewController(wygramAppUpdateController(context: context.context))
                        if case .available = prompt.kind { updater.acceptAutomaticUpdate(prompt.release) }
                    })
                ])
                window.present(alert, on: .root, blockInteraction: false, completion: {})
            }
        }))
    }
    deinit { disposable.dispose() }
}
