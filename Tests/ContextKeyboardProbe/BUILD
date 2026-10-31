load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_library")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("//Tests/SettingsLayoutProbe:only_binary.bzl", "only_binary")

swift_library(
    name = "ProbeCode",
    module_name = "ContextKeyboardProbe",
    srcs = ["Probe.swift"],
    deps = [
        "//submodules/AsyncDisplayKit",
        "//submodules/ContextUI",
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramPresentationData",
        "//submodules/TelegramUI/Components/Chat/ChatInputTextNode",
        "//submodules/TelegramUI/Components/ContextControllerImpl",
    ],
)
ios_application(
    name = "AppDefinition",
    bundle_id = "app.wygram.contextkeyboardprobe",
    families = ["iphone"],
    minimum_os_version = "15.0",
    infoplists = ["Info.plist"],
    resources = ["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"],
    deps = [":ProbeCode"],
)
only_binary(name = "ContextKeyboardProbeBinary", app = ":AppDefinition")

apple_static_library(
    name = "ChatCompileCheck",
    platform_type = "ios",
    minimum_os_version = "15.0",
    deps = ["//submodules/TelegramUI:TelegramUI"],
)
