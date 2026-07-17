# middleware-ios
---
<p align="center">
    <a href="https://github.com/middleware-labs/middleware-ios/releases">
        <img alt="Build Status" src="https://img.shields.io/badge/status-beta-orange">
      </a>
    <a href="https://github.com/middleware-labs/middleware-ios/actions/workflows/BuildAndTest.yml?query=branch%3Amain+">
        <img alt="GitHub release (latest SemVer)" src="https://github.com/middleware-labs/middleware-ios/actions/workflows/BuildAndTest.yml/badge.svg">
    </a>
    <a href="https://github.com/middleware-labs/middleware-android/releases">
        <img alt="GitHub release (latest SemVer)" src="https://img.shields.io/github/v/release/middleware-labs/middleware-ios?include_prereleases&style=flat">
    </a>
</p>

---

## Features

- Access to OpenTelemetry APIs
- Network Monitoring
- Crash Reporting
- AppLifecycle Instrumentation
- Slow Rendering Detection
- WebView Instrumentation
- Api for sending custom errors & record exceptions
- Custom logging
- Session Recording

## Benchmarks

Session-recording capture → JPEG → tar.gz via `RecordingBench` (mirrors `ScreenshotManager`). As of **2026-07-15**. Production flush size is **10 frames per tar.gz**.

### Production-readiness gate

| Metric | Threshold |
|---|---|
| Upload | ≤ 3 MB/min |
| Avg capture | ≤ 80 ms |

### Screenshot capture / encode

| Scenario | Baseline | Avg capture (ms) | tar.gz (bytes) | Frames/tar | Tars/min | MB/min | 1h bytes | 4h tars | Ready |
|---|---|---|---|---|---|---|---|---|---|
| idle_recording_off_proxy | recording_off | 3 | 2337 | 10 | 6 | 0.013 | 817889 | 1440 | yes |
| idle_recording_on_low | recording_on | 28.6 | 10874 | 10 | 6 | 0.062 | 3900703 | 1440 | yes |
| scroll_recording_on_standard | recording_on | 13 | 12369 | 10 | 18.182 | 0.214 | 13463716 | 4364 | yes |
| stress_recording_on_high | recording_on | 12.7 | 12459 | 10 | 30 | 0.356 | 22397583 | 7200 | yes |

### Measured tar.gz size (recording on)

| Workload | Frames / tar | Avg frame | JPEG bytes in tar | tar.gz (upload) | Frames / min | Tars / min |
|---|---:|---:|---:|---:|---:|---:|
| Default Low quality | 10 | 14335 B (14.0 KB) | 140.0 KB | **10874 B (10.6 KB)** | 60 | **6** |
| Standard quality | 10 | 15816 B (15.4 KB) | 154.5 KB | **12369 B (12.1 KB)** | 181.8 | **18.182** |
| High quality (stress) | 10 | 16822 B (16.4 KB) | 164.3 KB | **12459 B (12.2 KB)** | 300 | **30** |

### Measured upload rates (recording on)

| Workload | Bytes / min | MB / min |
|---|---:|---:|
| Default Low quality | 65012 B (63.5 KB) | 0.062 |
| Standard quality | 224395 B (219.1 KB) | 0.214 |
| High quality (stress) | 373293 B (364.5 KB) | 0.356 |

### Projected session upload (recording on)

Each cell is **tar upload count · total size**.

| Workload | tar.gz each | 5 min | 15 min | 30 min | 1 hour | 2 hours | 4 hours |
|---|---:|---:|---:|---:|---:|---:|---:|
| Default Low quality | 10.6 KB | 30 × 10.6 KB = 318.6 KB | 90 × 10.6 KB = 955.7 KB | 180 × 10.6 KB = 1.87 MB | 360 × 10.6 KB = 3.73 MB | 720 × 10.6 KB = 7.47 MB | 1440 × 10.6 KB = 14.93 MB |
| Standard quality | 12.1 KB | 91 × 12.1 KB = 1.07 MB | 273 × 12.1 KB = 3.22 MB | 545 × 12.1 KB = 6.43 MB | 1091 × 12.1 KB = 12.87 MB | 2182 × 12.1 KB = 25.74 MB | 4364 × 12.1 KB = 51.48 MB |
| High quality (stress) | 12.2 KB | 150 × 12.2 KB = 1.78 MB | 450 × 12.2 KB = 5.35 MB | 900 × 12.2 KB = 10.69 MB | 1800 × 12.2 KB = 21.39 MB | 3600 × 12.2 KB = 42.77 MB | 7200 × 12.2 KB = 85.55 MB |

