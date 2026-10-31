load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
swift_library(
    name = "ProbeCode", module_name = "PushCompatibilityProbe",
    srcs = ["Probe.swift", "//Telegram/NotificationService:Sources/WyGramPushBridgeNotification.swift"],
    deps = ["//Swiftgram/SGAppGroupIdentifier", "//Swiftgram/SGSettingsUI", "//submodules/TelegramCore", "//submodules/MtProtoKit", "//submodules/Display", "//submodules/TelegramPresentationData", "//submodules/TelegramUI/Components/NavigationBarImpl", "//submodules/LegacyUI"],
)
ios_application(
    name = "PushCompatibilityProbe", bundle_id = "app.wygram.pushcompatibilityprobe",
    families = ["iphone"], minimum_os_version = "15.0", infoplists = ["Info.plist"],
    resources = ["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"],
    deps = [":ProbeCode"],
)
