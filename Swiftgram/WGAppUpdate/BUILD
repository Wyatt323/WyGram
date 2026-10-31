load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "WGAppUpdate",
    module_name = "WGAppUpdate",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    deps = ["//Swiftgram/WGUpdateSigner:WGUpdateSigner", "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit"],
    visibility = ["//visibility:public"],
)
