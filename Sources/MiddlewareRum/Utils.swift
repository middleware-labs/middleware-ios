// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation

func isUsefulString(_ s: String?) -> Bool {
    return s != nil && !s!.isEmpty
}

func nop() {
        // "default label in a switch should have at least one executable statement"
}

func tracer() -> Tracer {
    return OpenTelemetry.instance.tracerProvider
        .get(instrumentationName: MiddlewareConstants.Global.INSTRUMENTATION_NAME, instrumentationVersion: MiddlewareConstants.Global.VERSION_STRING)
}

func loggerBuilder () -> LoggerBuilder {
    return OpenTelemetry.instance.loggerProvider.loggerBuilder(instrumentationScopeName: MiddlewareConstants.Global.INSTRUMENTATION_NAME)
}

private func attributeValueToAny(_ value: AttributeValue) -> Any {
    switch value {
    case .string(let v): return v
    case .bool(let v): return v
    case .int(let v): return v
    case .double(let v): return v
    case .stringArray(let v): return v
    case .boolArray(let v): return v
    case .intArray(let v): return v
    case .doubleArray(let v): return v
    case .set(let v):
        return v.labels.mapValues { attributeValueToAny($0) }
    }
}

func getAppVersion() -> String? {
    let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    let bundleShortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    return bundleShortVersion ?? bundleVersion
}

func convertAttributesToJson(_ attributes: [String: AttributeValue]) -> String? {
    let jsonObject = attributes.mapValues { attributeValueToAny($0) }

    guard JSONSerialization.isValidJSONObject(jsonObject) else {
        return nil
    }

    do {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}
