// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0
import Foundation
#if os(iOS) || targetEnvironment(macCatalyst) || os(macOS)
import WebKit
#endif

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#endif

var middlewareRumInitTime = Date()
var globalAttributes: [String: Any] = [:]
let globalAttributesLock = NSLock()

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
/// Whether recording follows the sampler (`auto`) or has been explicitly
/// turned on/off by the host through `startRecording()` / `stopRecording()`.
/// A manual intent is sticky: it survives session rotation and sampler
/// re-evaluation until the opposite call is made.
enum RecordingIntent {
    case auto
    case forcedOn
    case forcedOff
}

private let recordingStateLock = NSLock()
private var isSessionRecordingActive = false
private var recordingTarget: String?
private var recordingToken: String?
private var recordingV3Enabled = false
private var recordingV3Options = RecordingOptions()
/// Value of `builder.isRecordingEnabled()` at init. Recording context is captured
/// even when this is false so `startRecording()` can turn recording on later.
private var recordingEnabledAtInit = false
private var recordingIntent: RecordingIntent = .auto
/// How long we keep retrying the initial reachability check before giving up.
private let recordingStartMaxWaitSeconds = 30.0
#endif

public enum CheckState {
    case unchecked
    case canStart
    case cantStart
}

@objc public class MiddlewareRum: NSObject {
        
    @objc internal class func create(builder: MiddlewareRumBuilder) -> Bool {
        middlewareRumInitTime = Date()

        let otlpTraceExporter = OtlpHttpTraceExporter(
            endpoint: URL(string: builder.target! + "/v1/traces")!,
            config: OtlpConfiguration(timeout: TimeInterval(10000),
                                      headers: [
                                        ("Authorization", builder.rumAccessToken!),
                                        ("Origin","sdk.middleware.io"),
                                        ("Access-Control-Allow-Headers", "*")
                                      ]
                                     )
        )
        rawSpanExporter = otlpTraceExporter
        let resource = createMiddlewareResource(builder: builder)
        let provider = TracerProviderBuilder()
            .with(sampler: SessionBasedSampler(ratio: builder.sessionSamplingRatio))
            .with(resource: resource)
            .add(spanProcessors: [
                GlobalAttributesProcessor(),
                SignPostIntegration(),
                BatchSpanProcessor(spanExporter: otlpTraceExporter),
                SimpleSpanProcessor(spanExporter: StdoutExporter())
            ]).build()
        OpenTelemetry.registerTracerProvider(tracerProvider: provider)
        
        let otlpLogExporter = OtlpHttpLogExporter(
            endpoint: URL(string: builder.target! + "/v1/logs")!,
            config:  OtlpConfiguration(timeout: TimeInterval(10000),
                                       headers:[
                                        ("Origin", "sdk.middleware.io"),
                                        ("Access-Control-Allow-Headers", "*")
                                       ]
                                      )
        )
        
        OpenTelemetry.registerLoggerProvider(loggerProvider: LoggerProviderBuilder()
            .with(resource: resource)
            .with(processors: [SimpleLogRecordProcessor(logRecordExporter: otlpLogExporter)])
            .build())
        
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
        
