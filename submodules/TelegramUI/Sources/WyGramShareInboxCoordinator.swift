import Foundation
import SGAppGroupIdentifier

// Main-queue lifecycle of the handoff. Account/lock/scene eligibility and window
// attachment are separate: account readiness may precede attaching its root.
final class WyGramShareInboxCoordinator {
    typealias Entry = (inbox: WyGramShareInbox, batch: WyGramShareInbox.Batch)

    private let inboxes: () -> [WyGramShareInbox]
    private let canPresent: () -> Bool
    private let present: (Entry) -> Bool
    private let status: (String) -> Void
    private let retryInterval: TimeInterval
    private let retryLimit: Int
    private var retry: DispatchWorkItem?
    private var attemptsRemaining = 0
    private var eligible = false
    private var stopped = false
    private var scanning = false
    private var presenting = false

    init(inboxes: @escaping () -> [WyGramShareInbox] = { WyGramShareInbox.current() }, canPresent: @escaping () -> Bool, present: @escaping (Entry) -> Bool, status: @escaping (String) -> Void = { _ in }, retryInterval: TimeInterval = 0.5, retryLimit: Int = 20) {
        self.inboxes = inboxes
        self.canPresent = canPresent
        self.present = present
        self.status = status
        self.retryInterval = retryInterval
        self.retryLimit = retryLimit
    }

    func setEligible(_ value: Bool) {
        guard !self.stopped else { return }
        let changed = self.eligible != value
        self.eligible = value
        if !value {
            self.retry?.cancel()
            self.retry = nil
        } else if changed {
            self.refresh()
        }
    }

    func refresh() {
        guard !self.stopped else { return }
        self.attemptsRemaining = self.retryLimit
        self.retry?.cancel()
        self.retry = nil
        self.check()
    }

    func finished() {
        self.presenting = false
        self.refresh()
    }

    func stop() {
        self.stopped = true
        self.eligible = false
        self.retry?.cancel()
        self.retry = nil
    }

    private func scheduleRetry() {
        guard !self.stopped, self.eligible, !self.presenting, self.retry == nil, self.attemptsRemaining > 0 else { return }
        self.attemptsRemaining -= 1
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retry = nil
            self.check()
        }
        self.retry = item
        DispatchQueue.main.asyncAfter(deadline: .now() + self.retryInterval, execute: item)
    }

    private func check() {
        guard !self.stopped, self.eligible, !self.scanning, !self.presenting else { return }
        guard self.canPresent() else {
            self.status("waiting-window")
            self.scheduleRetry()
            return
        }
        self.scanning = true
        self.status("scanning")
        let inboxes = self.inboxes
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entry: Entry? = inboxes().compactMap { inbox in
                inbox.pending().first.map { (inbox: inbox, batch: $0) }
            }.min { $0.batch.created < $1.batch.created }
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                guard !self.stopped, self.eligible, !self.presenting else { return }
                guard self.canPresent() else {
                    self.status("waiting-window")
                    self.scheduleRetry()
                    return
                }
                guard let entry else {
                    self.status("empty")
                    // Publication can finish just after the scene becomes
                    // active. Retry briefly; never poll disk indefinitely.
                    self.scheduleRetry()
                    return
                }
                self.presenting = true
                if self.present(entry) {
                    self.status("presenting")
                } else {
                    self.presenting = false
                    self.status("waiting-window")
                    self.scheduleRetry()
                }
            }
        }
    }

    deinit { self.retry?.cancel() }
}
