// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(macOS)
import Foundation
import WebKit

class WebViewInstrumentation {
    private weak var view: WKWebView?
    private var installedScript: WKUserScript?

    init(view: WKWebView) {
        self.view = view
    }

    func enable() {
        runOnMain {
            let sessionId = getRumSessionId()
            self.installUserScript(sessionId: sessionId)
            // Best effort for a page that is already loaded; agent-browser reads
            // the id live per span, so spans converge onto the native id.
            self.view?.evaluateJavaScript(Self.bridgeSource(sessionId: sessionId), completionHandler: nil)
        }
        addSessionIdCallback { [self] in
            DispatchQueue.main.async {
                guard self.view != nil else { return }
                let newSessionId = getRumSessionId()
                self.installUserScript(sessionId: newSessionId)
                self.view?.evaluateJavaScript(
                    "window.__mwNativeSessionId = '\(newSessionId)';", completionHandler: nil)
            }
        }
    }

    // Session ids are 32 lowercase hex chars (generateNewSessionId) — safe to interpolate.
    static func bridgeSource(sessionId: String) -> String {
        """
        window.__mwNativeSessionId = '\(sessionId)';
        window.MiddlewareNative = window.MiddlewareNative || {};
        window.MiddlewareNative.getNativeSessionId = function() {
            return window.__mwNativeSessionId;
        };
        """
    }

    private func installUserScript(sessionId: String) {
        guard let controller = view?.configuration.userContentController else { return }
        let script = WKUserScript(source: Self.bridgeSource(sessionId: sessionId),
                                  injectionTime: .atDocumentStart,
                                  forMainFrameOnly: false)
        let preserved = controller.userScripts.filter { $0 !== installedScript }
        controller.removeAllUserScripts()
        preserved.forEach { controller.addUserScript($0) }
        controller.addUserScript(script)
        installedScript = script
    }

    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
#endif
