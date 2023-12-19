// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

struct BoolDecision: Decision {
    var isSampled: Bool
    var attributes: [String: AttributeValue] = [:]
}

class SessionBasedSampler: Sampler {
    
    var probability: Double = 1.0
    var upperBound: UInt32 = 0xFFFFFFFF
    var currentlySampled: Bool?
    var lock: NSLock = NSLock()
    
    init(ratio: Double) {
        probability = ratio
        upperBound = UInt32(floor(ratio * Double(upperBound)))
        observeSessionIdChange()
    }

    private func observeSessionIdChange() {
        addSessionIdCallback { [weak self] in
            self?.lock.withLock {
                self?.currentlySampled = self?.shouldSampleNewSession(sessionId: getRumSessionId())
            }
        }
    }
    func shouldSample(parentContext: OpenTelemetryApi.SpanContext?, traceId: OpenTelemetryApi.TraceId, name: String, kind: OpenTelemetryApi.SpanKind, attributes: [String : OpenTelemetryApi.AttributeValue], parentLinks: [OpenTelemetrySdk.SpanData.Link]) -> OpenTelemetrySdk.Decision {
        return lock.withLock({
            return self.getDecision()
        })
    }
    
    var description: String {
        return "SessionBasedSampler, Ratio: \(probability)"
    }

    private func getDecision() -> Decision {
        if let currentlySampled = self.currentlySampled {
            return BoolDecision(isSampled: currentlySampled)
        }

        let isSampled = self.shouldSampleNewSession(sessionId: getRumSessionId())
        self.currentlySampled = isSampled
        return BoolDecision(isSampled: isSampled)
    }
    
    private func shouldSampleNewSession(sessionId: String) -> Bool {
        var result = false

        switch probability {
        case 0.0:
            result = false
        case 1.0:
            result = true
        default:
            result = sessionIdValue(sessionId: sessionId) < self.upperBound
        }

        return result
    }
    
    func sessionIdValue(sessionId: String) -> UInt32 {
        if sessionId.count < 32 {
            return 0
        }

        var acc: UInt32 = 0

        for i in stride(from: 0, to: sessionId.count, by: 8) {
            let beginIndex = sessionId.index(sessionId.startIndex, offsetBy: i)
            let endIndex = sessionId.index(beginIndex, offsetBy: 8, limitedBy: sessionId.endIndex) ?? sessionId.endIndex
            let val = UInt32(sessionId[beginIndex ..< endIndex], radix: 16) ?? 0
            acc ^= val
        }

        return acc
    }
    
}
