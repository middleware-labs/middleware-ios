# Changelog

All notable changes to the Middleware iOS SDK (`MiddlewareRum`) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
Maintaining this file:
- Every PR that changes SDK behavior adds a bullet under [Unreleased], in the
  right category (Added, Changed, Deprecated, Removed, Fixed, Security).
  Write it for app developers: what changes for them, not how it was done.
- To release: python3 scripts/changelog.py release <version>
  (moves [Unreleased] into a dated section; the release workflow refuses to
  publish a version that has no section and uses it as the GitHub release notes).
-->

## [Unreleased]

## [2.3.0] - 2026-10-13

### Added

- Opt-in header and response-body capture on `URLSession` network spans, split
  like the Middleware browser SDK. Both are off by default:
  - `MiddlewareRumBuilder.captureNetworkHeaders(_:)` records request and
    response headers as `http.request.header.<name>` /
    `http.response.header.<name>` (name lowercased, `-` replaced by `_`, e.g.
    `http.request.header.content_type`). Request headers are recorded as sent,
    including the trace headers the SDK injects. The value of `x-access-token`
    is recorded as `********`.
  - `captureResponseBodies(_:)` records `http.response.body` for responses
    whose `Content-Type` is `application/json`, `*+json` or `text/plain`,
    truncated to 64 KiB (UTF-8). Download tasks are never read, and request
    bodies are never recorded.
  - `ignoreHeaders(_:)` lists header names (case-insensitive) that header
    capture never records, e.g. `Authorization` or `Cookie`.

## [2.2.6] - 2026-10-01

### Added

- A `screen_view` span (the mobile counterpart of the browser `pageview`) is
  emitted whenever the visible screen changes, named after the screen and
  carrying `screen.name` and `last.screen.name`; the backend counts these as RUM
  views. Repeats of the current screen and `unknown` are skipped. It is only
  armed by UI instrumentation, so hybrid hosts that call
  `disableUIInstrumentation()` and report their own screen views through
  `setScreenName` are not double-counted.

## [2.2.5] - 2026-10-01

### Added

- Wrapper SDKs can report their own version: a `mw.rum.sdk.version` entry in
  the builder's `globalAttributes` now overrides the native SDK version in the
  `mw.rum.sdk.version` resource attribute.

### Changed

- **Breaking:** Session recording masking defaults now match the browser SDK:
  `RecordingOptions.maskAllTextInputs` and `maskAllImages` default to `false`
  (were `true`). The screen is recorded as-is and only secure / sensitive
  inputs (passwords, one-time codes, card numbers, addresses and similar
  content types) are masked; `WKWebView` content is no longer masked unless one
  of the two options is on. Apps that relied on the old defaults must set them
  explicitly, or tag views with the `mw-no-capture` accessibility token.
- On iOS / tvOS 17+, fields with the credit-card security code, expiration,
  name and type content types are also treated as sensitive and always masked.

## [2.2.4] - 2026-09-18

### Changed

- **Breaking:** Network spans use the current OpenTelemetry HTTP semantic
  conventions: `http.request.method`, `url.full`, `url.path`, `url.scheme`,
  `server.address`, `server.port` and `http.response.status_code` replace
  `http.method`, `http.url`, `http.target`, `http.scheme`, `net.peer.name`,
  `net.peer.port` and `http.status_code`. Update any queries, dashboards or
  alerts that filter on the old keys.

## [2.2.3] - 2026-09-10

### Added

- `MiddlewareRum.critical(_:metadata:)`, the correctly spelled replacement for
  `crtical(_:metadata:)`.

### Deprecated

- `MiddlewareRum.crtical(_:metadata:)`; use `critical(_:metadata:)`.
- `MiddlewareRum.trace(_:_:)` with an unlabeled metadata argument; use
  `trace(_:metadata:)`, which now matches the other log methods.

### Removed

- The public `RecordingBench` / `RecordingBenchMetrics` benchmarking helpers
  (exposed since 1.0.7) are gone.

### Fixed

- OTLP log export now sends the RUM access token in the `Authorization`
  header, like trace export. Logs sent with `MiddlewareRum.info(...)` and the
  other log methods were previously exported without it.

