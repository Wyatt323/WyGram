# Share receiver lifecycle probe

Run on an Apple Silicon Mac with Xcode and the two simulators configured in `run.py`:

```sh
python3 Tests/ShareInboxReceiverProbe/run.py --output /tmp/wygram-share-receiver-check --baseline-presenter /path/to/1.1.0/WyGramShareInboxPresenter.swift
```

The script extracts and compiles the production old/new receiver readiness and lifecycle sections, with real SwiftSignalKit signals, the production inbox/coordinator, fabricated files and a real UIKit window. Account shells and the final native ShareController are replaced by signal providers and a presentation recorder. Discovery is injected to avoid claiming fixture signatures grant actual App Group access.

It reproduces the old ready-before-window loss, then checks delayed root attachment, readiness/unlock/foreground, files published after the initial scan, window or lock/background changes during disk IO, logout, duplicate triggers, bounded retry/manual refresh and ordering across inboxes. It never sends files, opens a real Telegram account or migrates user data. These checks are not a physical-device/system-extension-host test or an authenticated recipient-picker test.

Run simulator UI probes sequentially so one host does not background another. No application IPA is generated and the release version is unchanged.
