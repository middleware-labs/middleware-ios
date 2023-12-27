// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import StdoutExporter
import URLSessionInstrumentation
import NetworkStatus
import SignPostIntegration
import ResourceExtension
import WebKit
import Logging

var middlewareRumInitTime = Date()
var globalAttributes: [String: Any] = [:]
let globalAttributesLock = NSLock()

@objc public class MiddlewareRum: NSObject {
    
    static let logger: Logging.Logger = Logging.Logger(label: "MiddlewareLogger")
    
    @objc internal class func create(builder: MiddlewareRumBuilder) -> Bool {
        middlewareRumInitTime = Date()
        
        let otlpTraceExporter = OtlpHttpTraceExporter(
            endpoint: URL(string: builder.target! + "/v1/traces")!,
            config: OtlpConfiguration(timeout: TimeInterval(10000),
                                      headers: [
                                        ("Origin","sdk.middleware.io"),
                                        ("Access-Control-Allow-Headers", "*")
                                      ]
                                     )
        )
        
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
            .with(sampler: SessionBasedSampler(ratio: builder.sessionSamplingRatio))
            .with(resource: createMiddlewareResource(builder: builder))
            .add(spanProcessors: [
                GlobalAttributesProcessor(),
                SignPostIntegration(),
                BatchSpanProcessor(spanExporter: otlpTraceExporter),
                SimpleSpanProcessor(spanExporter: StdoutExporter())
            ]).build()
        )
        
        
        let otlpMetricExporter = OtlpHttpMetricExporter(
            endpoint: URL(string: builder.target! + "/v1/metrics")!,
            config: OtlpConfiguration(timeout: TimeInterval(10000),
                                      headers: [
                                        ("Origin", "sdk.middleware.io"),
                                        ("Access-Control-Allow-Headers", "*")
                                      ]
                                     )
        )
        
        OpenTelemetry.registerMeterProvider(meterProvider: MeterProviderBuilder()
            .with(exporter: otlpMetricExporter)
            .with(resource: createMiddlewareResource(builder: builder))
            .with(processor: MetricProcessorSdk())
            .with(pushInterval: 60)
            .build())
        
        OpenTelemetry.instance
            .meterProvider.get(instrumentationName: Constants.Global.INSTRUMENTATION_NAME, instrumentationVersion: Constants.Global.VERSION_STRING)
            .createIntCounter(name: "user.status")
            .add(value: 1, labels: ["description" : "User Status", "valueType": "1", "unit": ""])
        
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
            .with(resource: createMiddlewareResource(builder: builder))
            .with(processors: [SimpleLogRecordProcessor(logRecordExporter: otlpLogExporter)])
            .build())
        
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: Constants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: Constants.Global.VERSION_STRING)
        
        AppStart(spanStart: middlewareRumInitTime).sendAppStartSpan()
        let mwInit = tracer
            .spanBuilder(spanName: "Middleware.initialize")
            .setStartTime(time: middlewareRumInitTime)
            .startSpan()
        mwInit.setAttribute(key: Constants.Attributes.COMPONENT, value: "appstart")
        mwInit.setAttribute(key: Constants.Attributes.EVENT_TYPE, value: "app_activity")
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
            logger.info("Slow rendering is supported only in iOS")
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
            logger.info("UI instrumentation is supported only in iOS")
