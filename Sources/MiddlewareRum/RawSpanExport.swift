// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

/// Set once by MiddlewareRum.create() so externally-produced spans can ride
/// the SDK's OTLP trace pipeline.
var rawSpanExporter: SpanExporter?

extension MiddlewareRum {

    /// Exports spans produced by an external OpenTelemetry implementation
    /// (e.g. the Middleware React Native SDK's JS tracer) through this SDK's
    /// OTLP trace pipeline.
    ///
    /// Each dictionary matches middleware-react-native's `toNativeSpan()`
    /// shape: `name`, `kind` (OTel-JS Int: 0 internal / 1 server / 2 client /
    /// 3 producer / 4 consumer), `startTime`/`endTime` (nanoseconds since
    /// epoch), `traceId`/`spanId`/`parentSpanId` (hex), `attributes`,
    /// `events` `[{name, time, attributes}]`, and optional `resource`.
    ///
    /// The exported resource is the SDK's live resource overlaid with the
    /// dictionary's `resource` entries; `session.id` and `session.start_time`
    /// are always forced from the native session so streams stay linked.
    /// Spans are exported unconditionally (not subject to session sampling).
    ///
    /// - Returns: true when the batch was handed to the exporter.
    @objc public class func exportRawSpans(_ spans: [[String: Any]]) -> Bool {
        guard let exporter = rawSpanExporter else {
            Log.debug("MiddlewareRum: exportRawSpans called before initialization")
            return false
        }
        let spanData = spans.map { rawSpanToSpanData($0) }
        return exporter.export(spans: spanData) == .success
    }

    private class func rawSpanToSpanData(_ raw: [String: Any]) -> SpanData {
        let traceId = raw["traceId"] as? String ?? "00000000000000000000000000000000"
        let spanIdHex = raw["spanId"] as? String ?? "0000000000000000"
        let parentIdHex = raw["parentSpanId"] as? String

        var span = SpanData(
            traceId: TraceId(fromHexString: traceId),
            spanId: SpanId(id: UInt64(spanIdHex, radix: 16) ?? 0),
            name: raw["name"] as? String ?? "unknown",
            kind: rawSpanKind(raw["kind"] as? Int ?? 0),
            startTime: rawSpanTimestamp(raw["startTime"]),
            endTime: rawSpanTimestamp(raw["endTime"])
        )
        if let parentIdHex = parentIdHex, let parentId = UInt64(parentIdHex, radix: 16), parentId != 0 {
            span.settingParentSpanId(SpanId(id: parentId))
        }

        let attributes = rawSpanAttributes(raw["attributes"] as? [String: Any] ?? [:])
        span.settingAttributes(attributes)
        span.settingTotalAttributeCount(attributes.count)

        let events = (raw["events"] as? [[String: Any]] ?? []).compactMap { event -> SpanData.Event? in
            guard let name = event["name"] as? String else { return nil }
            return SpanData.Event(
                name: name,
                timestamp: rawSpanTimestamp(event["time"]),
                attributes: rawSpanAttributes(event["attributes"] as? [String: Any] ?? [:]))
        }
        span.settingEvents(events)
        span.settingTotalRecordedEvents(events.count)

        span.settingResource(rawSpanResource(raw["resource"] as? [String: Any]))
        span.settingTraceFlags(TraceFlags(fromByte: 1))
        span.settingHasEnded(true)
        return span
    }

    /// The SDK's live resource overlaid with the JS span's resource entries;
    /// the native session id/start time always win so streams stay linked.
    private class func rawSpanResource(_ jsResource: [String: Any]?) -> Resource {
        var resource = OpenTelemetry.instance.tracerProvider.getActiveResource()
        if let jsResource = jsResource {
            for (key, value) in rawSpanAttributes(jsResource) {
                resource.attributes[key] = value
            }
        }
        resource.attributes[MiddlewareConstants.Attributes.SESSION_ID] = AttributeValue(getRumSessionId())
        resource.attributes[MiddlewareConstants.Attributes.SESSION_START_TIME] = AttributeValue(getSessionStartTime())
        return resource
    }

    private class func rawSpanAttributes(_ dictionary: [String: Any]) -> [String: AttributeValue] {
        var attributes: [String: AttributeValue] = [:]
        for (key, value) in dictionary {
            if let string = value as? String {
                attributes[key] = AttributeValue.string(string)
            } else if let number = value as? NSNumber {
                // NSNumber bridges 0/1 integers to Bool too — check the
                // underlying CF type so numeric attributes stay numeric.
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    attributes[key] = AttributeValue.bool(number.boolValue)
                } else if CFNumberIsFloatType(number) {
                    attributes[key] = AttributeValue.double(number.doubleValue)
                } else {
                    attributes[key] = AttributeValue.int(number.intValue)
                }
            }
        }
        return attributes
    }

    /// OTel-JS SpanKind values: 0 internal, 1 server, 2 client, 3 producer,
    /// 4 consumer. (The old RN fork mapped 1/2 and 3/4 backwards.)
    private class func rawSpanKind(_ kind: Int) -> SpanKind {
        switch kind {
        case 1: return .server
        case 2: return .client
        case 3: return .producer
        case 4: return .consumer
        default: return .internal
        }
    }

    private class func rawSpanTimestamp(_ value: Any?) -> Date {
        switch value {
        case let double as Double:
            return Date(timeIntervalSince1970: double / 1e9)
        case let int as Int:
            return Date(timeIntervalSince1970: Double(int) / 1e9)
        case let string as String:
            return Date(timeIntervalSince1970: (Double(string) ?? 0) / 1e9)
        default:
            return Date()
        }
    }
}
