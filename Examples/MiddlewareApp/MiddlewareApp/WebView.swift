// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

import Foundation
import SwiftUI
import WebKit
import MiddlewareRum

struct WebView: UIViewRepresentable {

    func makeUIView(context: Context) -> some UIView {
        let webView = WKWebView()
        let request = URLRequest(url:  URL(string: "https://middleware.io")!)
        MiddlewareRum.integrateWebViewWithBrowserRum(view: webView)
        webView.load(request)
        MiddlewareRum.info("Loaded WebView")
        return webView
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
    }
}

#Preview {
    WebView()
}
