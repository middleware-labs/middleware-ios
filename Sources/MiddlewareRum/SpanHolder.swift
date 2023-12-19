// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import OpenTelemetryApi

class SpanHolder: NSObject {
    let span: Span
    init(_ span: Span) {
        self.span = span
    }
}

