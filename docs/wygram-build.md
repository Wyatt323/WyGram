# Build WyGram

This repository contains the complete WyGram source snapshot based on
`Swiftgram/Telegram-iOS@cf8b23beaaac4126a396337ac2d5be13f9f76b66`.
Submodules remain pinned to the public revisions in the Git tree. The historical
`WyGram-1.0.0.patch` and `build-ipa.yml` workflow describe the initial version;
use this recipe for the current source.

## Local unsigned build

The 1.1.1 (23) package uses Apple Silicon, Xcode 27.2 (27B52), iOS 27.2 SDK,
Metal Toolchain 27B47 and Bazel 8.4.2. Minimum supported iOS is 15.0.

```sh
git clone --recursive https://github.com/Wyatt323/WyGram.git
cd WyGram
python3 scripts/wygram_setup.py
cp build-system/template_minimal_development_configuration.json build-system/wygram.local.json
chmod 600 build-system/wygram.local.json
```

Edit the ignored configuration with your own Telegram `api_id` and `api_hash`,
Bundle ID, Team ID and application settings. For the existing WyGram installation
keep `app.wygram.ios` and the original signing identity. The example configuration
contains placeholders only. Do not commit real API credentials or signing files.

```sh
python3 build-system/Make/Make.py \
  --bazelUserRoot="$PWD/../wygram-bazel" --overrideXcodeVersion build \
  --configurationPath=build-system/wygram.local.json \
  --xcodeManagedCodesigning --unsigned \
  --configuration=release_arm64 --buildNumber=23
```

The result is `bazel-bin/Telegram/WyGram.ipa`. Run the setup script after updating
submodules or selecting another Xcode. It applies the checked-in unsigned-build
patch idempotently and generates an ignored selected-Xcode configuration.
On Intel Macs, update the Bazel binary checksum for that architecture before
building; the pinned checksum in `versions.json` is for Apple Silicon.

## Release

Synchronize `versions.json`, the main app and all extensions; increment the
user-visible patch version and the independent build number. Commit and push the
source, then pass its full commit SHA to release preparation:

```sh
python3 scripts/wygram_release.py prepare \
  --ipa /absolute/path/to/unsigned.ipa \
  --output /absolute/path/to/new-release-directory \
  --notes /absolute/path/to/release-notes.md \
  --source-commit FULL_COMMIT_SHA
python3 scripts/wygram_release.py publish /absolute/path/to/new-release-directory
```

Published IPAs are ad-hoc reference packages for later personal signing, with no
embedded profiles or signing keys. Local filenames are `WyGram <version>.ipa`.
GitHub replaces spaces with periods in stored asset names; the display label
retains the requested name. Tags are `v<version>-b<build>` and point to the exact
published source commit. Never overwrite previous IPAs or release tags.

See [online updates](wygram-online-updates.md) for first-install requirements,
on-device signing and installation verification boundaries.