        // Hybrid hosts (React Native, Flutter) own app-start tracking and
        // disable app-lifecycle instrumentation; skip the native AppStart /
        // init spans there so app starts aren't double-counted.
        var mwInit: Span?
        if builder.isAppLifecycleInstrumentationEnabled() {
            AppStart(spanStart: middlewareRumInitTime).sendAppStartSpan()
            let initSpan = tracer
                .spanBuilder(spanName: "Middleware.initialize")
                .setStartTime(time: middlewareRumInitTime)
                .startSpan()
            initSpan.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "appstart")
            initSpan.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "app_activity")
            mwInit = initSpan
        }
        setGlobalAttributes(builder.globalAttributes!)
        if(builder.deploymentEnvironment != nil) {
            setGlobalAttributes([ResourceAttributes.deploymentEnvironment.rawValue: builder.deploymentEnvironment!])
        }
        
        if(builder.isNetworkMonitoringEnabled()) {
            _ = initializeNetworkMonitoring()
        }
        
        if(builder.isSlowRenderingDetectionEnabled()) {
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
            _ = SlowRenderingDetector(configuration: SlowRenderingConfiguration(slowFrameThreshold: builder.slowFrameDetectionThresholdMs, frozenFrameThreshold: builder.frozenFrameDetectionThresholdMs))
#elseif os(macOS)
            Log.debug("Slow rendering is not supported in macOS")
#endif
        }
        
        initializeNetworkTypeMonitoring()
        
        if(builder.isAppLifecycleInstrumentationEnabled()) {
            let appLifeCycle = AppLifecycleInstrumentation()
            appLifeCycle.registerLifecycleEvents()
        }
        
        if(builder.isCrashReportingEnabled()) {
            let crashReporting = CrashReportingInstrumentation()
            crashReporting.start()
        }
        
        if(builder.isUiInstrumentationEnabled()) {
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
            let uiInstrumentation = UIInstrumentation()
            uiInstrumentation.start()
#elseif os(macOS)
            Log.debug("UI instrumentation is supported only in iOS")
#endif
        }
        
#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
        // Capture the recording context unconditionally — startRecording() is an
        // explicit host intent that overrides a disabled-at-init configuration,
        // and it needs the target/token/options to build a recorder.
        recordingStateLock.lock()
        recordingTarget = builder.target
        recordingToken = builder.rumAccessToken
        // Deliberately NOT isSessionRecordingV3Enabled(): that ANDs in the
        // recording flag, so a disabled-at-init config would later start the
        // legacy v2 recorder instead of v3.
        recordingV3Enabled = builder.isRecordingV3Configured()
        recordingV3Options = builder.recordingOptions
        recordingEnabledAtInit = builder.isRecordingEnabled()
        recordingStateLock.unlock()

        if builder.isRecordingEnabled() {
            scheduleRecordingStart()

            // Re-evaluate recording when the session rotates so SessionBasedSampler
            // decisions stay aligned with session recordings.
            addSessionIdCallback {
                DispatchQueue.main.async {
                    applyRecordingState()
                }
            }
        }
#else
        if builder.isRecordingEnabled() {
            print("Session recording is not supported.")
        }
