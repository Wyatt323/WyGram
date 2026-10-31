# WyGram 1.0.12

This fork starts from `Swiftgram/Telegram-iOS` commit `cf8b23beaaac4126a396337ac2d5be13f9f76b66`.

## Changes

- Build 19 adds GitHub Release checks, verified background downloads, on-device certificate import/signing and a system installation flow. The first version requires manual LCSign signing and installation; physical-device OTA validation remains pending. See [online updates](docs/wygram-online-updates.md).


- Build 18 closes the chat input through a one-shot presentation callback after a message or avatar preview is captured, so a scene-managed system keyboard cannot cover the context menu. Message, participant-avatar and header-avatar menus preserve the draft and allow typing again after dismissal. Production component checks reproduce the original overlap and verify the fix on 15 Pro and 18 Pro Max simulators; LCSign device verification remains pending.

- Build 17 imports chat file-picker selections only after the native picker dismisses, and accepts readable local copies without requiring a security scope. System sharing shows progress or actionable errors; when shared account storage is unavailable, selected files can be handed off for normal in-app recipient confirmation through a system-accessible common App Group. No account data is moved. The Message History and Notification Status pages use grouped layouts, clearer text hierarchy, application theme colors and corrected navigation/keyboard boundaries. Component checks use simulator fixtures; authenticated sharing and LCSign device verification remain pending.

- Build 13 handles keyboard-dismiss gestures without moving the composer independently of an unavailable system keyboard surface. Long-press message menus use the fixed WyGram logo with transparent rounded corners.

- Build 12 keeps complete incoming timed/view-once photos, including timed secret-chat photos, in an account-local archive outside the media cache. Saved chat photos use local resources and survive expiration, remote refresh/deletion and normal cache cleanup. The default-on switch is in Message History. Disabling it keeps existing records; deleting a retained-photo record also removes its local chat bubble. Incomplete/expired media cannot be restored; videos and voice are not included.

- Build 11 follows converted system keyboard target frames and the public keyboard layout guide, including input-method changes, glass keyboard gaps and foreground layout refreshes. The two WyGram settings icons use transparent rounded corners.
- Build 11 monitors connections for a bounded period after a long suspension. A persistently stalled transport is rebuilt once, preserving authentication, pending requests, local history and VPN/proxy settings. The phone-specific VPN stall still requires device verification.
- Build 10 removes the reference artwork's outer white canvas and rim from the desktop icon and internal logo assets. The central symbol stays unchanged.
- Display name, settings labels, watch labels, and localized references use WyGram.
- Build 16 opens retained disappearing photos directly from their message, avoiding the shared-media index that excludes their original timed-photo entry. Existing saved photos work without re-saving or reindexing.
- Build 15 corrects the Unknown iPhone fallback for the physical iPhone 18 Pro Max identifier `iPhone19,7` found in user-supplied crash logs. Simulator profile identifiers remain supported. Future unlisted iPhones show their hardware identifier instead of Unknown iPhone. Build 14 restored automatic hardware-model reporting for Telegram Devices. The first line is the device model, and the second is the registered app name plus the current version. Existing sessions update after the new client connects; no logout or account-data migration is required. Telegram controls the separate app name via the application's registered `api_id`.
- Swiftgram's local Pro settings and badges are available to all users. The paywall routes to the features page. StoreKit product requests and the startup subscription check are removed.
- Requests to Swiftgram's settings service now have timeouts so a resumed app cannot wait indefinitely on those requests.
- Build 9 uses the supplied WyGram icon and capsule badge, removes icon/badge selectors and alternate icons, and replaces internal Swiftgram branding. Badge visibility follows display metrics so iPhone 18 Pro Max and future supported screen layouts are included.
- Build 8 adapts push registration to the signed APNs environment and uses a system-accessible shared group for generic encrypted notification alerts when account data is app-local. Settings include registration status, retry, a local notification test, and a redacted status report. Existing account and message-history databases stay in place; actual remote delivery requires signed-device verification. Build 9 adds a direct status entry on the settings home screen. The supplied LCSign build 8 has a mismatched application identity; matching signing/provisioning and Telegram APNs service configuration remain unresolved external requirements.

Telegram Premium, Stars, paid messages, and anything enforced by Telegram or Swiftgram servers are unchanged. The current background report is a chat-list connection/update spinner while using a phone VPN; local policy checks and simulator lifecycle tests do not establish successful Telegram connectivity on that device.

## Build requirements

The local 1.0.12 device package uses macOS, Xcode 27.2, Bazel 8.4.2, and a minimum iOS version of 15.0. Its icon is an opaque, full-bleed blue square; iOS supplies the corner mask. The upstream toolchain requirements are in `versions.json`; the local recipe explicitly overrides the Xcode version check. Before building, create an application at [my.telegram.org](https://my.telegram.org/apps) named WyGram and enter its `api_id` and `api_hash` into a private copy of `build-system/template_minimal_development_configuration.json`. Replace the placeholder bundle identifier and Team ID with your own values. Do not commit secrets or signing files.

An installable IPA requires a device signing certificate and provisioning profile. The upstream README documents project generation and the `build` command. Test the resulting build by signing in, opening local features, moving the app to the background, and returning after both short and long delays on Wi-Fi and cellular data.
