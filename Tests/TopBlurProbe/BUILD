load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ProbeCode",
    srcs = ["Probe.swift"],
    module_name = "TopBlurProbe",
    deps = [
        "//submodules/Display",
        "//Swiftgram/SGSimpleSettings",
        "//submodules/MetalEngine",
        "//submodules/TelegramUI/Components/NavigationBarImpl",
    ],
)

ios_application(
    name = "TopBlurProbe",
    bundle_id = "app.wygram.topblurprobe",
    families = ["iphone"],
    minimum_os_version = "15.0",
    infoplists = ["Info.plist"],
    resources = ["//submodules/TelegramUI:TelegramUIAssets", "//Swiftgram/SGSettingsUI:SGUIAssets"],
    deps = [":ProbeCode"],
)
