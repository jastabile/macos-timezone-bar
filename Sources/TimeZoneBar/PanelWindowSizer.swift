import AppKit
import SwiftUI

/// Sizes the MenuBarExtra panel to its content, keeping the top edge under the menu bar.
/// SwiftUI grows a `.window`-style MenuBarExtra when content gets taller but never shrinks it,
/// leaving shorter content (search view, fewer zones) floating in the middle of an oversized panel.
struct PanelWindowSizer: NSViewRepresentable {
    let contentHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let height = contentHeight
        // Defer until SwiftUI has finished its own layout pass for this update.
        DispatchQueue.main.async {
            guard let window = view.window, height > 0 else { return }
            let current = window.contentRect(forFrameRect: window.frame).height
            guard abs(current - height) > 0.5 else { return }
            let top = window.frame.maxY
            var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: window.frame.width, height: height))
            frame.origin = NSPoint(x: window.frame.minX, y: top - frame.height)
            window.setFrame(frame, display: true)
        }
    }
}
