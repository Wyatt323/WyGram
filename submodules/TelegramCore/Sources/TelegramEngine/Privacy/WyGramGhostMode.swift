import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

/// Local to this account's Postbox, including extensions that open the same store.
/// These switches do not change the account's server-side privacy settings.
public struct WyGramGhostModeSettings: Codable, Equatable {
    public var hideStoryViews: Bool
    public var hideOnline: Bool
    public var hideInputActivity: Bool
    public var hideReadReceipts: Bool

    public init(hideStoryViews: Bool = false, hideOnline: Bool = false, hideInputActivity: Bool = false, hideReadReceipts: Bool = false) {
        self.hideStoryViews = hideStoryViews
        self.hideOnline = hideOnline
        self.hideInputActivity = hideInputActivity
        self.hideReadReceipts = hideReadReceipts
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.hideStoryViews = try values.decodeIfPresent(Bool.self, forKey: .hideStoryViews) ?? false
        self.hideOnline = try values.decodeIfPresent(Bool.self, forKey: .hideOnline) ?? false
        self.hideInputActivity = try values.decodeIfPresent(Bool.self, forKey: .hideInputActivity) ?? false
        self.hideReadReceipts = try values.decodeIfPresent(Bool.self, forKey: .hideReadReceipts) ?? false
    }
}

private let wygramGhostModeKey: ValueBoxKey = {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: 0x5759474d)
    return key
}()

private func wygramDecodeGhostMode(_ entry: PreferencesEntry?) -> WyGramGhostModeSettings {
    // Preserve the old local story-stealth choice on first use. Once saved,
    // each account owns its four switches and remote Swiftgram flags cannot reset them.
    return entry?.get(WyGramGhostModeSettings.self) ?? WyGramGhostModeSettings(hideStoryViews: SGSimpleSettings.shared.isStealthModeEnabled)
}

func wygramGhostModeSettings(transaction: Transaction) -> WyGramGhostModeSettings {
    return wygramDecodeGhostMode(transaction.getPreferencesEntry(key: wygramGhostModeKey))
}

public func wygramGhostModeSettings(postbox: Postbox) -> Signal<WyGramGhostModeSettings, NoError> {
    // Freeze the legacy default once per account before observing it. Otherwise a
    // remote change to the old Swiftgram flag could undo an inherited story choice
    // while the new page still displays its initial switch value.
    return postbox.transaction { transaction -> Void in
        if transaction.getPreferencesEntry(key: wygramGhostModeKey) == nil {
            let settings = wygramGhostModeSettings(transaction: transaction)
            transaction.updatePreferencesEntry(key: wygramGhostModeKey, { _ in PreferencesEntry(settings) })
        }
    }
    |> mapToSignal { _ in
        return postbox.preferencesView(keys: [wygramGhostModeKey])
        |> map { wygramDecodeGhostMode($0.values[wygramGhostModeKey]) }
        |> distinctUntilChanged
    }
}

/// Mutate in one transaction so rapid independent toggles cannot overwrite each other.
public func wygramUpdateGhostModeSettings(postbox: Postbox, _ update: @escaping (inout WyGramGhostModeSettings) -> Void) -> Signal<Void, NoError> {
    return postbox.transaction { transaction in
        var settings = wygramGhostModeSettings(transaction: transaction)
        update(&settings)
        transaction.updatePreferencesEntry(key: wygramGhostModeKey, { _ in PreferencesEntry(settings) })
    }
}

func wygramGhostOnlinePresence(_ presence: Signal<Bool, NoError>, settings: Signal<WyGramGhostModeSettings, NoError>) -> Signal<Bool, NoError> {
    return combineLatest(presence, settings)
    |> map { $0 && !$1.hideOnline }
    |> distinctUntilChanged
}

func wygramGhostInputActivityAllowed(_ activity: PeerInputActivity?, settings: WyGramGhostModeSettings) -> Bool {
    // Speaking-in-group-call is a call-liveness signal, not a composer indicator.
    if case .speakingInGroupCall? = activity { return true }
    return !settings.hideInputActivity || activity == nil
}

/// Discard the pending local synchronization without reverting the local read mark.
/// Do not leave a retrying operation that could leak a receipt after disabling the mode.
func wygramSuppressReadSynchronization(transaction: Transaction, peerId: PeerId) -> Bool {
    guard wygramGhostModeSettings(transaction: transaction).hideReadReceipts else { return false }
    transaction.confirmSynchronizedIncomingReadState(peerId)
    return true
}
