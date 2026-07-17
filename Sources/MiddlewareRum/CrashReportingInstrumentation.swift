// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import CrashReporter
#if !os(macOS)
import DeviceKit
#endif

private var ogCrashReporter: PLCrashReporter?
private var customDataDictionary: [String: String] = [String: String]()

class CrashReportingInstrumentation {
    
    func start() {
        let configuration = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: PLCrashReporterSymbolicationStrategy(rawValue: 0))
        
        let crashReporter = PLCrashReporter(configuration: configuration)
        
        if crashReporter == nil {
            Log.error("MiddlewareRum: Failed to initialize crash reporting instrumentation.")
            return
        }
        
        guard let _ = crashReporter?.enable() else {
            Log.error("MiddlewareRum: Failed to enable crash reporting instrumentation.")
            return
        }
        ogCrashReporter = crashReporter
        Log.debug("MiddlewareRum: Enabled crash reporting instrumentation.")
        setSessionId()
        setDeviceStats()
        startPollingForDeviceStats()
        if(!crashReporter!.hasPendingCrashReport()) {
            return
        }
        setPendingCrashReport()
        crashReporter?.purgePendingCrashReport()
    }
    
    private func startPollingForDeviceStats() {
        let repeatSeconds: Double = 5
        DispatchQueue.global(qos: .background).async {
            let timer = Timer.scheduledTimer(withTimeInterval: repeatSeconds, repeats: true) { _ in
                self.setDeviceStats()
            }
            timer.fire()
        }
    }
    
    private func setSessionId() {
        do {
            customDataDictionary["sessionId"] = getRumSessionId()
            let customData = try NSKeyedArchiver.archivedData(withRootObject: customDataDictionary, requiringSecureCoding: false)
            ogCrashReporter?.customData = customData
        } catch {
            Log.debug("MiddlewareRum: Failed to add sessionId to crash report.")
        }
        
    }
    
    private func setDeviceStats() {
        do {
            customDataDictionary["batteryLevel"] = DeviceStats.batteryLevel
            customDataDictionary["freeDiskSpace"] = DeviceStats.freeDiskSpace
            customDataDictionary["freeMemory"] = DeviceStats.freeMemory
            let customData = try NSKeyedArchiver.archivedData(withRootObject: customDataDictionary, requiringSecureCoding: false)
            ogCrashReporter?.customData = customData
        } catch {
            Log.error("MiddlewareRum: Failed to add device stats to crash report.")
        }
    }
    
    private func setPendingCrashReport() {
        do {
            let data = ogCrashReporter?.loadPendingCrashReportData()
            try sendingCrashReport(data)
        } catch {
            Log.error("MiddlewareRum: Failed to send crash report.")
        }
    }
    
    
    private func sendingCrashReport(_ data: Data!) throws {
        Log.debug("MiddlewareRum: Loading crash report size \(data?.count as Any)")
        
        let report = try PLCrashReport(data: data)

        // Signal crashes (e.g. SIGSEGV from rumCrashApp) have signalInfo only.
        // NSException / ObjC throws also populate exceptionInfo.
        var exceptionType = report.signalInfo?.name ?? "exception"
        var exceptionMessage: String?
        if report.hasExceptionInfo {
            if let name = report.exceptionInfo.exceptionName, !name.isEmpty {
                exceptionType = name
            }
            if let reason = report.exceptionInfo.exceptionReason, !reason.isEmpty {
                exceptionMessage = reason
            }
        }
        if exceptionMessage == nil, let signal = report.signalInfo {
            // Synthesize a message for pure signal crashes so exception.message is never empty
            let code = signal.code ?? ""
            exceptionMessage = code.isEmpty
                ? "App terminated with \(signal.name ?? "signal") at \(signal.address)"
                : "App terminated with \(signal.name ?? "signal") (\(code)) at \(signal.address)"
        }

        var exceptionStacktrace: String?
        for case let thread as PLCrashReportThreadInfo in report.threads where thread.crashed {
            exceptionStacktrace = crashedThreadToStack(report: report, thread: thread)
            break
        }

        let now = Date()
        let span = tracer().spanBuilder(spanName: exceptionType).setStartTime(time: now).startSpan()
        span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "crash")
        span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "error")
        span.setAttribute(key: MiddlewareConstants.Attributes.ERROR, value: true)

        // Mirror MiddlewareRum.addException / Android CrashAttributesExtractor:
        // put exception.* on the SPAN so RUM queries for exception.* resolve.
        span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_TYPE, value: exceptionType)
        if let exceptionMessage {
            span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_MESSAGE, value: exceptionMessage)
        }
        if let exceptionStacktrace, !exceptionStacktrace.isEmpty {
            span.setAttribute(key: MiddlewareConstants.Attributes.EXCEPTION_STACKTRACE, value: exceptionStacktrace)
        }
        span.setAttribute(key: "exception.framework", value: "ios")

        if let customDataBytes = report.customData {
            let customData = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSDictionary.self,
                from: customDataBytes
            ) as? [String: String]
            if let customData {
                if let sessionId = customData["sessionId"] {
                    span.setAttribute(key: "crash.rumSessionId", value: sessionId)
                }
                if let batteryLevel = customData["batteryLevel"] {
                    span.setAttribute(key: "crash.batteryLevel", value: batteryLevel)
                }
                if let freeDiskSpace = customData["freeDiskSpace"] {
                    span.setAttribute(key: "crash.freeDiskSpace", value: freeDiskSpace)
                }
                if let freeMemory = customData["freeMemory"] {
                    span.setAttribute(key: "crash.freeMemory", value: freeMemory)
                }
            } else {
                span.setAttribute(key: "crash.rumSessionId", value: String(decoding: customDataBytes, as: UTF8.self))
            }
        }
        span.setAttribute(key: "crash.app.version", value: report.applicationInfo.applicationMarketingVersion)
