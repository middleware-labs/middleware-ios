// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS)
import XCTest
import WebKit
@testable import MiddlewareRum

class WebViewInstrumentationTests: XCTestCase {

    // Session rotation emits a session.id.change span via the active tracer
    // provider; the API-default provider has no getActiveResource, so register
    // a real SDK provider once for the whole test process.
    override class func setUp() {
        super.setUp()
        OpenTelemetry.registerTracerProvider(tracerProvider: TracerProviderSdk())
    }

    private func drainMainQueue() {
        let expectation = expectation(description: "main queue drained")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 5)
    }

    private func bridgeScripts(in webView: WKWebView) -> [WKUserScript] {
        webView.configuration.userContentController.userScripts.filter {
            $0.source.contains("window.MiddlewareNative")
        }
    }

    func testEnableInstallsBridgeUserScript() {
        let webView = WKWebView()
        WebViewInstrumentation(view: webView).enable()
        drainMainQueue()

        let scripts = bridgeScripts(in: webView)
        XCTAssertEqual(scripts.count, 1)
        XCTAssertEqual(scripts[0].injectionTime, .atDocumentStart)
        XCTAssertFalse(scripts[0].isForMainFrameOnly)
        XCTAssertTrue(scripts[0].source.contains(getRumSessionId()))
    }

    func testSessionRotationReplacesScriptAndPreservesOthers() {
        let webView = WKWebView()
        let customerScript = WKUserScript(source: "window.__customer = true;",
                                          injectionTime: .atDocumentStart,
                                          forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(customerScript)
        WebViewInstrumentation(view: webView).enable()
        drainMainQueue()
        let oldSessionId = getRumSessionId()

        let newSessionId = getRumSessionId(forceNewSessionId: true)
        drainMainQueue()

        let controller = webView.configuration.userContentController
        XCTAssertTrue(controller.userScripts.contains { $0.source.contains("window.__customer") })
        let scripts = bridgeScripts(in: webView)
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].source.contains(newSessionId))
        XCTAssertFalse(scripts[0].source.contains(oldSessionId))
    }

    func testBridgeAnswersInLoadedPage() {
        let webView = WKWebView()
        WebViewInstrumentation(view: webView).enable()
        drainMainQueue()

        let navigationDelegate = NavigationExpectation()
        navigationDelegate.expectation = expectation(description: "page loaded")
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
        wait(for: [navigationDelegate.expectation!], timeout: 10)

        let jsExpectation = expectation(description: "js evaluated")
        webView.evaluateJavaScript("window.MiddlewareNative.getNativeSessionId()") { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result as? String, getRumSessionId())
            jsExpectation.fulfill()
        }
        wait(for: [jsExpectation], timeout: 10)
    }

    func testIntegrateTwiceIsIdempotent() {
        let webView = WKWebView()
        MiddlewareRum.integrateWebViewWithBrowserRum(view: webView)
        MiddlewareRum.integrateWebViewWithBrowserRum(view: webView)
        drainMainQueue()

        XCTAssertEqual(bridgeScripts(in: webView).count, 1)
    }
}

private class NavigationExpectation: NSObject, WKNavigationDelegate {
    var expectation: XCTestExpectation?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        expectation?.fulfill()
    }
}
#endif
