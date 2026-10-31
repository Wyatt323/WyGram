load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_library")
apple_static_library(
    name = "CompileCheck",
    platform_type = "ios",
    minimum_os_version = "15.0",
    deps = ["//Swiftgram/SGSettingsUI", "//submodules/TelegramUI"],
)

load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load(":only_binary.bzl", "only_binary")
swift_library(
    testonly = True,
    name = "ProbeCode", module_name = "OnlineUpdateProbe", srcs = ["Probe.swift"],
    deps = ["//Swiftgram/WGUpdateSigner:CryptoCoexistenceChecks", "//Swiftgram/WGAppUpdate", "//Swiftgram/SGSettingsUI", "//submodules/Display", "//submodules/TelegramPresentationData", "//submodules/TelegramUI/Components/NavigationBarImpl", "//submodules/LegacyUI"],
)
ios_application(
    testonly = True,
    name = "AppDefinition", bundle_id = "app.wygram.onlineupdateprobe", families = ["iphone"], minimum_os_version = "15.0", infoplists = ["Info.plist"],
    resources = ["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"], deps = [":ProbeCode"],
)
only_binary(testonly = True, name = "OnlineUpdateProbeBinary", app = ":AppDefinition")
