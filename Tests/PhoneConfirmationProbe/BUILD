load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application")
load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
swift_library(name="ProbeCode", module_name="PhoneConfirmationProbe", srcs=glob(["*.swift"]), deps=["//submodules/Display", "//submodules/AsyncDisplayKit", "//submodules/TelegramPresentationData", "//submodules/SolidRoundedButtonNode", "//submodules/PresentationDataUtils", "//submodules/SSignalKit/SwiftSignalKit"])
ios_application(name="PhoneConfirmationProbe", bundle_id="app.wygram.phoneconfirmationprobe", families=["iphone","ipad"], minimum_os_version="15.0", infoplists=["Info.plist"], resources=["//Telegram:AppStringResources", "//Telegram:GeneratedPresentationStrings/Resources/PresentationStrings.data"], deps=[":ProbeCode"])