## [2.2.2] - 2026-09-04

### Removed

- **Breaking:** The legacy (v2) screenshot recorder is removed; session
  recording always uses the v3 recorder. `disableSessionRecordingV3()`,
  `isSessionRecordingV3Enabled()` and `isRecordingV3Configured()` are removed
  from `MiddlewareRumBuilder`, the public `ScreenshotManager` class is removed,
  and the `recordingV3` resource attribute is no longer sent. `addIgnoredView`,
  `removeIgnoredView`, the SwiftUI `.sensitive()` modifier and
  `RecordingOptions` keep working.

## [2.2.1] - 2026-09-02

### Added

- `MiddlewareRumBuilder.tracePropagationTargets(_:)` limits which outbound
  requests carry trace headers, so backend correlation works for your own
  services without sending trace ids to third parties. Each entry is a
  case-insensitive regular expression searched anywhere in the request URL
  (`"api.example.com"` matches `https://api.example.com/orders`); invalid
  patterns are ignored. Requests to other hosts are still traced, just without
  headers. Not calling it keeps propagating to every URL; an empty array turns
  propagation off.

## [2.2.0] - 2026-07-31

### Added

- `MiddlewareRum.startRecording()`, `stopRecording()` and `isRecording()`
  control session recording at runtime. `startRecording()` overrides both
  `disableRecording()` at init and the session sampler; either call is sticky
  across session rotations until the opposite call is made.

### Changed

- The `recording` / `recordingV3` resource attributes now follow the live
  recording state instead of the builder flags at init.

### Fixed

- Session recording never started when `build()` was called from a background
  queue, as React Native and Flutter hosts do. The start check now runs on the
  main run loop.
- Session recording is no longer skipped for the whole launch when the app
  starts offline: the SDK keeps checking reachability for up to 30 seconds and
  starts recording once the network is available.
- `mw.rum.sdk.version` reports the correct version again; 2.1.2 reported
  `2.1.1`.

## [2.1.2] - 2026-07-28

### Changed

- The background inactivity timeout is back to 15 minutes (was 5 minutes since
  1.0.1): returning to the foreground starts a new session only after the app
  has been inactive for more than 15 minutes.

## [2.1.1] - 2026-07-28

### Fixed

- When app lifecycle instrumentation is disabled
  (`disableAppLifcycleInstrumentation()`, as hybrid hosts such as React Native
  and Flutter do), the SDK no longer emits its native `AppStart` and
  `Middleware.initialize` spans, so app starts are not counted twice next to
  the host's own.

## [2.1.0] - 2026-07-27

### Added

- `MiddlewareRum.setNativeSession(_:startTimeMs:)` binds the RUM session to an
  externally managed session id (React Native / hybrid hosts). From then on
  internal rotation (4-hour expiry, inactivity) is suppressed and the caller
  must push every rotation; session recording, crash reports and all later
  telemetry follow the injected id.
