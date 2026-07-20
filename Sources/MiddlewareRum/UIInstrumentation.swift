// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import Foundation
import UIKit
extension UIApplication {
    @objc open func abracadabra_sendAction(_ action: Selector,
                                           to target: Any?,
                                           from sender:Any?,
                                           for event: UIEvent?) -> Bool {
        setUIFields()
        let uiSpan = tracer()
            .spanBuilder(spanName: action.description).startSpan()
        uiSpan.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "ui")
        uiSpan.setAttribute(key: MiddlewareConstants.Attributes.ACTION_NAME, value: action.description)
        OpenTelemetry.instance.contextProvider.setActiveSpan(uiSpan)
        defer {
            OpenTelemetry.instance.contextProvider.removeContextForSpan(uiSpan)
            uiSpan.end()
        }
        if(target != nil) {
            uiSpan.setAttribute(key: MiddlewareConstants.Attributes.TARGET_TYPE, value: AttributeValue(String(describing: type(of: target!))))
        }
        if sender != nil {
            uiSpan.setAttribute(key: MiddlewareConstants.Attributes.SENDER_TYPE, value: String(describing: type(of: sender!)))
        }
        if event != nil {
            uiSpan.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: String(describing: type(of: event!)))
        }
        return abracadabra_sendAction(action, to: target, from: sender, for: event)
    }
}

extension UIViewController {
    @objc open func abracadabra_viewDidLoad() {
        setUIFields()
        self.abracadabra_viewDidLoad()
    }
    @objc open func abracadabra_viewDidAppear(_ animated: Bool) {
        setUIFields()
        self.abracadabra_viewDidAppear(animated)
    }
    @objc open func abracadabra_viewDidDisappear(_ animated: Bool) {
        setUIFields()
        self.abracadabra_viewDidDisappear(animated)
    }
}

class NotificationPairInstrumenter {
    let obj2Span = NSMapTable<NSObject, SpanHolder>(keyOptions: NSPointerFunctions.Options.weakMemory, valueOptions: NSPointerFunctions.Options.strongMemory)
    let begin: String
    let end: String
    let spanName: String
    init(begin: String, end: String, spanName: String) {
        self.begin = begin
        self.end = end
        self.spanName = spanName
    }
    func start() {
        let beginName = Notification.Name(rawValue: begin)
        let endName = Notification.Name(rawValue: end)
        
        _ = NotificationCenter.default.addObserver(forName: beginName, object: nil, queue: nil) { (notif) in
            let notifObj = notif.object as? NSObject
            if notifObj != nil {
                let span = tracer().spanBuilder(spanName: self.spanName).startSpan()
                span.setAttribute(key: MiddlewareConstants.Attributes.LAST_SCREEN_NAME, value: getScreenName())
                span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "ui")
                span.setAttribute(key: MiddlewareConstants.Attributes.OBJECT_TYPE, value: String(describing: type(of: notif.object!)))
                self.obj2Span.setObject(SpanHolder(span), forKey: notifObj)
            }
            
        }
        _ = NotificationCenter.default.addObserver(forName: endName, object: nil, queue: nil) { (notif) in
            setUIFields()
            let notifObj = notif.object as? NSObject
            if notifObj != nil {
                let spanHolder = self.obj2Span.object(forKey: notifObj)
                if spanHolder != nil {
                    
                    spanHolder?.span.setAttribute(key: MiddlewareConstants.Attributes.SCREEN_NAME, value: getScreenName())
                    spanHolder?.span.end()
                }
            }
        }
        
    }
}

private func pickVC(_ vc: UIViewController?) -> UIViewController? {
    if vc == nil {
        return nil
    }
    if let nav = vc as? UINavigationController {
        if nav.visibleViewController != nil {
            return pickVC(nav.visibleViewController)
        }
        if nav.topViewController != nil {
            return pickVC(nav.topViewController)
        }
    }
    if let tabVC = vc as? UITabBarController {
        if tabVC.selectedViewController != nil {
            return pickVC(tabVC.selectedViewController)
        }
    }
    if let page = vc as? UIPageViewController {
        if page.viewControllers != nil && !page.viewControllers!.isEmpty {
            return pickVC(page.viewControllers![0])
        }
    }
    if vc!.presentedViewController != nil {
        return pickVC(vc!.presentedViewController)
    }
    return vc
}

private func pickWindow() -> UIWindow? {
    let app = UIApplication.shared
    let key = app.windows.last { $0.isKeyWindow }
    if key != nil {
        return key
    }
    let wins = app.windows
    if !wins.isEmpty {
        return wins[wins.count-1]
    }
    return nil
}

private func setUIFields() {
    if !Thread.current.isMainThread {
        return
    }
    if isScreenNameManuallySet() {
        return
    }
    let win = pickWindow()
    if win != nil {
        let vc = pickVC(win!.rootViewController)
        if vc != nil {
            setScreenNameInternal(String(describing: type(of: vc!)), false)
        }
    }
}

func abracadabra(clazz: AnyClass, orig: Selector, swoosh: Selector) {
    let origM = class_getInstanceMethod(clazz, orig)
    let swizM = class_getInstanceMethod(clazz, swoosh)
    if origM != nil && swizM != nil {
        method_exchangeImplementations(origM!, swizM!)
    } else {
        print("warning: could not swizzle "+NSStringFromSelector(orig))
    }
}

