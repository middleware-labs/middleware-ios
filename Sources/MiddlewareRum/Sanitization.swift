// Copyright © 2023 Middleware. Licensed under the Apache License, Version 2.0

#if os(iOS) || targetEnvironment(macCatalyst) || os(tvOS)
import UIKit
import Foundation
import SwiftUI

@objc public enum RecordingQuality: Int {
    case Low
    case Standard
    case High
}

/// Anything that can report a frame to mask out of a captured session-replay frame.
/// `UIView` conforms (see `UIViewExtension`), so hosts can pass any view to
/// `MiddlewareRum.addIgnoredView(_:)`.
public protocol Sanitizable {
    var frameInWindow: CGRect? { get }
}

struct SensitiveViewWrapperRepresentable: UIViewRepresentable {
    @Binding var viewWrapper: SensitiveViewWrapper?

    func makeUIView(context: Context) -> SensitiveViewWrapper {
        let wrapper = SensitiveViewWrapper()
        viewWrapper = wrapper
        return wrapper
    }

    func updateUIView(_ uiView: SensitiveViewWrapper, context: Context) { }
}

struct SensitiveModifier: ViewModifier {
    @State private var viewWrapper: SensitiveViewWrapper?

    func body(content: Content) -> some View {
        content
            .background(SensitiveViewWrapperRepresentable(viewWrapper: $viewWrapper))
    }
}

public extension View {
    func sensitive() -> some View {
        self.modifier(SensitiveModifier())
    }
}

class SensitiveViewWrapper: UIView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // registering is a no-op while the recorder is inactive
        if self.superview != nil {
            ReplayRecorderV3.shared.addSanitizedElement(self)
        } else {
            ReplayRecorderV3.shared.removeSanitizedElement(self)
        }
    }
}

class SensitiveTextField: UITextField {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window != nil {
            ReplayRecorderV3.shared.addSanitizedElement(self)
        } else {
            ReplayRecorderV3.shared.removeSanitizedElement(self)
        }
    }
}
#endif
