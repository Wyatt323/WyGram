# WyGram contributor notes

- Current version: 1.1.1 (build 23). Increment patch version and independent build number for each new release. Synchronize main app and all extensions.
- IPA filenames: `WyGram <version>.ipa`; GitHub normalizes spaces to periods in stored names. Preserve old releases. See `docs/wygram-build.md`.
- Keep `app.wygram.ios` and existing application data/signing identity for in-place upgrades.
- Never commit private API configuration, signing keys, provisioning profiles, account databases, build logs or generated outputs.
- Keep the fixed WyGram icon, internal rounded logo and capsule badge; do not restore icon/badge selectors.
- Retained photos use account-relative paths and supported LocalImage/LocalFileMediaResource types. Keep full `.dataPart` fetch handling and the retained-photo single-message gallery path.
- The existing `APP_PUSH_CERT_MISSING` notification failure requires Telegram server-side APNs configuration; client packaging does not resolve it.
- Distinguish simulator/fixture checks from real-account or physical-device verification. Do not claim LCSign OTA or push delivery has been tested without evidence.

- Repeat Message acts on exactly the pressed message in the current writable chat/topic, preserves captions and drafts, and uses the normal hidden-attribution forwarding/send path. Respect protection, permissions, slow mode and paid-message confirmation. Do not restore the removed branded context submenu or remove the top badge.

- Forward to This Chat is a separate adjacent action that keeps normal forward attribution (`hideNames: false`) and preserves captions. Repeat must continue hiding attribution. Share permission, paid-message, slow-mode and selected-message checks.

- System share fallback completion closes the extension and preserves its published attachments for manual opening of WyGram; explicit Cancel Share removes them. Do not require a Share extension to open its containing app. Select an inbox prepared by the main app rather than blindly choosing the first container, and preserve account storage. A storage marker and simulator probes do not prove a signed device has common App Group permissions. See `docs/wygram-system-share.md` and `Tests/ShareInboxHandoffProbe`.

- Version 1.1.0 adds an explicit user-enabled direct-share setup. Before any account/key/logger opens on the next cold start, an exclusively renamed complete store may move to an authorised common App Group. Never enable automatically, copy session keys, merge/overwrite an existing destination, or silently create an empty account after an interrupted move. Keep the recovery journal and exact-directory identity checks.

- Share inbox presentation continuously observes ready/unlocked/active state and waits for an attached root window. Keep bounded retries, cross-container oldest-first handling, explicit manual refresh and account-change cancellation. Never consume a pending batch merely because readiness or window attachment is delayed.
- Direct-share setup chooses a vacant authorised common group, including a safe alternative for an old occupied request. Do not overwrite even empty existing stores. Native sharing requires the main app's positive shared-storage marker. Main and extension inbox discovery use the same actual signing-group intersection.
