load("@build_bazel_rules_apple//apple:providers.bzl", "AppleExecutableBinaryInfo")
def _impl(ctx):
    return [DefaultInfo(files = depset([ctx.attr.app[AppleExecutableBinaryInfo].binary]))]
only_binary = rule(implementation = _impl, attrs = {"app": attr.label(mandatory = True, providers = [AppleExecutableBinaryInfo])})
