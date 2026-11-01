load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_library")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("//Tests/SettingsLayoutProbe:only_binary.bzl", "only_binary")

genrule(
    name = "ProductionTitle",
    srcs = ["//submodules/ChatListUI:WyGramLoadingProbeSources"],
    tools = ["extract_title.py"],
    outs = ["ProductionTitle.swift"],
    cmd = "python3 $(location extract_title.py) $@ $(locations //submodules/ChatListUI:WyGramLoadingProbeSources)",
)

swift_library(
    name = "ProbeCode",
    module_name = "ChatListLoadingProbe",
    srcs = ["Probe.swift", ":ProductionTitle", "//submodules/ChatListUI:WyGramLoadingStateSource"],
    copts = ["-warnings-as-errors"],
    deps = [
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramUI/Components/ChatListTitleView",
    ],
)

ios_application(
    name = "AppDefinition",
    bundle_id = "app.wygram.chatlistloadingprobe",
    families = ["iphone"],
    minimum_os_version = "15.0",
    infoplists = ["Info.plist"],
    resources = ["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"],
    deps = [":ProbeCode"],
)

only_binary(name = "ChatListLoadingProbeBinary", app = ":AppDefinition")

apple_static_library(
    name = "ChatListCompileCheck",
    platform_type = "ios",
    minimum_os_version = "15.0",
    deps = ["//submodules/ChatListUI"],
)
