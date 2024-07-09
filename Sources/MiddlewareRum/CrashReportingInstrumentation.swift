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
        var exceptionType = report.signalInfo.name
        if(report.hasExceptionInfo) {
            exceptionType = report.exceptionInfo.exceptionName
        }
        
        let now = Date()
        let span = tracer().spanBuilder(spanName: exceptionType ?? "exception").setStartTime(time: now).startSpan()
        span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "crash")
        span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "error")
        if(report.customData != nil ) {
            let customData = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self, from: report.customData) as? [String: String]
            if(customData != nil) {
                span.setAttribute(key: "crash.rumSessionId", value: customData!["sessionId"]!)
                span.setAttribute(key: "crash.batteryLevel", value: customData!["batteryLevel"]!)
                span.setAttribute(key: "crash.freeDiskSpace", value: customData!["freeDiskSpace"]!)
                span.setAttribute(key: "crash.freeMemory", value: customData!["freeMemory"]!)
            } else {
                span.setAttribute(key: "crash.rumSessionId", value: String(decoding: report.customData, as: UTF8.self))
            }
        }
        span.setAttribute(key: "crash.app.version", value: report.applicationInfo.applicationMarketingVersion)
        span.setAttribute(key: "error", value: true)
        var exceptionAttributes = [String: AttributeValue]()
#if !os(macOS)
        span.setAttribute(key: MiddlewareConstants.Attributes.DEVICE_MODEL_NAME, value: DeviceKit.Device.current.description)
#else
        span.setAttribute(key: MiddlewareConstants.Attributes.DEVICE_MODEL_NAME, value: Device.current.model)
#endif
        
        exceptionAttributes["exception.type"] = AttributeValue(exceptionType ?? "unknown")
        span.setAttribute(key: "crash.address", value: report.signalInfo.address.description)
        for case let thread as PLCrashReportThreadInfo in report.threads where thread.crashed {
            exceptionAttributes["exception.stacktrace"] = AttributeValue(crashedThreadToStack(report: report, thread: thread))
            break
        }
        if report.hasExceptionInfo {
            if(report.exceptionInfo.exceptionName != nil) {
                exceptionAttributes["exception.type"] = AttributeValue(report.exceptionInfo.exceptionName as Any)
            }
            if(report.exceptionInfo.exceptionReason != nil) {
                exceptionAttributes["exception.message"] = AttributeValue(report.exceptionInfo.exceptionReason as Any)
            }
        }
        span.addEvent(name: "crash.timestamp", attributes: exceptionAttributes, timestamp: report.systemInfo.timestamp)
        span.end(time: now)
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
