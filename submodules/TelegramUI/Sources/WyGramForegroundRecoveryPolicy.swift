import Foundation
import Darwin

/// A bounded recovery window after suspension; time is monotonic across sleep.
struct WyGramForegroundRecoveryPolicy {
    static func currentTime() -> TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        // Unlike uptime clocks, this includes time spent asleep while locked.
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }

    enum Status: Equatable {
        case unavailable
        case connecting
        case updating
        case online
    }

    private var backgroundTime: TimeInterval?
    private var deadline: TimeInterval?
    private var stalledSince: TimeInterval?
    private(set) var status: Status = .unavailable
    private(set) var didRecover = false

    mutating func enterBackground(at now: TimeInterval) {
        if self.backgroundTime == nil { self.backgroundTime = now }
        self.deadline = nil
        self.stalledSince = nil
    }

    mutating func activate(at now: TimeInterval) -> Bool {
        guard let backgroundTime = self.backgroundTime else { return false }
        self.backgroundTime = nil
        guard now - backgroundTime >= 30.0 else { return false }
        self.deadline = now + 90.0
        self.stalledSince = nil
        self.status = .unavailable
        self.didRecover = false
        return true
    }

    mutating func update(_ status: Status, at now: TimeInterval) {
        switch status {
        case .online, .unavailable:
            self.stalledSince = nil
        case .connecting, .updating:
            if self.stalledSince == nil || self.status != status {
                self.stalledSince = now
            }
        }
        self.status = status
    }

    mutating func shouldReconnect(at now: TimeInterval) -> Bool {
        guard let deadline = self.deadline, now <= deadline,
              !self.didRecover, let stalledSince = self.stalledSince else { return false }
        let delay: TimeInterval = self.status == .updating ? 45.0 : 8.0
        guard now - stalledSince >= delay else { return false }
        self.didRecover = true
        return true
    }

    func isMonitoring(at now: TimeInterval) -> Bool {
        return self.deadline.map { now <= $0 } == true && !self.didRecover
    }
}
