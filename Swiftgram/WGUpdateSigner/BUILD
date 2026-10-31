
filegroup(
    name = "Licenses",
    srcs = ["Resources/WGUpdateSigner-zsign-LICENSE.txt", "//Swiftgram/WGUpdateOpenSSL:Licenses"],
    visibility = ["//visibility:public"],
)

objc_library(
    name = "WGUpdateSigner",
    module_name = "WGUpdateSigner",
    enable_modules = True,
    srcs = glob(["Sources/*.mm", "Vendor/zsign/*.cpp", "Vendor/zsign/common/*.cpp", "Vendor/zsign/**/*.h"]),
    hdrs = ["Public/WGUpdateSigner.h"],
    includes = ["Public", "Vendor/zsign", "Vendor/zsign/common"],
    copts = ["-std=c++17", "-Wno-deprecated-declarations"],
    sdk_frameworks = ["Foundation", "Security"],
    deps = ["//Swiftgram/WGUpdateOpenSSL:WGUpdateOpenSSL", "//third-party/ZipArchive:ZipArchive"],
    visibility = ["//visibility:public"],
)

objc_library(
    name = "CryptoCoexistenceChecks",
    visibility = ["//Tests/OnlineUpdateProbe:__pkg__"],
    srcs = ["Tests/CryptoCoexistenceChecks.mm"],
    copts = ["-std=c++17"],
    deps = [":WGUpdateSigner", "//submodules/OpenSSLEncryptionProvider:OpenSSLEncryptionProvider"],
    sdk_frameworks = ["Foundation"],
    testonly = True,
)

cc_test(
    name = "CryptoCoexistenceTests",
    srcs = ["Tests/CryptoCoexistenceMain.cpp"],
    deps = [":CryptoCoexistenceChecks"],
)
