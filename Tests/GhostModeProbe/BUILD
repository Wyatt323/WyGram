load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_library")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("//Tests/SettingsLayoutProbe:only_binary.bzl", "only_binary")

genrule(
    name = "ProductionPolicies",
    srcs = ["//submodules/TelegramCore:WyGramGhostProbeSources", "//Swiftgram/SGSettingsUI:WyGramGhostSettingsSource"],
    tools = ["extract.py"],
    outs = ["ProductionPolicies.swift"],
    cmd = "python3 $(location extract.py) $@ $(locations //submodules/TelegramCore:WyGramGhostProbeSources) $(locations //Swiftgram/SGSettingsUI:WyGramGhostSettingsSource)",
)

swift_library(
    name = "ProbeCode",
    module_name = "GhostModeProbe",
    srcs = ["Probe.swift", ":ProductionPolicies"],
    copts = ["-warnings-as-errors"],
    deps = [
        "//submodules/TelegramCore", "//submodules/Postbox", "//submodules/TelegramApi", "//submodules/MtProtoKit",
        "//submodules/SSignalKit/SwiftSignalKit", "//Swiftgram/SGSimpleSettings",
        "//Swiftgram/SGSettingsUI", "//submodules/Display", "//submodules/TelegramPresentationData",
    ],
)

ios_application(
    name = "AppDefinition",
    bundle_id = "app.wygram.ghostmodeprobe",
    families = ["iphone"], minimum_os_version = "15.0", infoplists = ["Info.plist"],
    resources = ["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"],
    deps = [":ProbeCode"],
)
only_binary(name = "GhostModeProbeBinary", app = ":AppDefinition")

apple_static_library(
    name = "ProductionCompileCheck",
    platform_type = "ios", minimum_os_version = "15.0",
    deps = ["//Swiftgram/SGSettingsUI", "//submodules/TelegramUI/Components/Stories/StoryContainerScreen"],
)
