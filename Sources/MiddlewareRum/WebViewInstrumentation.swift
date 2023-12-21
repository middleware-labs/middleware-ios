// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import WebKit

class WebViewInstrumentation {
    let view: WKWebView
    var sessionId: String
    init(view: WKWebView) {
        self.view = view
        self.sessionId = getRumSessionId()
    }
    
    func enable(){
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let js = """
            document.cookie = "".concat('mwRumSessionId', '=').concat('\(sessionId)').concat('-').concat('\(now)', '; path=/');
        """
        view.evaluateJavaScript(js)
    }
}
