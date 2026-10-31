#!/usr/bin/env python3
"""Prepare selected Xcode and the pinned unsigned-build rule patch. No credentials."""
from pathlib import Path
import json, re, subprocess

ROOT = Path(__file__).resolve().parents[1]
def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()

def main():
    patch = ROOT/'build-system/patches/rules-apple-unsigned.patch'
    rules = ROOT/'build-system/bazel-rules/rules_apple'
    if not (rules/'apple/internal/ios_rules.bzl').is_file():
        raise SystemExit('Initialize submodules first: git submodule update --init --recursive')
    applied = subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=rules,capture_output=True).returncode == 0
    if not applied:
        subprocess.run(['git','apply','--check',str(patch)],cwd=rules,check=True)
        subprocess.run(['git','apply',str(patch)],cwd=rules,check=True)
    developer = run('xcode-select','-p')
    version = run('xcodebuild','-version').splitlines()[0].split()[1]
    sdks = {p:run('xcrun','--sdk',sdk,'--show-sdk-version') for p,sdk in [('ios','iphoneos'),('macos','macosx'),('tvos','appletvos'),('watchos','watchos'),('visionos','xros')]}
    if not all(re.fullmatch(r'[0-9]+(?:\.[0-9]+)*',s) for s in [version,*sdks.values()]):
        raise SystemExit('Unexpected Xcode/SDK version')
    output = ROOT/'build-system/local-xcode';output.mkdir(exist_ok=True)
    text = 'package(default_visibility = ["//visibility:public"])\nxcode_version(\n    name = "selected_xcode",\n    version = '+json.dumps(version)+',\n'
    text += ''.join('    default_'+platform+'_sdk_version = '+json.dumps(sdk)+',\n' for platform,sdk in sdks.items())
    text += ')\nxcode_config(name = "host_xcodes", default = ":selected_xcode", versions = [":selected_xcode"])\n'
    (output/'BUILD.bazel').write_text(text)
    (ROOT/'build-system/wygram.local.bazelrc').write_text('build --xcode_version_config=//build-system/local-xcode:host_xcodes\nbuild --repo_env=DEVELOPER_DIR='+json.dumps(developer)+'\nbuild --action_env=DEVELOPER_DIR='+json.dumps(developer)+'\n')
    print('Prepared selected Xcode '+version+' and unsigned build rules. Private API configuration is still required.')

if __name__ == '__main__': main()
