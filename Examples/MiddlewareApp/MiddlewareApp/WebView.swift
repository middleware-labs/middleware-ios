// Copyright © 2024 Middleware. Licensed under the Apache License, Version 2.0
// CoffeeCart iOS — Help WebView: setScreenName, integrateWebViewWithBrowserRum, load middleware.io.

import Foundation
import SwiftUI
import WebKit
import MiddlewareRum

struct HelpWebView: UIViewRepresentable {

    func makeUIView(context: Context) -> WKWebView {
        MiddlewareRum.setScreenName("Help")
        MiddlewareRum.info("HelpWebView: loading middleware.io")

        let webView = WKWebView()
        MiddlewareRum.integrateWebViewWithBrowserRum(view: webView)

        let request = URLRequest(url: URL(string: "https://middleware.io")!)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - SwiftUI Wrapper for navigation

struct HelpScreen: View {
    var body: some View {
        HelpWebView()
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Help & FAQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

// Keep old WebView name as a typealias so existing project references still compile if any
typealias WebView = HelpScreen

#Preview {
    NavigationStack {
        HelpScreen()
    }
}
