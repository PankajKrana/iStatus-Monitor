import AppKit
import SwiftUI

@MainActor
enum ChartExportSupport {
    static func copyToPasteboard<V: View>(view: V, size: CGSize) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let image = renderer.nsImage else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
}
