// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

/// Capture trigger for v3 session recording: observes every layout pass by
/// swizzling `UIView.layoutSublayers(of:)` and invokes a throttled callback on
/// the main thread. Static screens therefore cost nothing — captures happen
/// only when something actually changes on screen.
///
/// The swizzle is installed once per process and never removed; start/stop
/// cycles only toggle `isEnabled` (removing a swizzle races with other hooks).
class ViewLayoutObserver {
    static let shared = ViewLayoutObserver()

    /// Leading-edge throttle window. A trailing fire is scheduled so the last
    /// layout of a burst is never lost.
    var throttleInterval: TimeInterval = 1.0

    /// Invoked on the main thread, at most once per throttle window.
    var onLayout: (() -> Void)?

    private(set) var isEnabled = false

    private static var hasSwizzled = false
    private var lastFire = Date.distantPast
    private var trailingScheduled = false

    private init() {}

    func enable() {
        Self.installSwizzleIfNeeded()
        isEnabled = true
    }

    func disable() {
        isEnabled = false
    }

    private static func installSwizzleIfNeeded() {
        guard !hasSwizzled else { return }
        hasSwizzled = true
        Swizzling.swizzle(
            cls: UIView.self,
            original: #selector(UIView.layoutSublayers(of:)),
            swizzled: #selector(UIView.mw_replayLayoutSublayers(of:)))
    }

    /// Always called on the main thread.
    fileprivate func handleLayout() {
        guard isEnabled, onLayout != nil else { return }
        let now = Date()
        if now.timeIntervalSince(lastFire) >= throttleInterval {
            lastFire = now
            onLayout?()
        } else if !trailingScheduled {
            // trailing fire so a burst's final layout still gets captured
            trailingScheduled = true
            let delay = throttleInterval - now.timeIntervalSince(lastFire)
            DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.05)) { [weak self] in
                guard let self = self else { return }
                self.trailingScheduled = false
                if self.isEnabled {
                    self.lastFire = Date()
                    self.onLayout?()
                }
            }
        }
    }

    /// iOS 13-safe key-window lookup. Never uses `UIWindowScene.keyWindow`
    /// (iOS 15+); falls back to `UIApplication.windows` for scene-less apps.
    static func keyWindow() -> UIWindow? {
        let sceneWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
        if let sceneWindow = sceneWindow {
            return sceneWindow
        }
        return UIApplication.shared.windows.first { $0.isKeyWindow }
    }
}

extension UIView {
    @objc func mw_replayLayoutSublayers(of layer: CALayer) {
        // calls the original implementation (methods are exchanged)
        mw_replayLayoutSublayers(of: layer)
        // layoutSublayers can fire on background threads during CA transaction
        // cleanup; hop to main to avoid Auto Layout (NSISEngine) thread issues
        // and to keep throttle state single-threaded.
        if Thread.isMainThread {
            ViewLayoutObserver.shared.handleLayout()
        } else if ViewLayoutObserver.shared.isEnabled {
            DispatchQueue.main.async {
                ViewLayoutObserver.shared.handleLayout()
            }
        }
    }
}
#endif
