# WyGram contributor notes

- Current version: 1.0.12 (build 19). Increment patch version and independent build number for each new release. Synchronize main app and all extensions.
- IPA filenames: `WyGram <version>.ipa`; GitHub normalizes spaces to periods in stored names. Preserve old releases. See `docs/wygram-build.md`.
- Keep `app.wygram.ios` and existing application data/signing identity for in-place upgrades.
- Never commit private API configuration, signing keys, provisioning profiles, account databases, build logs or generated outputs.
- Keep the fixed WyGram icon, internal rounded logo and capsule badge; do not restore icon/badge selectors.
- Retained photos use account-relative paths and supported LocalImage/LocalFileMediaResource types. Keep full `.dataPart` fetch handling and the retained-photo single-message gallery path.
- The existing `APP_PUSH_CERT_MISSING` notification failure requires Telegram server-side APNs configuration; client packaging does not resolve it.
- Distinguish simulator/fixture checks from real-account or physical-device verification. Do not claim LCSign OTA or push delivery has been tested without evidence.
