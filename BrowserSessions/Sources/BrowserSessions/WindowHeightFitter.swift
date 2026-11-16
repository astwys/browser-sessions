import AppKit
import SwiftUI

extension View {
    /// Sizes the MenuBarExtra window to this content's height, keeping the top edge under the menu bar.
    /// MenuBarExtra grows its window while open but never shrinks it, so smaller content (a closed session,
    /// a dismissed banner) would otherwise float at the bottom of an oversized window.
    func fitsWindowHeight(_ height: CGFloat) -> some View {
        modifier(WindowHeightFitter(height: height))
    }
}

/// Animatable, so a height change inside `withAnimation` reaches the window on every frame of that
/// animation: the window edge and the content it holds move on one clock instead of the window jumping.
private struct WindowHeightFitter: ViewModifier, Animatable {
    var height: CGFloat

    nonisolated var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(height: height > 0 ? height : nil, alignment: .top)
            .background(WindowFrameSetter(contentHeight: height))
    }
}

private struct WindowFrameSetter: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard contentHeight > 0, let window = view.window else { return }
        let frame = window.frame
        let chrome = frame.height - window.contentRect(forFrameRect: frame).height
        let height = (contentHeight + chrome).rounded()
        guard abs(frame.height - height) > 0.5 else { return }
        let fitted = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        // No forced display: this runs inside SwiftUI's update, every frame of an animation, and drawing
        // here caught text halfway through being updated.
        window.setFrame(fitted, display: false)
    }
}