**Planning:** default Low ≈ 3.7 MB/hour (360 uploads); 4 hours ≈ 14.9 MB (1440 uploads). Real apps vary with UI density and network conditions.

## Setup
            
### Add the following line in `Package.swift` in `dependencies`
            
```swift
.package(url: "https://github.com/middleware-labs/middleware-ios", from: "1.0.7"),
```

## Using Cocoapods

```ruby
pod "MiddlewareRum", "~> 1.0.7"
```

## Initialization of Middleware iOS sdk
            
```swift
import SwiftUI
import MiddlewareRum
            
@main
struct YourApp: App {
    init() {
        MiddlewareRumBuilder()
            .globalAttributes(["customerId" : "123456"])
            .target("<target>")
            .serviceName("Mobile-SDK-iOS")
            .projectName("Mobile-SDK-iOS")
            .rumAccessToken("<account-key>")
            .deploymentEnvironment("PROD")
            .build()
        
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## Documentation

### Configurations

Methods that can be used for setting instrumentation & configure your application.
                                
<table>
    <thead>
        <tr><td>Option</td><td>Description</td><tr>
    </thead>
    <tbody>
        <tr>
            <td>
                <code lang="swift">.rumAccessToken(String)</code>
            </td>
            <td>
                Sets the RUM account access token to authorize client to send telemetry data to Middleware
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.target(String)</code>
            </td>
            <td>
                Sets the target URL to which you want to send telemetry data. For example - Unified Observability Platform | Middleware
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.serviceName(String)</code>
            </td>
            <td>
                Sets the service name for your application. This can be used further for filtering by service name.
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.projectName(String)</code>
            </td>
            <td>
                Sets the project name for your application.
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.deploymentEnvironment(String)</code>
            </td>
            <td>
                Sets the environment attribute on the spans that are generated by the instrumentation. For Example - PROD | DEV
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.disableCrashReportingInstrumentation()</code>
            </td>
            <td>
                Disable crash reporting. By default it is enabled.
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.disableNetworkMonitoring()</code>
            </td>
            <td>
                Disable HTTP Instrumentation. By default it is enabled.
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.disableSlowRenderingDetection()</code>
            </td>
            <td>
                Disable slow or frozen frame renders. By default it is enabled.
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.slowFrameDetectionThresholdMs(Double)</code>
            </td>
            <td>
                Sets the default polling for slow render detection. Default value in milliseconds is 16.7
            </td>
        </tr>
        <tr>
            <td>
                <code lang="swift">.frozenFrameDetectionThresholdMs(Double)</code>
            </td>
            <td>
                Sets the default polling for slow render detection. Default value in milliseconds is 700
            </td>
        </tr>
    </tbody>
</table>

### Logging using Middleware API

```swift

MiddlewareRum.info("Some information")
MiddlewareRum.debug("Some information")
MiddlewareRum.trace("Some information")
MiddlewareRum.warning("Some information")
MiddlewareRum.error("Some information")
MiddlewareRum.critical("Some information")
```

### Adding custom error to trace

```swift
MiddlewareRum.addError("Unable to process I am error")
```

### Custom Exception

```swift
MiddlewareRum.addException(e: NSException(name: NSExceptionName(rawValue: "RuntimeException"), reason: "I am custom exception"))
```

### Set screen name

```swift
MiddlewareRum.setScreenName("WebView")
```

### Set Global Attributes

```swift
MiddlewareRum.setGlobalAttributes(["some": "value"])
```

### WebView Instrumentation

```swift
MiddlewareRum.integrateWebViewWithBrowserRum(view: webView)
```

### Enable Session Recording

By default session recording is enabled, to disable call `.disableRecording()` :

```swift
    MiddlewareRumBuilder()
        .globalAttributes(["customerId" : "123456"])
        .target("<target>")
        .serviceName("Mobile-SDK-iOS")
        .projectName("Mobile-SDK-iOS")
        .rumAccessToken("<account-key>")
        .deploymentEnvironment("PROD")
        .disableRecording()
        .build()
