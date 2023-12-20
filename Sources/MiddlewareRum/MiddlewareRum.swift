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

var middlewareRumInitTime = Date()
var globalAttributes: [String: Any] = [:]
let globalAttributesLock = NSLock()

public class MiddlewareRum: NSObject {
    
    internal class func create(builder: MiddlewareRumBuilder) -> Bool {
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
            .with(resource: createMiddlewareResource(builder: builder))
            .with(sampler: SessionBasedSampler(ratio: builder.sessionSamplingRatio))
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
        OpenTelemetry.registerMeterProvider(meterProvider:
                                                MeterProviderSdk(
                                                    metricProcessor: MetricProcessorSdk(),
                                                    metricExporter: otlpMetricExporter,
                                                    metricPushInterval: 10000,
                                                    resource: createMiddlewareResource(builder: builder)))
        
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
        let mwInit = tracer
            .spanBuilder(spanName: "Middleware.initialize")
            .setStartTime(time: middlewareRumInitTime)
            .startSpan()
        
        setGlobalAttributes(builder.globalAttributes!)
        if(builder.deploymentEnvironment != nil) {
            setGlobalAttributes(["environment": builder.deploymentEnvironment!])
        }
        
        if(builder.isNetworkMonitoringEnabled()) {
            _ = initializeNetworkMonitoring()
        }
        
        if(builder.isSlowRenderingDetectionEnabled()) {
            _ = SlowRenderingDetector(configuration: SlowRenderingConfiguration(slowFrameThreshold: builder.slowFrameDetectionThresholdMs, frozenFrameThreshold: builder.frozenFrameDetectionThresholdMs))
        }
        
        initializeNetworkTypeMonitoring()
        
        if(builder.isAppLifecycleInstrumentationEnabled()) {
            _ = AppLifecycleInstrumentation()
        }
//        
//        if(builder.isCrashReportingEnabled()) {
//            installCrashReportingInstrumentation()
//        }
        
        mwInit.end()
        
        return true
    }
    
    public class func setGlobalAttributes(_ attributes: [String: Any]) {
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
            "service.name" : AttributeValue(builder.serviceName!),
            "browser.trace" : AttributeValue(true),
            "browser.mobile" : AttributeValue(true),
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
            }))
    }
    
    class func initializeNetworkTypeMonitoring() {
        do{
            let _ = try NetworkStatus()
        } catch {
            print("Middleware: Failed to initialize network type detection")
        }
        
    }
    
    public class func addEvent(name: String, attributes: NSDictionary) {
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
    
    
    /**
     * Get the Middleware Session ID associated with this instance of the RUM instrumentation library.
     * Note: this value can change throughout the lifetime of an application instance, so it is
     * recommended that you do not cache this value, but always retrieve it from here when needed.
     */
    public class func getSessionId() -> String {
        return getRumSessionId()
    }
    
    public class func addSessionIdChangeCallback(_ callback: @escaping (() -> Void)) {
        addSessionIdCallback(callback)
    }
    
    public class func getOpenTelemetrySdk() -> OpenTelemetry {
        return OpenTelemetry.instance
    }
    
    /**
     * Add a custom exception to RUM monitoring. This can be useful for tracking custom error
     * handling in your application.
     *
     * <p>This event will be turned into a Span and sent to the RUM ingest along with other,
     * auto-generated spans.
     *
     * @param {NSException} associated with this event.
     */
    public class func addException(e: NSException) {
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
    
    /**
     * Add a custom errors to RUM monitoring. This can be useful for tracking custom error
     * handling in your application.
     *
     * <p>This event will be turned into a Span and sent to the RUM ingest along with other,
     * auto-generated spans.
     *
     * @param {Error} associated with this event.
     */
    public class func addError(e: Error) {
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
    
    /**
     * Add a custom error to RUM monitoring. This can be useful for tracking custom error
     * handling in your application.
     *
     * <p>This event will be turned into a Span and sent to the RUM ingest along with other,
     * auto-generated spans.
     *
     * @param {String} associated with this event.
     */
    public class func addError(e: String) {
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
    
    public func startCrashReporting() {
        installCrashReportingInstrumentation()
    }
}
