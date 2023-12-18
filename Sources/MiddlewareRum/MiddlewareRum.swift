// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetrySdk
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import StdoutExporter

public class MiddlewareRum: NSObject {
    
    internal class func create(builder: MiddlewareRumBuilder) -> MiddlewareRum {
        
        let otlpTraceExporter = OtlpHttpTraceExporter(
            endpoint: URL(string: builder.target! + "/v1/traces")!,
            config: OtlpConfiguration(timeout: TimeInterval(10000),
                                      headers: [("Origin","sdk.middleware.io"),
                                                ("Content-Type", "application/json")]))
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderBuilder()
            .add(spanProcessor: SimpleSpanProcessor(spanExporter: MultiSpanExporter(spanExporters: [StdoutExporter(), otlpTraceExporter])))
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
        return MiddlewareRum()
    }
    
}
