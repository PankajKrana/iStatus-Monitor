import AppKit
import SwiftUI

@MainActor
final class MenuBarPopover {
    let popover: NSPopover
    private var eventMonitor: Any?

    init(content: some View) {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 420)

        let hosting = NSHostingController(rootView: AnyView(content.frame(width: 320).padding(12)))
        popover.contentViewController = hosting
        applyDynamicSize(hosting)
    }

    func update(content: some View) {
        let hosting = NSHostingController(rootView: AnyView(content.frame(width: 320).padding(12)))
        popover.contentViewController = hosting
        applyDynamicSize(hosting)
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
        } else {
            open(relativeTo: button)
        }
    }

    func open(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installEventMonitor()
    }

    func close() {
        popover.performClose(nil)
        removeEventMonitor()
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func applyDynamicSize(_ hosting: NSHostingController<AnyView>) {
        let fitting = hosting.sizeThatFits(in: NSSize(width: 320, height: 2000))
        let height = max(180, min(480, fitting.height))
        popover.contentSize = NSSize(width: 320, height: height)
    }
}