#if !os(macOS)
        span.setAttribute(key: MiddlewareConstants.Attributes.DEVICE_MODEL_NAME, value: DeviceKit.Device.current.description)
#else
        span.setAttribute(key: MiddlewareConstants.Attributes.DEVICE_MODEL_NAME, value: Device.current.model)
#endif

        if let signal = report.signalInfo {
            span.setAttribute(key: "crash.address", value: signal.address.description)
            if let signalName = signal.name {
                span.setAttribute(key: "crash.signal", value: signalName)
            }
        }

        // Keep event-level attributes for backwards compatibility, using non-optional AttributeValue
        var exceptionAttributes = [String: AttributeValue]()
        exceptionAttributes[MiddlewareConstants.Attributes.EXCEPTION_TYPE] = AttributeValue(exceptionType)
        if let exceptionMessage {
            exceptionAttributes[MiddlewareConstants.Attributes.EXCEPTION_MESSAGE] = AttributeValue(exceptionMessage)
        }
        if let exceptionStacktrace, !exceptionStacktrace.isEmpty {
            exceptionAttributes[MiddlewareConstants.Attributes.EXCEPTION_STACKTRACE] = AttributeValue(exceptionStacktrace)
        }
        span.addEvent(name: "exception", attributes: exceptionAttributes, timestamp: report.systemInfo.timestamp)
        span.addEvent(name: "crash.timestamp", attributes: exceptionAttributes, timestamp: report.systemInfo.timestamp)
        span.end(time: now)

        // Crash spans are emitted on next launch; flush immediately so BatchSpanProcessor
        // does not delay OTLP export of exception.* attributes.
        if let provider = OpenTelemetry.instance.tracerProvider as? TracerProviderSdk {
            provider.forceFlush(timeout: 5)
        }

        Log.debug("MiddlewareRum: Crash span exported type=\(exceptionType) message=\(exceptionMessage ?? "")")
    }
    
    func crashedThreadToStack(report: PLCrashReport, thread: PLCrashReportThreadInfo) -> String {
        let text = NSMutableString()
        text.appendFormat("Thread %ld", thread.threadNumber)
        var frameNum = 0
        while frameNum < thread.stackFrames.count {
            let str = formatStackFrame(
                frame: thread.stackFrames[frameNum] as! PLCrashReportStackFrameInfo,
                frameNum: frameNum,
                report: report)
            text.append(str)
            text.append("\n")
            frameNum += 1
        }
        return String(text)
    }
    
    func formatStackFrame(frame: PLCrashReportStackFrameInfo, frameNum: Int, report: PLCrashReport) -> String {
        var baseAddress: UInt64 = 0
        var pcOffset: UInt64 = 0
        var imageName = "???"
        var symbolString: String?
        let imageInfo = report.image(forAddress: frame.instructionPointer)
        if imageInfo != nil {
            imageName = imageInfo!.imageName
            imageName = URL(fileURLWithPath: imageName).lastPathComponent
            baseAddress = imageInfo!.imageBaseAddress
            pcOffset = frame.instructionPointer - imageInfo!.imageBaseAddress
        }
        if frame.symbolInfo != nil {
            let symbolName = frame.symbolInfo.symbolName
            let symOffset = frame.instructionPointer - frame.symbolInfo.startAddress
            symbolString =  String(format: "%@ + %ld", symbolName!, symOffset)
        } else {
            symbolString = String(format: "0x%lx + %ld", baseAddress, pcOffset)
        }
        return String(format: "%-4ld%-35@ 0x%016lx %@", frameNum, imageName, frame.instructionPointer, symbolString!)
    }
}
