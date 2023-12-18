// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import StdoutExporter

var middlewareRumInitTime = Date()
var globalAttributes: [String: Any] = [:]
let globalAttributesLock = NSLock()

public class MiddlewareRum: NSObject {
    
    internal class func create(builder: MiddlewareRumBuilder) -> MiddlewareRum {
        
        middlewareRumInitTime = Date()
        let otlpTraceExporter = OtlpHttpTraceExporter(
            endpoint: URL(string: builder.target! + "/v1/traces")!,
            config: OtlpConfiguration(timeout: TimeInterval(10000),
                                      headers: [("Origin","sdk.middleware.io"),
                                                ("Content-Type", "application/json")]))
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()

            .add(spanProcessors: [
                GlobalAttributesProcessor(),
                SimpleSpanProcessor(spanExporter: MultiSpanExporter(spanExporters: [StdoutExporter(), otlpTraceExporter]))])
            .build())
        
        
        let otlpMetricExporter = OtlpHttpMetricExporter(
            endpoint: URL(string: builder.target! + "/v1/metrics")!,
            config: OtlpConfiguration(timeout: TimeInterval(10000),
                                      headers: [("Origin", "sdk.middleware.io"),
                                                ("Content-Type", "application/json")]))
        OpenTelemetry.registerMeterProvider(meterProvider:
                                                MeterProviderSdk(metricProcessor: MetricProcessorSdk(), metricExporter: otlpMetricExporter))
        
        let otlpLogExporter = OtlpHttpLogExporter(
            endpoint: URL(string: builder.target! + "/v1/logs")!,
            config:  OtlpConfiguration(timeout: TimeInterval(10000),
                                       headers:[("Origin", "sdk.middleware.io"),                    ("Content-Type", "application/json")]))
        OpenTelemetry.registerLoggerProvider(loggerProvider: LoggerProviderBuilder()
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
        mwInit.end()
        return MiddlewareRum()
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
    
}
