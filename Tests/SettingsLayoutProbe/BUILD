load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load(":only_binary.bzl", "only_binary")
swift_library(
    name = "ProbeCode", module_name = "SettingsLayoutProbe", srcs = ["Probe.swift"],
    deps = ["//Swiftgram/SGAppGroupIdentifier", "//Swiftgram/SGSettingsUI", "//submodules/TelegramCore", "//submodules/Postbox", "//submodules/SSignalKit/SwiftSignalKit", "//submodules/Display", "//submodules/TelegramPresentationData", "//submodules/TelegramUI/Components/NavigationBarImpl", "//submodules/LegacyUI"],
)
ios_application(
    name = "AppDefinition", bundle_id = "app.wygram.settingslayoutprobe", families = ["iphone"], minimum_os_version = "15.0", infoplists = ["Info.plist"],
    resources = ["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"], deps = [":ProbeCode"],
)
# Build this target only: request the linked simulator executable, without any
# application archive, signing, packaging or IPA output action.
only_binary(name = "SettingsLayoutProbeBinary", app = ":AppDefinition")
