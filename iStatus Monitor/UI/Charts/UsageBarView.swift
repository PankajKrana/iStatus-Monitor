import SwiftUI

struct UsageBarView: View {
    let value: Double
    let tint: Color

    var body: some View {
        ProgressView(value: max(0, min(value, 100)), total: 100)
            .tint(tint)
    }
}
