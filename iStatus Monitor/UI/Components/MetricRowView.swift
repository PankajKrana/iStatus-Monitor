import SwiftUI

struct MetricRowView: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}
