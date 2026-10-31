load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ProbeCode",
    module_name = "ResumeKeyboardProbe",
    srcs = ["Probe.swift"],
    deps = ["//submodules/Display", "//submodules/AsyncDisplayKit", "//submodules/TelegramPresentationData", "//submodules/TelegramUI/Components/Chat/ChatInputTextNode"],
)
ios_application(
    name = "ResumeKeyboardProbe",
    bundle_id = "app.wygram.resumekeyboardprobe",
    families = ["iphone", "ipad"],
    minimum_os_version = "15.0",
    infoplists = ["Info.plist"],
    resources = ["//Swiftgram/SGSettingsUI:SGUIAssets"],
    deps = [":ProbeCode"],
)
