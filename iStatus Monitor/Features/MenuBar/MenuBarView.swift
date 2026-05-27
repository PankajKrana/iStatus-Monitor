import SwiftUI

struct MenuBarView: View {
    let cpuText: String
    let ramText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iStatus Monitor")
                .font(.headline)
            Text(cpuText)
            Text(ramText)
        }
        .padding(12)
    }
}