let PresentationTransitionInstrumenter = NotificationPairInstrumenter(
    begin: "UIPresentationControllerPresentationTransitionWillBeginNotification",
    end: "UIPresentationControllerPresentationTransitionDidEndNotification",
    spanName: MiddlewareConstants.Spans.PRESENTATION_TRANSITION)

func initializePresentationTransitionInstrumentation() {
    PresentationTransitionInstrumenter.start()
    _ = NotificationCenter.default.addObserver(forName: Notification.Name(rawValue: "_UIWindowSystemGestureStateChangedNotification"), object: nil, queue: nil) { (_) in
        setUIFields()
    }
}


let ShowVCInstrumenter = NotificationPairInstrumenter(
    begin: "UINavigationControllerWillShowViewControllerNotification",
    end: "UINavigationControllerDidShowViewControllerNotification",
    spanName: MiddlewareConstants.Spans.SHOW_VC)

func initializeShowVCInstrumentation() {
    ShowVCInstrumenter.start()
}

class UIInstrumentation {
    func start() {
        initializePresentationTransitionInstrumentation()

        initializeShowVCInstrumentation()

        abracadabra(clazz: UIApplication.self, orig: #selector(UIApplication.sendAction(_:to:from:for:)), swoosh: #selector(UIApplication.abracadabra_sendAction(_:to:from:for:)))
        abracadabra(clazz: UIViewController.self, orig: #selector(UIViewController.viewDidLoad), swoosh: #selector(UIViewController.abracadabra_viewDidLoad))
        abracadabra(clazz: UIViewController.self, orig: #selector(UIViewController.viewDidAppear(_:)), swoosh: #selector(UIViewController.abracadabra_viewDidAppear(_:)))
        abracadabra(clazz: UIViewController.self, orig: #selector(UIViewController.viewDidDisappear(_:)), swoosh: #selector(UIViewController.abracadabra_viewDidDisappear(_:)))

        startTapHeatmapCapture()
    }
}

/// Captures every user tap and emits it as a `tap` RUM span so the backend can build
/// a click heatmap (parity with the browser SDK). Coordinates are window points —
/// the same space the v3 replay uses — so a heatmap can overlay the replay screenshots.
private func startTapHeatmapCapture() {
    TouchTracker.shared.onTap = { location, window, timestampMs in
        emitTapSpan(location: location, window: window, timestampMs: timestampMs)
    }
    TouchTracker.shared.enableTapCapture()
}

private func emitTapSpan(location: CGPoint, window: UIWindow, timestampMs: Int64) {
    let target = window.hitTest(location, with: nil)
    let screenName = getScreenName()
    let x = Int(location.x)
    let y = Int(location.y)
    let width = Int(window.bounds.width)
    let height = Int(window.bounds.height)
    let targetClass = target.map { String(describing: type(of: $0)) }
    let accessibilityId = target?.accessibilityIdentifier
    let text = tapTargetText(target)

    let span = tracer().spanBuilder(spanName: "tap").startSpan()
    span.setAttribute(key: MiddlewareConstants.Attributes.COMPONENT, value: "ui")
    span.setAttribute(key: MiddlewareConstants.Attributes.EVENT_TYPE, value: "tap")
    span.setAttribute(key: "x", value: x)
    span.setAttribute(key: "y", value: y)
    span.setAttribute(key: "pageX", value: x)
    span.setAttribute(key: "pageY", value: y)
    span.setAttribute(key: "viewport.width", value: width)
    span.setAttribute(key: "viewport.height", value: height)
    span.setAttribute(key: "target_xpath", value: buildTapSelector(screenName, targetClass, accessibilityId))
    span.setAttribute(key: MiddlewareConstants.Attributes.SCREEN_NAME, value: screenName)
    if let targetClass = targetClass {
        span.setAttribute(key: MiddlewareConstants.Attributes.TARGET_TYPE, value: targetClass)
    }
    if let accessibilityId = accessibilityId, !accessibilityId.isEmpty {
        span.setAttribute(key: "target.accessibility_id", value: accessibilityId)
    }
    if let text = text, !text.isEmpty {
        span.setAttribute(key: "target.text", value: text)
    }
    span.end()
}

/// Best-effort human-readable label for the tapped view.
private func tapTargetText(_ view: UIView?) -> String? {
    switch view {
    case let button as UIButton:
        return button.currentTitle ?? button.titleLabel?.text
    case let label as UILabel:
        return label.text
    case let textField as UITextField:
        return textField.text ?? textField.placeholder
    default:
        return view?.accessibilityLabel
    }
}

/// Synthetic selector (`Screen/ViewClass#accessibility-id`) matching the Android SDK,
/// so the heatmap can group taps by element and highlight top elements.
private func buildTapSelector(_ screenName: String, _ targetClass: String?, _ accessibilityId: String?) -> String {
    var selector = screenName + "/" + (targetClass ?? "UIView")
    if let accessibilityId = accessibilityId, !accessibilityId.isEmpty {
        selector += "#" + accessibilityId
    }
    return selector
}
#endif
