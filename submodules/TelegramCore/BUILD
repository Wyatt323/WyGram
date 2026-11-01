load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

sgdeps = [
    "//Swiftgram/SGAppGroupIdentifier:SGAppGroupIdentifier",
    "//Swiftgram/SGGTranslate:SGGTranslate",
    "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
    "//Swiftgram/SGTranslationLangFix:SGTranslationLangFix",
    "//Swiftgram/SGWebSettingsScheme:SGWebSettingsScheme",
    "//Swiftgram/SGGHSettingsScheme:SGGHSettingsScheme",
    "//Swiftgram/SGConfig:SGConfig",
    "//Swiftgram/SGLogging:SGLogging",
]

sgsrc = [
    "//Swiftgram/SGIQTP:SGIQTP",
]

swift_library(
    name = "TelegramCore",
    module_name = "TelegramCore",
    srcs = sgsrc + glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = sgdeps + [
        "//submodules/TelegramApi:TelegramApi",
        "//submodules/MtProtoKit:MtProtoKit",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/CloudData:CloudData",
        "//submodules/EncryptionProvider:EncryptionProvider",
        "//submodules/CryptoUtils:CryptoUtils",
        "//submodules/NetworkLogging:NetworkLogging",
        "//submodules/Reachability:Reachability",
        "//submodules/ManagedFile:ManagedFile",
        "//submodules/Utils/RangeSet:RangeSet",
        "//submodules/Utils/DarwinDirStat",
        "//submodules/Emoji",
        "//submodules/TelegramCore/FlatBuffers",
        "//submodules/TelegramCore/FlatSerialization",
        "//submodules/MurMurHash32"
    ],
    visibility = [
        "//visibility:public",
    ],
)

filegroup(
    name = "WyGramGhostProbeSources",
    srcs = [
        "Sources/TelegramEngine/Privacy/WyGramGhostMode.swift",
        "Sources/State/SynchronizePeerReadState.swift",
        "Sources/State/ManagedLocalInputActivities.swift",
        "Sources/TelegramEngine/Messages/Stories.swift",
        "Sources/State/ManagedSynchronizeConsumeMessageContentsOperations.swift",
        "Sources/State/ManagedSynchronizeViewStoriesOperations.swift",
        "Sources/State/ManagedAccountPresence.swift",
        "Sources/ApiUtils/ApiUtils.swift",
        "Sources/SyncCore/SynchronizeViewStoriesOperation.swift",
    ],
    visibility = ["//visibility:public"],
)
