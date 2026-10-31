import Foundation
import SwiftSignalKit
import TelegramCore

final class WyGramForegroundConnectionRecovery {
    private var policy = WyGramForegroundRecoveryPolicy()
    private var timer: SwiftSignalKit.Timer?
    private let statusDisposable = MetaDisposable()

    func enterBackground() {
        self.policy.enterBackground(at: WyGramForegroundRecoveryPolicy.currentTime())
        self.stopMonitoring()
    }

    func activate(account: Account?) {
        guard self.policy.activate(at: WyGramForegroundRecoveryPolicy.currentTime()), let account else { return }
        self.stopMonitoring()
        // Reassert foreground ownership even if a background extension expired
        // while the process was suspended. The normal wakeup manager agrees.
        account.postbox.setCanBeginTransactions(true)
        account.shouldBeServiceTaskMaster.set(.single(.always))
        // Watch the same state shown by the chat list, including a message-sync
        // spinner while the underlying socket itself already reports online.
        self.statusDisposable.set((account.networkState
        |> deliverOnMainQueue).start(next: { [weak self] status in
            guard let self else { return }
            let value: WyGramForegroundRecoveryPolicy.Status
            switch status {
            case .waitingForNetwork: value = .unavailable
            case .connecting: value = .connecting
            case .updating: value = .updating
            case .online: value = .online
            }
            self.policy.update(value, at: WyGramForegroundRecoveryPolicy.currentTime())
        }))
        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self, weak account] in
            guard let self else { return }
            let now = WyGramForegroundRecoveryPolicy.currentTime()
            if self.policy.shouldReconnect(at: now) {
                // Reuse authentication and queued requests; never log out, clear
                // history or change the user's VPN / proxy configuration.
                account?.network.reconnectAfterSuspension()
                if self.policy.status == .updating {
                    account?.retryStateSynchronizationAfterSuspension()
                }
            }
            if !self.policy.isMonitoring(at: now) { self.stopMonitoring() }
        }, queue: .mainQueue())
        self.timer = timer
        timer.start()
    }

    private func stopMonitoring() {
        self.timer?.invalidate()
        self.timer = nil
        self.statusDisposable.set(nil)
    }

    deinit {
        self.timer?.invalidate()
        self.statusDisposable.dispose()
    }
}