#endif

        mwInit?.end()

        return true
    }

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
    /// Defers the first recording start until the network is reachable.
    ///
    /// The timer is installed on the **main** run loop: `Timer.scheduledTimer`
    /// binds to `RunLoop.current`, and hybrid hosts (React Native, Flutter) call
    /// `build()` from a GCD queue that has no run loop running — there the timer
    /// would never fire and recording would never start.
    ///
    /// Reachability is re-checked on every tick rather than once, so an app that
    /// launches offline still starts recording once connectivity arrives.
    private class func scheduleRecordingStart() {
        DispatchQueue.main.async {
            let deadline = Date().addingTimeInterval(recordingStartMaxWaitSeconds)
            let timer = Timer(timeInterval: 0.1, repeats: true) { timer in
                if NetworkReachability.isNetworkAvailable() {
                    timer.invalidate()
                    applyRecordingState()
                    return
                }
                if Date() >= deadline {
                    timer.invalidate()
                    Log.debug("Network unreachable after \(recordingStartMaxWaitSeconds)s; session recording not started.")
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Resolves whether recording should be running and starts/stops it to match.
    ///
    /// Must run on the main thread: starting the recorder installs UIKit swizzles
    /// and reads the key window.
    ///
    /// The decision honours the host's explicit intent first, and only falls back
    /// to the sampler when no manual override is in effect.
    private class func applyRecordingState() {
        guard recordingTarget != nil, recordingToken != nil else {
            return
        }

        recordingStateLock.lock()
        let intent = recordingIntent
        let enabledAtInit = recordingEnabledAtInit
        recordingStateLock.unlock()

        let shouldRecord: Bool
        switch intent {
        case .forcedOff:
            shouldRecord = false
        case .forcedOn:
            // Explicit host intent wins over both the init flag and the sampler.
            shouldRecord = true
        case .auto:
            shouldRecord = enabledAtInit && isSampledIn()
        }

        recordingStateLock.lock()
        let currentlyActive = isSessionRecordingActive
        recordingStateLock.unlock()

        if shouldRecord {
            guard !currentlyActive else {
                return
            }
            if recordingV3Enabled {
                // v3: rrweb events through the metrics endpoint; the legacy
                // (v2) screenshot recorder must not run alongside it.
                ReplayRecorderV3.shared.start(
                    target: recordingTarget!,
                    token: recordingToken!,
                    options: recordingV3Options)
            } else {
                let captureSettings = getCaptureSettings(fps: 3, quality: "standard")
                ScreenshotManager.shared.setSettings(settings: captureSettings)
                ScreenshotManager.shared.start(
                    startTs: UInt64(Date().timeIntervalSince1970 * 1000),
                    target: recordingTarget,
                    token: recordingToken)
            }
            recordingStateLock.lock()
            isSessionRecordingActive = true
            recordingStateLock.unlock()
            updateRecordingResourceAttributes(recording: true)
        } else if currentlyActive {
            if recordingV3Enabled {
                ReplayRecorderV3.shared.stop()
            } else {
                ScreenshotManager.shared.stop()
            }
            recordingStateLock.lock()
            isSessionRecordingActive = false
            recordingStateLock.unlock()
            updateRecordingResourceAttributes(recording: false)
        }
    }

    /// Probes the active tracer sampler (SessionBasedSampler) for this session.
    private class func isSampledIn() -> Bool {
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
        let probe = tracer.spanBuilder(spanName: "record init").startSpan()
        let sampled = probe.isRecording
        probe.end()
        return sampled
    }

    /// Keeps the `recording` / `recordingV3` resource attributes in step with the
    /// live recording state. They are written once at init from the builder flags,
    /// but recording can now be toggled at runtime — and these attributes are what
    /// tells the backend a session has a replay to play back.
    private class func updateRecordingResourceAttributes(recording: Bool) {
        var activeResource = OpenTelemetry.instance.tracerProvider.getActiveResource()
        activeResource.attributes[MiddlewareConstants.Attributes.RECORDING] =
            AttributeValue(recording ? "1" : "0")
        activeResource.attributes[MiddlewareConstants.Attributes.RECORDING_V3] =
            AttributeValue(recording && recordingV3Enabled ? "1" : "0")
        OpenTelemetry.instance.tracerProvider.updateActiveResource(activeResource)
    }

    /// Starts session recording immediately, overriding both a disabled-at-init
    /// configuration (`disableRecording()`) and the session sampler.
    ///
    /// The intent is sticky — recording keeps running across session rotations
    /// until `stopRecording()` is called.
    @objc public class func startRecording() {
        recordingStateLock.lock()
        recordingIntent = .forcedOn
        let configured = recordingTarget != nil && recordingToken != nil
        recordingStateLock.unlock()

        guard configured else {
            Log.debug("startRecording() called before MiddlewareRum was initialized; ignoring.")
            return
        }
        onMain { applyRecordingState() }
    }

    /// Stops session recording immediately.
    ///
    /// The intent is sticky — recording stays off across session rotations and
    /// sampler re-evaluation until `startRecording()` is called.
    @objc public class func stopRecording() {
        recordingStateLock.lock()
        recordingIntent = .forcedOff
        let configured = recordingTarget != nil && recordingToken != nil
        recordingStateLock.unlock()

        guard configured else {
            Log.debug("stopRecording() called before MiddlewareRum was initialized; ignoring.")
            return
        }
        onMain { applyRecordingState() }
    }

    /// Whether session recording is currently running.
    @objc public class func isRecording() -> Bool {
        recordingStateLock.lock()
        defer {
            recordingStateLock.unlock()
        }
        return isSessionRecordingActive
    }

    private class func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
#endif
    
    @objc public class func setGlobalAttributes(_ attributes: [String: Any]) {
        globalAttributesLock.lock()
        defer {
            globalAttributesLock.unlock()
        }
        let newAttrs = globalAttributes.merging(attributes) { (_, new) in
            return new
        }
        globalAttributes = newAttrs
    }
    
    class func internalGetGlobalAttributes() -> [String: Any] {
        globalAttributesLock.lock()
        defer {
            globalAttributesLock.unlock()
        }
        return globalAttributes
    }
    
    class func addGlobalAttributesToSpan(_ span: Span) {
        let attrs = internalGetGlobalAttributes()
        attrs.forEach({ (key: String, value: Any) in
            switch value {
            case is Int:
                span.setAttribute(key: key, value: value as! Int)
            case is String:
                span.setAttribute(key: key, value: value as! String)
            case is Double:
                span.setAttribute(key: key, value: value as! Double)
            case is Bool:
                span.setAttribute(key: key, value: value as! Bool)
            default:
                nop()
            }
        })
        
    }
    
    class func createMiddlewareResource(builder: MiddlewareRumBuilder) -> Resource {
        
        var app = Bundle.main.infoDictionary?["CFBundleName"] as? String
        if app == "" {
            app = MiddlewareConstants.Global.UNKNOWN_APP_NAME
        }
        var defaultResource = DefaultResources().get()
        defaultResource.merge(other: Resource(attributes: [
            MiddlewareConstants.Attributes.RUM_SDK_VERSION: AttributeValue(MiddlewareConstants.Global.VERSION_STRING),
            MiddlewareConstants.Attributes.APP: AttributeValue(app!),
            ResourceAttributes.serviceName.rawValue : AttributeValue(builder.serviceName!),
            MiddlewareConstants.Attributes.MW_RUM: AttributeValue("true"),
            ResourceAttributes.deviceModelName.rawValue: AttributeValue(Device.current.model),
            MiddlewareConstants.Attributes.PROJECT_NAME: AttributeValue(builder.projectName!),
            MiddlewareConstants.Attributes.SESSION_ID: AttributeValue(getSessionId()),
            MiddlewareConstants.Attributes.SESSION_START_TIME: AttributeValue(getSessionStartTime()),
            MiddlewareConstants.Attributes.APP_VERSION: AttributeValue(getAppVersion()!),
            MiddlewareConstants.Attributes.OS: AttributeValue("iOS"),
            MiddlewareConstants.Attributes.BROWSER_TRACE: AttributeValue("true"),
            MiddlewareConstants.Attributes.RECORDING: AttributeValue(builder.isRecordingEnabled() ? "1" : "0"),
            MiddlewareConstants.Attributes.RECORDING_V3: AttributeValue(builder.isSessionRecordingV3Enabled() ? "1" : "0")
        ]))
        return defaultResource
    }
    
    class func initializeNetworkMonitoring() -> URLSessionInstrumentation {
        return URLSessionInstrumentation(configuration: URLSessionInstrumentationConfiguration(
            shouldInstrument: { URLRequest in
                guard let url = URLRequest.url?.absoluteString else {
                    return true
                }
                let excludedPaths = ["/v1/metrics", "/v1/logs", "/v1/traces", "/v1/rum"]
                
                for path in excludedPaths {
                    if url.contains(path) {
                        return false
                    }
                }
                return true
            },
            spanCustomization: { URLRequest, spanBuilder in
                spanBuilder.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "http")
                spanBuilder.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "fetch")
            },
            receivedError: { (error: Error, _: DataOrFile?, status: HTTPStatus, span: Span) in
                span.addEvent(name: "error", attributes: ["description" : AttributeValue(error.localizedDescription)])
            }
        )
        )
    }
    
    class func initializeNetworkTypeMonitoring() {
        do{
            let _ = try NetworkMonitor()
        } catch {
            print("Middleware: Failed to initialize network type detection")
        }
        
    }
    
    /// Send custom span to trace
    /// - Parameters:
    ///   - name: Sets the name of the span
    ///   - attributes: Attach attributes to span
    @objc public class func addEvent(name: String, attributes: NSDictionary) {
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
        let now = Date()
        let span = tracer.spanBuilder(spanName: name)
        for attribute in attributes {
            span.setAttribute(key: attribute.key as? String ?? "", value: AttributeValue(attribute.value) ?? AttributeValue(""))
        }
        span.setStartTime(time: now).startSpan().end(time: now)
    }
    
    
    
    /// Get the Middleware Session ID associated with this instance of the RUM instrumentation library.
    /// Note: this value can change throughout the lifetime of an application instance, so it is recommended that you do not cache this value, but always retrieve it from here when needed.
    /// - Returns: the session id String
    @objc public class func getSessionId() -> String {
        return getRumSessionId()
    }
    
    /// Add screen name to view. Note this only sets screen name from main thread.
    /// - Parameter name: <#name description#>
    @objc public class func setScreenName(_ name: String) {
        if !Thread.current.isMainThread {
            Log.debug("MiddlewareRum.setScreenName is not called from main thread: \(Thread.current.debugDescription)")
            return
        }
        setScreenNameInternal(name, true)
    }
    
    @objc public class func addSessionIdChangeCallback(_ callback: @escaping (() -> Void)) {
        addSessionIdCallback(callback)
    }

    /// Binds the RUM session to an externally-managed session id (React Native
    /// / hybrid hosts). Internal session rotation is suppressed from this point
    /// on — the caller owns the session lifecycle and must push every rotation.
    /// The v3 session recording, crash reports, and all subsequent telemetry
    /// follow the injected id.
    ///
    /// - Parameters:
    ///   - sessionId: the externally-generated session id (32 hex chars)
    ///   - startTimeMs: session start time in epoch milliseconds
    @objc public class func setNativeSession(_ sessionId: String, startTimeMs: Double) {
        setNativeSessionInternal(sessionId, startTimeMs: Int(startTimeMs.rounded()))
    }
    
    public class func getOpenTelemetrySdk() -> OpenTelemetry {
        return OpenTelemetry.instance
    }
    
    
    /// Add a custom exception to RUM monitoring. This can be useful for tracking custom error handling in your application.
    /// NOTE : This event will be turned into a Span and sent to the RUM ingest along with other, auto-generated spans.
    /// - Parameter e: NSException associated with this event.
    @objc  public class func addException(e: NSException) {
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
        let now = Date()
        let typeName = e.name.rawValue
        let span = tracer.spanBuilder(spanName: typeName).setStartTime(time: now).startSpan()
        span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "error")
        span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "error")
        span.setAttribute(key: MiddlewareConstants.Attributes.ERROR, value: true)
        span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_TYPE, value: typeName)
        if e.reason != nil {
            span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_MESSAGE, value: e.reason!)
        }
        let stack = e.callStackSymbols.joined(separator: "\n")
        if !stack.isEmpty {
            span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_STACKTRACE, value: stack)
        }
        span.addEvent(name: "exception")
        span.end(time: now)
    }
    
    
    /// Add a custom errors to RUM monitoring. This can be useful for tracking custom error handling in your application.
    /// NOTE: This event will be turned into a Span and sent to the RUM ingest along with other, auto-generated spans.
    /// - Parameter e: Error associated with this event.
    @objc public class func addError(e: Error) {
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
        let now = Date()
        let typeName = String(describing: type(of: e))
        let span = tracer.spanBuilder(spanName: typeName).setStartTime(time: now).startSpan()
        span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "error")
        span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "error")
        span.setAttribute(key: MiddlewareConstants.Attributes.ERROR, value: true)
        span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_TYPE, value: typeName)
        span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_MESSAGE, value: e.localizedDescription)
        span.end(time: now)
    }
    
    
    /// Add a custom error to RUM monitoring. This can be useful for tracking custom error handling in your application.
    /// NOTE: This event will be turned into a Span and sent to the RUM ingest along with other, auto-generated spans.
    /// - Parameter e: String associated with this event.
    @objc public class func addError(_ e: String) {
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
        let now = Date()
        let typeName = "MiddlewareRum.addError(String)"
        let span = tracer.spanBuilder(spanName: typeName).setStartTime(time: now).startSpan()
        span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "error")
        span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "error")
        span.setAttribute(key: MiddlewareConstants.Attributes.ERROR, value: true)
        span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_TYPE, value: "String")
        span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_MESSAGE, value: e)
        span.end(time: now)
    }
    