- `MiddlewareRum.exportRawSpans(_:)` exports spans produced by another
  OpenTelemetry implementation (e.g. the React Native SDK's JS tracer) through
  the SDK's OTLP trace pipeline. Spans get the SDK's live resource with the
  native `session.id` / `session.start_time`, and are not subject to session
  sampling. Returns `false` if called before `build()`.
- The `browser.trace` resource attribute (`"true"`) is sent again.

### Fixed

- Crash reports are attributed to the session that was active when the app
  crashed. The session id stored for crash reports was only set at startup,
  so crashes after a session rotation pointed at the old session.
- Fixed a crash (infinite recursion) when the active resource was read or
  updated before `build()` had registered the tracer provider, e.g. on a
  session rotation before initialization.
- `mw.rum.sdk.version` reports the correct version again; 2.0.1 and 2.0.2
  reported `2.0.0`.

## [2.0.2] - 2026-07-20

### Added

- Tap heatmap capture: every completed tap (not a scroll or drag) is emitted as
  a `tap` span with `event.type=tap`, window-point coordinates (`x`, `y`,
  `pageX`, `pageY`), `viewport.width` / `viewport.height`, `screen.name`,
  `target.type`, `target.accessibility_id`, `target.text` (button title, label
  text, text field text or placeholder, or accessibility label) and a
  `target_xpath` selector of the form `Screen/ViewClass#accessibility-id`.
  Enabled with UI instrumentation; turn off with `disableUIInstrumentation()`.

## [2.0.1] - 2026-07-20

### Changed

- `integrateWebViewWithBrowserRum(view:)` now bridges the native session id
  into the web view as `window.__mwNativeSessionId` /
  `window.MiddlewareNative.getNativeSessionId()` instead of writing an
  `mwRumSessionId` cookie, so hybrid / PWA pages instrumented with the
  Middleware browser RUM SDK report under the native session. The script is
  injected at document start in every frame (call it before loading the URL),
  is updated when the session rotates, keeps the web view's other user scripts,
  and repeated calls for the same web view are ignored.

## [2.0.0] - 2026-07-19

### Added

- v3 session recording: masked screenshots captured on layout changes, plus
  touch indicators, sent as rrweb-compatible events through the OTLP metrics
  endpoint (`{target}/v1/metrics`) in gzip batches every 5 seconds. A new
  replay segment starts on session rotation, screen size change and return to
  the foreground. Sessions record `recordingV3="1"` as a resource attribute.
- `RecordingOptions` and `MiddlewareRumBuilder.recordingOptions(_:)`:
  `setFrequency(.low | .standard | .high)` (about 1 s / 330 ms / 100 ms
  between frames, default `.low`), `setQuality(.Low | .Standard | .High)` (JPEG
  quality 25 / 50 / 75 %, default `.Standard`), `setMaskAllTextInputs(_:)` and
  `setMaskAllImages(_:)` (both default `true` in this release).
- Per-view masking tokens in `accessibilityIdentifier` / `accessibilityLabel`:
  `mw-no-capture` always masks the view, `mw-no-mask` never masks it or its
  subviews. Secure and sensitive-content text fields, system pickers shown out
  of process, and views passed to `addIgnoredView` / `.sensitive()` are always
  masked.
- `disableSessionRecordingV3()` falls back to the legacy screenshot recorder.

### Changed

- **Breaking:** With recording enabled, the v3 recorder is used by default
  instead of the legacy screenshot recorder that uploaded to `{target}/v1/rum`.

## [1.0.7] - 2026-07-17

### Added

- dSYM upload tool: `Tools/dsym-upload` adds `upload-dsym.sh` and an Xcode
  build-phase script that upload dSYMs through
  `@middleware.io/sourcemap-uploader` for crash symbolication.

### Changed

- Session recording follows session sampling: it starts only for sessions
  sampled in by `sessionSamplingRatio`, and is re-evaluated (started or
  stopped) whenever the session rotates.

### Fixed

- Crash spans now carry `exception.type`, `exception.message` and
  `exception.stacktrace` on the span itself (not only on the event), plus
  `error=true`, `exception.framework=ios` and `crash.signal`. Pure signal
  crashes get a synthesized message such as
  `App terminated with SIGSEGV at <address>`, and an `exception` span event is
  added.
- Crash spans are flushed right after they are created on the next launch
  instead of waiting for the next batch.
- Processing a crash report no longer crashes when it has no signal info or
  is missing some of the stored device fields.

## [1.0.6] - 2026-03-30

### Changed

- Trace export authenticates with the RUM access token in the `Authorization`
  header; the `mw.account_key` resource attribute is no longer sent.
- `app`, `app.version`, `mw.rum.sdk.version` and the device model moved from
  per-span attributes to resource attributes. New resource attributes:
  `session.start_time` (updated on rotation), `os` (`iOS`) and `recording`
  (`"1"` / `"0"`). `browser.trace` is no longer sent.
- Session recording uploads include the session's resource attributes.
- Swift Package Manager: DeviceKit is pinned to exactly 5.1.0.
- Crash spans no longer set `error=true` (restored in 1.0.7).

### Fixed

- `mw.rum.sdk.version` reports the real SDK version; 1.0.2 through 1.0.5
  reported `1.0.1`.

## [1.0.5] - 2024-12-11

### Changed

- `session.id` is now a resource attribute and is updated on the resource when
  the session rotates.
- The `browser.mobile` resource attribute is replaced by `mw.rum` (`"true"`).

## [1.0.4] - 2024-10-01

### Changed

- Every span carries `browser.trace="true"` and `mw.rum="true"`, marking it as
  RUM telemetry.
- The SDK version attribute is renamed from `rum.sdk.version` to
  `mw.rum.sdk.version`.

## [1.0.3] - 2024-07-09

### Added

- CocoaPods support: `pod 'MiddlewareRum'` (iOS 13.0+, Swift 5.9), depending on
  SwiftProtobuf, PLCrashReporter, DeviceKit, SWCompression and Reachability.

### Changed

- **Breaking:** OpenTelemetry Swift is now bundled inside the SDK instead of
  being resolved as the `opentelemetry-swift` package, and `swift-log` is no
  longer a dependency (SwiftProtobuf 1.27+ is added). Apps that used
  OpenTelemetry Swift products transitively must add them themselves, and
  `getOpenTelemetrySdk()` returns the bundled `OpenTelemetry` type.
- **Breaking:** The log methods (`trace`, `info`, `debug`, `warning`, `error`,
  `crtical`) take a `String` message and `[String: String]` metadata instead of
  swift-log `Logger.Message` / `MetadataValue`.
- The `browser.trace` and `browser.mobile` resource attributes are sent as
  the string `"true"` instead of a boolean.

### Removed

- The OTLP metrics exporter and the `user.status` counter it reported.

## [1.0.2] - 2024-06-28

### Changed

- Swift Package Manager: the minimum swift-tools-version is lowered to 5.8
  (was 5.9), and the minimum `opentelemetry-swift` is 1.9.2 (was 1.9.1).

## [1.0.1] - 2024-03-04

### Added

- Session recording (iOS, tvOS, Mac Catalyst): screenshots of the key window
  about 3 times a second, uploaded as compressed batches to
  `{target}/v1/rum`. On by default when the network is reachable at startup;
  control it with `MiddlewareRumBuilder.disableRecording()` /
  `enableRecording()` / `isRecordingEnabled()`.
- `MiddlewareRum.addIgnoredView(_:)` / `removeIgnoredView(_:)` and the SwiftUI
  `.sensitive()` modifier blur sensitive views in recordings.
- `MiddlewareRumBuilder.disableUIInstrumentation()`.

### Changed

- The background inactivity timeout is 5 minutes (was 15): returning to the
  foreground after more than 5 minutes starts a new session.
- New dependency: SWCompression 4.8.5+.

## [1.0.0] - 2024-01-05

### Added

- Initial release of the Middleware iOS RUM SDK (`MiddlewareRum`) for iOS 13+,
  macOS 10.15+ and tvOS 13+, distributed with Swift Package Manager and built
  on OpenTelemetry Swift 1.9.1 (traces and logs exported over OTLP/HTTP).
- Configure with `MiddlewareRumBuilder`: `target`, `rumAccessToken`,
  `projectName` and `serviceName` (required), plus `deploymentEnvironment`,
  `globalAttributes`, `sessionSamplingRatio`, and
  `slowFrameDetectionThresholdMs` / `frozenFrameDetectionThresholdMs`
  (16.7 ms / 700 ms).
- Automatic instrumentation: app start, network connection type, and UIKit
  actions and view-controller transitions, plus the following, each with a
  builder switch: crash reporting (PLCrashReporter, sent on next launch;
  `disableCrashReportingInstrumentation()`), app lifecycle
  (`disableAppLifcycleInstrumentation()`), slow / frozen frame detection
  (`disableSlowRenderingDetection()`) and `URLSession` network spans with
  trace-header propagation (`disableNetworkMonitoring()`).
- Sessions rotate after 4 hours, or on returning to the foreground after 15
  minutes of inactivity.
- API: `addEvent(name:attributes:)`, `addError`, `addException`,
  `setGlobalAttributes`, `setScreenName`, `getSessionId`,
  `addSessionIdChangeCallback`, log methods (`trace`, `info`, `debug`,
  `warning`, `error`, `crtical`), `integrateWebViewWithBrowserRum(view:)` to
  link `WKWebView` pages to the native session, and `getOpenTelemetrySdk()`.
