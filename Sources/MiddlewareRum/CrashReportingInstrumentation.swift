// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk


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
    NSSetUncaughtExceptionHandler { exception in
        print("Uncaught exception: \(exception)")
        handleUncaughtException(e: exception)
    }
}
