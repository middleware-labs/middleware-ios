// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

/// Capture trigger for v3 session recording: notes every layout pass by
/// swizzling `UIView.layoutSublayers(of:)`, and invokes a throttled callback
/// on the main thread once the run loop has finished that pass's UI work.
/// Static screens therefore cost nothing — captures happen only when
/// something actually changes on screen.
///
/// The callback runs from a main run loop observer ordered after Core
/// Animation's commit, not from inside the layout pass: a capture blocks the
/// main thread, and inside `layoutSublayers` it would delay the very frame
/// being committed.
///
/// The swizzle is installed once per process and never removed; start/stop
/// cycles only toggle `isEnabled` (removing a swizzle races with other hooks).
class ViewLayoutObserver {
    static let shared = ViewLayoutObserver()

    /// Minimum time between captures. A layout inside the window is not
    /// lost: it is captured once the window has passed.
    var throttleInterval: TimeInterval = 1.0

    /// Invoked on the main thread, at most once per throttle window. Returns
    /// false to put the capture off; it is then retried after `retryInterval`
    /// without waiting for another layout pass.
    var onLayout: (() -> Bool)?

    static let retryInterval: TimeInterval = 0.25

    private(set) var isEnabled = false

    private static var hasSwizzled = false
    private var observer: CFRunLoopObserver?
    private var hasPendingLayout = false
    private var notBefore = Date.distantPast
    private var wakeUpScheduled = false

    private init() {}

    /// Main thread only.
    func enable() {
        Self.installSwizzleIfNeeded()
        isEnabled = true
        notBefore = .distantPast
        installObserverIfNeeded()
    }

    /// Main thread only.
    func disable() {
        isEnabled = false
        hasPendingLayout = false
        if let observer = observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = nil
        }
    }

    private static func installSwizzleIfNeeded() {
        guard !hasSwizzled else { return }
        hasSwizzled = true
        Swizzling.swizzle(
            cls: UIView.self,
            original: #selector(UIView.layoutSublayers(of:)),
            swizzled: #selector(UIView.mw_replayLayoutSublayers(of:)))
    }

    private func installObserverIfNeeded() {
        guard observer == nil else { return }
        // beforeWaiting: the run loop has done its work for this pass and Core
        // Animation has committed (its observer runs at a lower order).
        // exit: the same point for a nested run loop that ends instead.
        let activities = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities, true, CFIndex.max) { [weak self] _, _ in
            self?.runLoopDidFinishWork()
        }
        guard let observer = observer else { return }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    /// Main thread only. Asks for a capture at the end of the next run loop
    /// pass, ignoring the throttle window (recording start, return to the
    /// foreground).
    func setNeedsCapture() {
        guard isEnabled else { return }
        hasPendingLayout = true
        notBefore = .distantPast
        wakeUp(after: 0)
    }

    /// Always called on the main thread.
    fileprivate func handleLayout() {
        guard isEnabled else { return }
        hasPendingLayout = true
    }

    private func runLoopDidFinishWork() {
        guard isEnabled, hasPendingLayout, let onLayout = onLayout else { return }

        let now = Date()
        let wait = notBefore.timeIntervalSince(now)
        // a few ms of slack absorbs wake-up jitter
        guard wait <= 0.005 else {
            wakeUp(after: wait)
            return
        }

        if onLayout() {
            hasPendingLayout = false
            notBefore = now.addingTimeInterval(throttleInterval)
        } else {
            notBefore = now.addingTimeInterval(Self.retryInterval)
            wakeUp(after: Self.retryInterval)
        }
    }

    /// The run loop may go to sleep with a layout still pending; wake it so the
    /// observer runs again once the window has passed.
    private func wakeUp(after delay: TimeInterval) {
        guard !wakeUpScheduled else { return }
        wakeUpScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.05)) { [weak self] in
            self?.wakeUpScheduled = false
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
        // and to keep the pending flag single-threaded.
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
