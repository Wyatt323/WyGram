import Foundation
import Darwin
import SwiftSignalKit

/// UI activity follows local readiness as well as the socket's network state.
/// All callbacks and entry points run on the main queue.
final class WyGramChatListLoading {
    enum Phase: Equatable {
        case idle
        case restoring
        case opening
    }

    private let phaseValue = ValuePromise<Phase>(.idle, ignoreRepeated: true)
    var phase: Signal<Phase, NoError> { self.phaseValue.get() }

    private let foregroundDisposable = MetaDisposable()
    private let readinessDisposable = MetaDisposable()
    private let openingReadinessDisposable = MetaDisposable()
    private let readLocalState: () -> Signal<Bool, NoError>
    private let clock: () -> TimeInterval
    private var inForeground: Bool?
    private var backgroundTime: TimeInterval?
    private var generation = 0
    private var restoring = false
    private var nextOpeningId = 0
    private var openingId: Int?

    init(foreground: Signal<Bool, NoError>, readLocalState: @escaping () -> Signal<Bool, NoError>, clock: @escaping () -> TimeInterval = WyGramChatListLoading.currentTime) {
        self.readLocalState = readLocalState
        self.clock = clock
        self.foregroundDisposable.set((foreground
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.updateForeground(value)
        }))
    }

    private static func currentTime() -> TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }

    private func updateForeground(_ value: Bool) {
        guard self.inForeground != value else { return }
        self.inForeground = value
        self.generation += 1
        let generation = self.generation
        self.readinessDisposable.set(nil)
        if !value {
            self.backgroundTime = self.clock()
            self.restoring = false
            self.openingId = nil
            self.openingReadinessDisposable.set(nil)
            self.updatePhase()
            return
        }
        let backgroundTime = self.backgroundTime
        self.backgroundTime = nil
        guard let backgroundTime, self.clock() - backgroundTime >= 30.0 else { return }
        self.restoring = true
        self.updatePhase()
        // A local Postbox round trip acknowledges that transactions can run
        // again. A cached network .online value cannot establish this.
        self.readinessDisposable.set((self.readLocalState()
        |> filter { $0 }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let self, self.inForeground == true, self.generation == generation else { return }
            self.restoring = false
            self.updatePhase()
        }))
    }

    /// Ignore repeated taps until this navigation completes or is abandoned.
    func beginOpening() -> Int? {
        guard self.inForeground != false, self.openingId == nil else { return nil }
        self.nextOpeningId += 1
        self.openingId = self.nextOpeningId
        self.updatePhase()
        return self.nextOpeningId
    }

    func isCurrentOpening(_ id: Int) -> Bool {
        return self.openingId == id && self.inForeground != false
    }

    func finishOpening(_ id: Int) {
        guard self.openingId == id else { return }
        self.cancelOpening()
    }

    func waitForOpenedChat(_ id: Int, ready: Signal<Bool, NoError>) {
        guard self.isCurrentOpening(id) else { return }
        // Navigation completion may only acknowledge a stack change while the
        // destination is still waiting for its first local history view.
        self.openingReadinessDisposable.set((ready
        |> filter { $0 }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.finishOpening(id)
        }))
    }

    func cancelOpening() {
        self.openingId = nil
        self.openingReadinessDisposable.set(nil)
        self.updatePhase()
    }

    private func updatePhase() {
        self.phaseValue.set(self.openingId != nil ? .opening : (self.restoring ? .restoring : .idle))
    }

    deinit {
        self.foregroundDisposable.dispose()
        self.readinessDisposable.dispose()
        self.openingReadinessDisposable.dispose()
    }
}