```

#### Sensitive views (View will get blurred) 

```swift

//SwiftUI
Text("Very important sensitive text").sensitive()

// UIKit
MiddlewareRum.addIgnoredView(view)
```

## Upload dSYM files (crash symbolication)

Reuse **`@middleware.io/sourcemap-uploader`** (same package as JS sourcemaps) with the `upload-dsym` command — same SAS + PUT protocol as the Android mapping plugin.

```bash
export MW_API_KEY="<your_rum_account_key>"

npx @middleware.io/sourcemap-uploader upload-dsym \
  --apiKey "$MW_API_KEY" \
  --appVersion "1.0.0" \
  --path "/path/to/YourApp.app.dSYM"
```

Or use the thin wrappers under [`Tools/dsym-upload`](Tools/dsym-upload) (prefer a local `sourcemap-uploader` checkout, then `npx`):

```bash
./Tools/dsym-upload/upload-dsym.sh \
  --version "1.0.0" \
  --path "/path/to/YourApp.app.dSYM"
```

`--appVersion` must match the `app.version` / marketing version sent by the SDK.  
Default backend: `https://app.middleware.io/api/v1/rum/getSasUrl` (override with `--backendUrl` / `MW_BACKEND_URL`).

### Xcode Run Script

The Coffee Cart sample includes an **Upload Middleware dSYM** phase that calls `Tools/dsym-upload/xcode-upload-dsym.sh`. For your app:

1. Target → Build Phases → New Run Script Phase  
2. `"${SRCROOT}/path/to/Tools/dsym-upload/xcode-upload-dsym.sh"`  
3. Set `MW_API_KEY` and `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`

Docs: [`Tools/dsym-upload/README.md`](Tools/dsym-upload/README.md) · [`sourcemap-uploader`](https://www.npmjs.com/package/@middleware.io/sourcemap-uploader)

## Coffee Cart Sample App

`Examples/MiddlewareApp` is a full **Coffee Cart** ecommerce SwiftUI demo that exercises every Middleware iOS RUM feature in a realistic coffee-ordering flow.

### Screens

| Tab / Screen | What the user does |
|--------------|-------------------|
| **Menu** | Browse specialty coffees, fetch live catalog (network monitoring), open product detail |
| **Product Detail** | Choose size (S/M/L), add to cart (`addEvent`) |
| **Cart** | Change quantities, proceed to checkout |
| **Checkout** | Delivery + payment (card fields use `.sensitive()`), place order via URLSession |
| **Order Confirmation** | Success event, clear cart |
| **Account** | Save profile (`setGlobalAttributes` with `customerId`), open Help |
| **Help (WebView)** | `setScreenName` + `integrateWebViewWithBrowserRum` |
| **RUM Lab** | Crash, custom exception/error, events, all log levels, HTTP, sensitive field demo |

### Run

1. Open `Examples/MiddlewareApp/MiddlewareApp.xcodeproj` in Xcode.
2. In `MiddlewareAppApp.swift`, replace `<target>` and `<rum-token>` with your Middleware credentials.
3. Build & run on a simulator or device.

Service / project name sent to Middleware: `CoffeeCart-iOS`.

### RUM feature → screen map

| Feature | Where it is exercised |
|---------|------------------------|
| Network monitoring (URLSession) | Menu catalog fetch, Checkout order, Rum Lab HTTP |
| Crash reporting | Rum Lab Crash App |
| App lifecycle instrumentation | Automatic |
| Slow rendering detection | Automatic (enabled by default) |
| WebView instrumentation | Help screen |
| Custom errors (`addError`) | Menu/Checkout failures, Rum Lab |
| Custom exceptions (`addException`) | Checkout failure, Rum Lab |
| Custom logging (info/debug/trace/warning/error) | Shop flow + Rum Lab buttons |
| Session recording + `.sensitive()` | Checkout card/expiry/CVV; Rum Lab demo field |
| `setScreenName` | Every major screen |
| `setGlobalAttributes` / builder globals | App init + Account profile save |
| `addEvent` | Add to cart, checkout started, order placed/confirmed, Rum Lab |
