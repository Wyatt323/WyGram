load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("//Tests/SettingsLayoutProbe:only_binary.bzl", "only_binary")

swift_library(
    name = "ProbeCode",
    module_name = "RepeatMessageProbe",
    srcs = ["Probe.swift", "//submodules/TelegramUI:WyGramRepeatMessageSources"],
    deps = [
        "//submodules/Postbox", "//submodules/TelegramCore", "//submodules/ContextUI",
        "//submodules/Display", "//submodules/TelegramPresentationData",
    ],
)
ios_application(
    name = "AppDefinition",
    bundle_id = "app.wygram.repeatmessageprobe",
    families = ["iphone"], minimum_os_version = "15.0", infoplists = ["Info.plist"],
    resources = ["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"],
    deps = [":ProbeCode"],
)
only_binary(name = "RepeatMessageProbeBinary", app = ":AppDefinition")