#endif
        }
        
        mwInit.end()
        
        return true
    }
    
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
        var defaultResource = DefaultResources().get()
        defaultResource.merge(other: Resource(attributes: [
            "mw.account_key" :AttributeValue(builder.rumAccessToken!),
            ResourceAttributes.serviceName.rawValue : AttributeValue(builder.serviceName!),
            "browser.trace" : AttributeValue(true),
            ResourceAttributes.browserMobile.rawValue : AttributeValue(true),
            ResourceAttributes.deviceModelName.rawValue: AttributeValue(Device.current.model),
            "project.name":AttributeValue(builder.projectName!)
        ]))
        return defaultResource
    }
    
    class func initializeNetworkMonitoring() -> URLSessionInstrumentation {
        return URLSessionInstrumentation(configuration: URLSessionInstrumentationConfiguration(
            shouldInstrument: { URLRequest in
                guard let url = URLRequest.url?.absoluteString else {
                    return true
                }
                let excludedPaths = ["/v1/metrics", "/v1/logs", "/v1/traces"]
                
                for path in excludedPaths {
                    if url.contains(path) {
                        return false
                    }
                }
                return true
            },
            spanCustomization: { URLRequest, spanBuilder in
                spanBuilder.setAttribute(key: Constants.Attributes.COMPONENT, value: "http")
                spanBuilder.setAttribute(key: Constants.Attributes.EVENT_TYPE, value: "fetch")
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
            instrumentationName: Constants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: Constants.Global.VERSION_STRING)
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
            logger.info("MiddlewareRum.setScreenName is not called from main thread: \(Thread.current.debugDescription)")
            return
        }
        setScreenNameInternal(name, true)
    }
    
    @objc public class func addSessionIdChangeCallback(_ callback: @escaping (() -> Void)) {
        addSessionIdCallback(callback)
    }
    
    public class func getOpenTelemetrySdk() -> OpenTelemetry {
        return OpenTelemetry.instance
    }
    
    
    /// Add a custom exception to RUM monitoring. This can be useful for tracking custom error handling in your application.
    /// NOTE : This event will be turned into a Span and sent to the RUM ingest along with other, auto-generated spans.
    /// - Parameter e: NSException associated with this event.
    @objc  public class func addException(e: NSException) {
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: Constants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: Constants.Global.VERSION_STRING)
        let now = Date()
        let typeName = e.name.rawValue
        let span = tracer.spanBuilder(spanName: typeName).setStartTime(time: now).startSpan()
        span.setAttribute(key: Constants.Attributes.COMPONENT, value: "error")
        span.setAttribute(key: Constants.Attributes.EVENT_TYPE, value: "error")
        span.setAttribute(key: Constants.Attributes.ERROR, value: true)
        span.setAttribute(key: Constants.Attributes.EXCEPTION_TYPE, value: typeName)
        if e.reason != nil {
            span.setAttribute(key: Constants.Attributes.EXCEPTION_MESSAGE, value: e.reason!)
        }
        let stack = e.callStackSymbols.joined(separator: "\n")
        if !stack.isEmpty {
            span.setAttribute(key: Constants.Attributes.EXCEPTION_STACKTRACE, value: stack)
        }
        span.addEvent(name: "exception")
        span.end(time: now)
    }
    
    
    /// Add a custom errors to RUM monitoring. This can be useful for tracking custom error handling in your application.
    /// NOTE: This event will be turned into a Span and sent to the RUM ingest along with other, auto-generated spans.
    /// - Parameter e: Error associated with this event.
    @objc public class func addError(e: Error) {
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: Constants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: Constants.Global.VERSION_STRING)
        let now = Date()
        let typeName = String(describing: type(of: e))
        let span = tracer.spanBuilder(spanName: typeName).setStartTime(time: now).startSpan()
        span.setAttribute(key: Constants.Attributes.COMPONENT, value: "error")
        span.setAttribute(key: Constants.Attributes.EVENT_TYPE, value: "error")
        span.setAttribute(key: Constants.Attributes.ERROR, value: true)
        span.setAttribute(key: Constants.Attributes.EXCEPTION_TYPE, value: typeName)
        span.setAttribute(key: Constants.Attributes.EXCEPTION_MESSAGE, value: e.localizedDescription)
        span.end(time: now)
    }
    
    
    /// Add a custom error to RUM monitoring. This can be useful for tracking custom error handling in your application.
    /// NOTE: This event will be turned into a Span and sent to the RUM ingest along with other, auto-generated spans.
    /// - Parameter e: String associated with this event.
    @objc public class func addError(_ e: String) {
        let tracer = OpenTelemetry.instance.tracerProvider.get(
            instrumentationName: Constants.Global.INSTRUMENTATION_NAME,
            instrumentationVersion: Constants.Global.VERSION_STRING)
        let now = Date()
        let typeName = "MiddlewareRum.addError(String)"
        let span = tracer.spanBuilder(spanName: typeName).setStartTime(time: now).startSpan()
        span.setAttribute(key: Constants.Attributes.COMPONENT, value: "error")
        span.setAttribute(key: Constants.Attributes.EVENT_TYPE, value: "error")
        span.setAttribute(key: Constants.Attributes.ERROR, value: true)
        span.setAttribute(key: Constants.Attributes.EXCEPTION_TYPE, value: "String")
        span.setAttribute(key: Constants.Attributes.EXCEPTION_MESSAGE, value: e)
        span.end(time: now)
    }
    
    @objc public class func integrateWebViewWithBrowserRum(view: WKWebView) {
#if os(iOS) || targetEnvironment(macCatalyst) || os(macOS)
        let webkit = WebViewInstrumentation(view: view)
        webkit.enable()
#else
        logger.info("MiddlewareRum: WebView Instrumentation is not supported in tvOS")
#endif
    }
    
    /// Send trace log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional dditional information with log
    public class func trace(_ message: Logging.Logger.Message, _ metadata: [String: Logging.Logger.MetadataValue]? = nil) {
        logger.trace(message, metadata: metadata ?? [:])
        MiddlewareRum.log(message: message, severity: .trace, metadata: metadata ?? [:])
    }
    
    /// Send info log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func info(_ message: Logging.Logger.Message, metadata: [String: Logging.Logger.MetadataValue]? = nil) {
        logger.info(message, metadata: metadata ?? [:])
        MiddlewareRum.log(message: message, severity: .info, metadata: metadata ?? [:])
    }
    
    /// Send error log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func error(_ message: Logging.Logger.Message, metadata: [String: Logging.Logger.MetadataValue]? = nil) {
        logger.error(message, metadata: metadata ?? [:])
        MiddlewareRum.log(message: message, severity: .error, metadata: metadata ?? [:])
    }
    
    /// Send info log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func debug(_ message: Logging.Logger.Message, metadata: [String: Logging.Logger.MetadataValue]? = nil) {
        logger.debug(message, metadata: metadata ?? [:])
        MiddlewareRum.log(message: message, severity: .debug, metadata: metadata ?? [:])
    }
    
    /// Send warning log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func warning(_ message: Logging.Logger.Message, metadata: [String: Logging.Logger.MetadataValue]? = nil) {
        logger.warning(message, metadata: metadata ?? [:])
        MiddlewareRum.log(message: message, severity: .warn, metadata: metadata ?? [:])
    }
    
    /// Send critical log message.
    /// - Parameters:
    ///   - message: message that you like to log
    ///   - metadata: optional additional information with log
    public class func crtical(_ message: Logging.Logger.Message, metadata: [String: Logging.Logger.MetadataValue]? = nil) {
        logger.critical(message, metadata: metadata ?? [:])
        MiddlewareRum.log(message: message, severity: .fatal, metadata: metadata ?? [:])
    }
    
    private class func log(message: Logging.Logger.Message, severity: Severity, metadata: [String: Logging.Logger.MetadataValue]) {
        var attribute: [String: AttributeValue] = [:]
        for (name, value) in metadata {
            attribute[name] = AttributeValue(value.description)
        }
        OpenTelemetry.instance.loggerProvider
            .get(instrumentationScopeName: Constants.Global.INSTRUMENTATION_NAME)
            .logRecordBuilder()
            .setSeverity(severity)
            .setBody(message.description)
            .setAttributes(attribute)
            .emit()
    }
}
