# Share inbox handoff regression probe

Run on an Apple Silicon Mac with Xcode 27.2 and the local iPhone 15 Pro and
iPhone 18 Pro Max simulators configured in `run.py`:

```sh
python3 Tests/ShareInboxHandoffProbe/run.py --output /tmp/wygram-share-handoff-check
```

This compiles the production inbox and fallback controller without replacing
their implementation. It uses real UIKit controls and `NSItemProvider`
callbacks with fabricated certificate/profile files, and checks the completed
batch through a separate receiver instance. It covers completion preserving
attachments across controller destruction, explicit cancellation, repeated and
late callbacks, directory selection using the main app's storage marker,
corrupt/unprepared directories, provider failures, file limits and cleanup.

It does not launch a Files-hosted production extension, obtain cross-process
App Group permissions, log in to Telegram, send messages, or verify a signed
physical-device installation. The output includes result JSON and component
screenshots; it does not generate an IPA or change the app version.
