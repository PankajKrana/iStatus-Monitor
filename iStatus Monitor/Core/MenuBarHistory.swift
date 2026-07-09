import Foundation

// MARK: - Ring Buffer

/// Fixed-capacity FIFO buffer for rolling metric history.
///
/// Appends are amortized O(1): once at capacity, the oldest sample is dropped as
/// the newest is appended. This backs the menu-bar sparklines and is fed exactly
/// once per sampling tick by `AppState.apply(_:)` — it owns no timer or poller of
/// its own, so the single `SystemMonitorService` loop stays the only source.
struct RingBuffer<Element: Sendable>: Sendable {
    private(set) var elements: [Element] = []
    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Append a sample, dropping the oldest once at capacity.
    mutating func append(_ element: Element) {
        elements.append(element)
        if elements.count > capacity {
            elements.removeFirst()
        }
    }

    /// Append a sequence of samples, preserving FIFO order.
    mutating func append(contentsOf newElements: some Sequence<Element>) {
        for element in newElements {
            append(element)
        }
    }

    var values: [Element] { elements }
    var isEmpty: Bool { elements.isEmpty }
    var count: Int { elements.count }
}

// MARK: - Menu Bar History

/// Rolling history for the six sparkline-capable widgets, keyed by widget id.
///
/// `Sendable` and stateless about the metrics it carries — it only stores scalar
/// sequences. `AppState` constructs and mutates it on the main actor (inside
/// `apply`), and the menu-bar views read `values(for:)` on the main actor. It is
/// never passed across an actor boundary, so the non-isolated `AppState` that
/// wraps it stays safe under Swift 6 strict concurrency.
struct MenuBarHistory: Sendable {
    /// 60 s of history at the default 1 Hz sampling cadence — matches Stats' window.
    static let capacity = 60

    /// Widget ids that support a sparkline, in registry order.
    static let widgetIDs = ["cpu", "ram", "network", "disk", "gpu", "battery"]

    private var buffers: [String: RingBuffer<Double>]

    init() {
        buffers = Dictionary(uniqueKeysWithValues: Self.widgetIDs.map {
            ($0, RingBuffer<Double>(capacity: Self.capacity))
        })
    }

    /// Append a sample for a widget. No-op for unknown ids or `nil` values
    /// (e.g. battery on a desktop, GPU before its first snapshot).
    mutating func record(_ value: Double?, for widgetId: String) {
        guard let value, var buffer = buffers[widgetId] else { return }
        buffer.append(value)
        buffers[widgetId] = buffer
    }

    /// Recent samples oldest→newest, or `[]` when the widget has no history yet.
    func values(for widgetId: String) -> [Double] {
        buffers[widgetId]?.values ?? []
    }
}
