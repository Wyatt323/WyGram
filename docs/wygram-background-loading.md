# Chat-list loading feedback

Version 1.1.4 (26) shows the existing localized loading title and activity indicator while local chat data resumes after at least 30 seconds in the background. A Postbox transaction acknowledges local readiness; a cached network-online value alone cannot do that. This read-only check does not move accounts or change message history.

Selecting a chat shows activity through local peer-data lookup and the destination controller's `ready` signal. Navigation-stack completion may arrive before content readiness and must not hide the indicator alone. Repeated pending selections are ignored; backgrounding or leaving the list invalidates old local-query callbacks. Real offline, connecting and syncing states keep priority over the local-loading label. No full-screen blocking overlay or artificial loading delay is added.

`Tests/ChatListLoadingProbe` compiles the production coordinator and extracts the real header switch. Its 60 checks on iPhone 15 Pro and iPhone 18 Pro Max simulators use real SwiftSignalKit, injected local-readiness signals and a deterministic monotonic clock, including a simulated one-minute wait. They do not establish actual suspension behavior, authenticated complete chat navigation or improved network latency on a signed phone.

Existing transport recovery, background-execution limits, APNs configuration, sharing, fixed branding, Repeat/Forward actions and retained photos remain unchanged. This feature adds feedback during waits; it does not claim the reported 10–60 second recovery is eliminated.
