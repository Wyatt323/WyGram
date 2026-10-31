import Foundation
import SGAppGroupIdentifier
import SwiftSignalKit
import Postbox
import TelegramApi


public enum NotificationTokenType {
    case aps(encrypt: Bool)
    case voip
}

func _internal_unregisterNotificationToken(account: Account, token: Data, type: NotificationTokenType, otherAccountUserIds: [PeerId.Id]) -> Signal<Never, NoError> {
    let mappedType: Int32
    switch type {
        case .aps:
            mappedType = 1
        case .voip:
            mappedType = 9
    }
    return account.network.request(Api.functions.account.unregisterDevice(tokenType: mappedType, token: hexString(token), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
    |> retryRequest
    |> ignoreValues
}

func _internal_registerNotificationToken(account: Account, token: Data, type: NotificationTokenType, sandbox: Bool, otherAccountUserIds: [PeerId.Id], excludeMutedChats: Bool) -> Signal<Bool, NoError> {
    return masterNotificationsKey(account: account, ignoreDisabled: false)
    |> mapToSignal { masterKey -> Signal<Bool, NoError> in
        let mappedType: Int32
        var keyData = Data()
        switch type {
            case let .aps(encrypt):
                mappedType = 1
                if encrypt {
                    keyData = masterKey.data
                }
            case .voip:
                mappedType = 9
                keyData = masterKey.data
        }
        if case .aps = type {
            WyGramPushStatus.record("server.\(account.id.int64)", value: "registering")
            if UserDefaults.standard.string(forKey: "wygram.applicationDataStorage") == "local", let directory = WyGramPushDirectory.current() {
                do {
                    try WyGramPushBridge.write(WyGramPushBridgeAccount(recordId: account.id.int64, keyId: masterKey.id, key: masterKey.data), directory: directory.url)
                    WyGramPushStatus.record("bridge", value: "ready")
                } catch {
                    WyGramPushStatus.record("bridge", value: "write_failed")
                }
            } else if UserDefaults.standard.string(forKey: "wygram.applicationDataStorage") == "local" {
                WyGramPushStatus.record("bridge", value: "unavailable")
            }
        }
        var flags: Int32 = 0
        if excludeMutedChats {
            flags |= 1 << 0
        }
        return account.network.request(Api.functions.account.registerDevice(flags: flags, tokenType: mappedType, token: hexString(token), appSandbox: sandbox ? .boolTrue : .boolFalse, secret: Buffer(data: keyData), otherUids: otherAccountUserIds.map({ $0._internalGetInt64Value() })))
        |> map { success -> Bool in
            if case .aps = type {
                let accepted: Bool
                switch success { case .boolTrue: accepted = true; case .boolFalse: accepted = false }
                WyGramPushStatus.record("server.\(account.id.int64)", value: accepted ? "accepted" : "rejected")
            }
            return true
        }
        |> `catch` { error -> Signal<Bool, NoError> in
            if case .aps = type {
                WyGramPushStatus.record("server.\(account.id.int64)", value: WyGramPushStatus.safeError(error.errorDescription))
            }
            if error.errorDescription == "TOKEN_WAS_INVALIDATED" {
                return .single(false)
            } else {
                return .single(true)
            }
        }
    }
}
