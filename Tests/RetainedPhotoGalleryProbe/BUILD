load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
swift_library(
    name = "ProbeCode",
    module_name = "RetainedPhotoGalleryProbe",
    srcs = ["Probe.swift", "GallerySelection.swift"],
    deps = [
        "//submodules/TelegramCore", "//submodules/Postbox", "//submodules/SSignalKit/SwiftSignalKit",
        "//Swiftgram/SGSettingsUI", "//submodules/Display", "//submodules/TelegramPresentationData",
        "//submodules/TelegramUI/Components/NavigationBarImpl",
        "//submodules/LegacyUI", "//submodules/PhotoResources",
    ],
)
ios_application(
    name = "RetainedPhotoGalleryProbe",
    bundle_id = "app.wygram.retainedphotogalleryprobe",
    families = ["iphone"], minimum_os_version = "15.0", infoplists = ["Info.plist"],
    resources = ["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"],
    deps = [":ProbeCode"],
)
