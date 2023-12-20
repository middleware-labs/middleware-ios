// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import CrashReporter

private var customDataDictionary: [String: String] = [String: String]()
private var tracer = OpenTelemetry.instance.tracerProvider.get(
    instrumentationName: Constants.Global.INSTRUMENTATION_NAME,
    instrumentationVersion: Constants.Global.VERSION_STRING)

func handleUncaughtException(e: NSException) {
    let existingHandler = NSGetUncaughtExceptionHandler()
    if let existingHandler = existingHandler {
        existingHandler(e)
    }
    reportCrash(e: e)
}

func reportCrash(e: NSException) {
    MiddlewareRum.addException(e: e)
}

func installCrashReportingInstrumentation() {
    let configuration = PLCrashReporterConfig(signalHandlerType: .BSD, symbolicationStrategy: PLCrashReporterSymbolicationStrategy(rawValue: 0))
    
    let crashReporter = PLCrashReporter(configuration: configuration)
    
    if crashReporter == nil {
        print("MiddlewareRum: Failed to initialize crash reporting instrumentation.")
        return
    }
    
    guard let _ = crashReporter?.enable() else {
        print("MiddlewareRum: Failed to enable crash reporting instrumentation.")
        return
    }
    
    print("MiddlewareRum: Enabled crash reporting instrumentation.")
    setSessionId(crashReporter!)
    setDeviceStats(crashReporter!)
    startPollingForDeviceStats(crashReporter!)
    MiddlewareRum.addSessionIdChangeCallback {
        setSessionId(crashReporter!)
    }
    if(crashReporter!.hasPendingCrashReport()) {
        return
    }
    setPendingCrashReport(crashReporter: crashReporter!)
    
}

private func startPollingForDeviceStats(_ crashReporter: PLCrashReporter) {
    let repeatSeconds: Double = 5
    DispatchQueue.global(qos: .background).async {
        let timer = Timer.scheduledTimer(withTimeInterval: repeatSeconds, repeats: true) { _ in
            setDeviceStats(crashReporter)
        }
        timer.fire()
    }
}

private func setSessionId(_ crashReporter: PLCrashReporter) {
    do {
        customDataDictionary["sessionId"] = getRumSessionId()
        let customData = try NSKeyedArchiver.archivedData(withRootObject: customDataDictionary, requiringSecureCoding: false)
        crashReporter.customData = customData
    } catch {
        print("MiddlewareRum: Failed to add sessionId to crash report.")
    }
    
}

private func setDeviceStats(_ crashReporter: PLCrashReporter) {
    do {
        customDataDictionary["batteryLevel"] = DeviceStats.batteryLevel
        customDataDictionary["freeDiskSpace"] = DeviceStats.freeDiskSpace
        customDataDictionary["freeMemory"] = DeviceStats.freeMemory
        let customData = try NSKeyedArchiver.archivedData(withRootObject: customDataDictionary, requiringSecureCoding: false)
        crashReporter.customData = customData
    } catch {
        print("MiddlewareRum: Failed to add device stats to crash report.")
    }
}

private func setPendingCrashReport(crashReporter: PLCrashReporter) {
    do {
        let data = crashReporter.loadPendingCrashReportData()
        try sendingCrashReport(data)
    } catch {
        print("MiddlewareRum: Failed to send crash report.")
    }
    crashReporter.purgePendingCrashReport()
}


private func sendingCrashReport(_ data: Data!) throws {
    print("MiddlewareRum: Loading crash report size \(data?.count as Any)")
    
    let report = try PLCrashReport(data: data)
    var exceptionType = report.signalInfo.name
    if(report.hasExceptionInfo) {
        exceptionType = report.exceptionInfo.exceptionName
    }
    
    let now = Date()
    let span = tracer.spanBuilder(spanName: exceptionType ?? "exception").setStartTime(time: now).setNoParent().startSpan()
    span.setAttribute(key: Constants.Attributes.COMPONENT, value: "crash")
    span.setAttribute(key: Constants.Attributes.EVENT_TYPE, value: "error")
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
    span.addEvent(name: "crash.timestamp", timestamp: report.systemInfo.timestamp)
    span.setAttribute(key: "exception.type", value: exceptionType ?? "unknown")
    span.setAttribute(key: "crash.address", value: report.signalInfo.address.description)
    for case let thread as PLCrashReportThreadInfo in report.threads where thread.crashed {
        span.setAttribute(key: "exception.stacktrace", value: crashedThreadToStack(report: report, thread: thread))
        break
    }
    if report.hasExceptionInfo {
        span.setAttribute(key: "exception.type", value: report.exceptionInfo.exceptionName)
        span.setAttribute(key: "exception.message", value: report.exceptionInfo.exceptionReason)
    }
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

