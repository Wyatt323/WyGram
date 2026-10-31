load(":headers.bzl", "openssl_headers")

filegroup(
    name = "Licenses",
    srcs = ["Resources/WGUpdateOpenSSL-LICENSE.txt"],
    visibility = ["//visibility:public"],
)

# The update signer must not export the BN/EVP/ASN1 symbols used by Telegram's
# BoringSSL. Compile a separate OpenSSL with every defined C symbol prefixed.
genrule(
    name = "build_private_crypto",
    srcs = [
        "symbols.txt",
        "//submodules/openssl:openssl-1.1.1d.tar.gz",
        "//submodules/openssl:build-openssl-bazel.sh",
        "//submodules/openssl:patch-conf.patch",
        "//submodules/openssl:patch-include.patch",
    ],
    tools = ["build_private_crypto.py", "namespace_archive.py"],
    outs = ["libWGUpdateCrypto.a", "Public/WGUpdateOpenSSL/Symbols.h"] + ["Public/WGUpdateOpenSSL/openssl/" + x for x in openssl_headers],
    cmd = "python3 $(location build_private_crypto.py) " +
        "--symbols $(location symbols.txt) " +
        "--archive $(location //submodules/openssl:openssl-1.1.1d.tar.gz) " +
        "--builder $(location //submodules/openssl:build-openssl-bazel.sh) " +
        "--configuration-patch $(location //submodules/openssl:patch-conf.patch) " +
        "--header-patch $(location //submodules/openssl:patch-include.patch) " +
        "--cpu $(TARGET_CPU) --output $(RULEDIR)",
)

cc_library(
    name = "private_crypto_archive",
    srcs = [":libWGUpdateCrypto.a"],
)

objc_library(
    name = "WGUpdateOpenSSL",
    module_name = "WGUpdateOpenSSL",
    enable_modules = True,
    hdrs = ["Public/WGUpdateOpenSSL/Symbols.h"] + ["Public/WGUpdateOpenSSL/openssl/" + x for x in openssl_headers],
    includes = ["Public"],
    deps = [":private_crypto_archive"],
    visibility = ["//visibility:public"],
)
