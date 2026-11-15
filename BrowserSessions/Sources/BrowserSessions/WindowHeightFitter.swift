import AppKit
import SwiftUI

/// Fits the MenuBarExtra window to its content's height, keeping the top edge under the menu bar.
/// MenuBarExtra grows its window while open but never shrinks it, so smaller content (a closed session,
/// a dismissed banner) would otherwise float at the bottom of an oversized window.
struct WindowHeightFitter: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard contentHeight > 0, let window = view.window else { return }
        let frame = window.frame
        let chrome = frame.height - window.contentRect(forFrameRect: frame).height
        let height = contentHeight + chrome
        guard abs(frame.height - height) > 0.5 else { return }
        let fitted = NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
        window.setFrame(fitted, display: true)
    }
}
