// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0
//
// Portions adapted from sentry-cocoa (SentrySessionReplayCaptureGuard),
// Copyright (c) 2015 Sentry, used under the MIT License:
// https://github.com/getsentry/sentry-cocoa/blob/main/LICENSE.md

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit

/// Tells v3 session recording when to put a capture off. A capture blocks the
/// main thread, and a dropped frame is most visible while the user is
/// scrolling or dragging, or while something is animating. Capturing a moment
/// later, once that settles, also gives a cleaner frame.
///
/// Adapted from the Sentry Cocoa SDK's session-replay capture guard.
enum CaptureActivityGuard {

    enum Reason: Equatable {
        case interaction
        case animation
        case transition
    }

    /// Fewer running layer animations than this (a caret blink, a spinner)
    /// do not hold a capture back.
    static let activeAnimationThreshold = 4

    /// Main thread only. Why a capture of `window` should wait, or nil.
    static func reasonToWait(window: UIWindow) -> Reason? {
        if RunLoop.main.currentMode == .tracking || containsActiveInteraction(in: window) {
            return .interaction
        }
        if isAnimatingTransition(window) {
            return .transition
        }
        if activeAnimationCount(in: window, upTo: activeAnimationThreshold) >= activeAnimationThreshold {
            return .animation
        }
        return nil
    }

    static func containsActiveInteraction(in view: UIView) -> Bool {
        traverse(view) { view in
            if let scrollView = view as? UIScrollView,
               scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking {
                return true
            }
            if let control = view as? UIControl, control.isTracking {
                return true
            }
            return view.gestureRecognizers?.contains { $0.state == .began || $0.state == .changed } == true
        }
    }

    static func activeAnimationCount(in view: UIView, upTo limit: Int) -> Int {
        var count = 0
        traverse(view) { view in
            count += view.layer.animationKeys()?.count ?? 0
            return count >= limit
        }
        return count
    }

    /// Whether any view controller in the hierarchy is animating a transition;
    /// drawHierarchy renders black/torn frames mid-animation.
    static func isAnimatingTransition(_ window: UIWindow) -> Bool {
        var controller = window.rootViewController
        while let current = controller {
            if current.transitionCoordinator?.isAnimated == true {
                return true
            }
            if let presented = current.presentedViewController {
                controller = presented
            } else if let navigation = current as? UINavigationController {
                controller = navigation.topViewController
            } else if let tabs = current as? UITabBarController {
                controller = tabs.selectedViewController
            } else {
                controller = nil
            }
        }
        return false
    }

    /// Visits visible views depth-first until `visit` returns true.
    @discardableResult
    private static func traverse(_ view: UIView, _ visit: (UIView) -> Bool) -> Bool {
        guard !view.isHidden, view.alpha > 0.01 else { return false }
        if visit(view) {
            return true
        }
        for subview in view.subviews where traverse(subview, visit) {
            return true
        }
        return false
    }
}
#endif