#if os(iOS) || targetEnvironment(macCatalyst) || os(macOS)
    private static let webViewIntegrations =
        NSMapTable<WKWebView, WebViewInstrumentation>(keyOptions: .weakMemory,
                                                      valueOptions: .strongMemory)

    /// Bridges the native RUM session id into the given WKWebView so pages
    /// instrumented with the Middleware browser RUM SDK report under the native
    /// session. Must be called before loading the URL.
    @objc public class func integrateWebViewWithBrowserRum(view: WKWebView) {
        if webViewIntegrations.object(forKey: view) != nil {
            return
        }
        let instrumentation = WebViewInstrumentation(view: view)
        webViewIntegrations.setObject(instrumentation, forKey: view)
        instrumentation.enable()
    }
#endif
    
    /// Send trace log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional dditional information with log
    public class func trace(_ message: String, _ metadata: [String: String]? = nil) {
        Log.trace(message)
        MiddlewareRum.log(message: message, severity: .trace, metadata: metadata ?? [:])
    }
    
    /// Send info log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func info(_ message: String, metadata: [String: String]? = nil) {
        Log.debug(message)
        MiddlewareRum.log(message: message, severity: .info, metadata: metadata ?? [:])
    }
    
    /// Send error log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func error(_ message: String, metadata: [String: String]? = nil) {
        Log.error(message)
        MiddlewareRum.log(message: message, severity: .error, metadata: metadata ?? [:])
    }
    
    /// Send info log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func debug(_ message: String, metadata: [String: String]? = nil) {
        Log.debug(message)
        MiddlewareRum.log(message: message, severity: .debug, metadata: metadata ?? [:])
    }
    
    /// Send warning log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func warning(_ message: String, metadata: [String: String]? = nil) {
        Log.warning(message)
        MiddlewareRum.log(message: message, severity: .warn, metadata: metadata ?? [:])
    }
    
    /// Send critical log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func crtical(_ message: String, metadata: [String: String]? = nil) {
        Log.error(message)
        MiddlewareRum.log(message: message, severity: .fatal, metadata: metadata ?? [:])
    }

#if os(iOS) || targetEnvironment(macCatalyst)
    /// Sanitize sensitive information
    /// - Parameter view: Any UIView will be blurred
    @objc public class func addIgnoredView(_ view: UIView) {
        ScreenshotManager.shared.addSanitizedElement(view)
        ReplayRecorderV3.shared.addSanitizedElement(view)
    }

    /// To show sensitive information use this method.
    /// - Parameter view: Any view which is been sanitize already.
    @objc public class func removeIgnoredView(_ view: UIView) {
        ScreenshotManager.shared.removeSanitizedElement(view)
        ReplayRecorderV3.shared.removeSanitizedElement(view)
    }
#endif

    private class func log(message: String, severity: Severity, metadata: [String: String]) {
        var attribute: [String: AttributeValue] = [:]
        for (name, value) in metadata {
            attribute[name] = AttributeValue(value)
        }
        OpenTelemetry.instance.loggerProvider
            .get(instrumentationScopeName: MiddlewareConstants.Global.INSTRUMENTATION_NAME)
            .logRecordBuilder()
            .setSeverity(severity)
            .setBody(AttributeValue(message))
            .setAttributes(attribute)
            .emit()
    }
}
