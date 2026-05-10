import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SpaceMouseUSBViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusRow(isConnected: vm.isConnected)

            Divider()

            Form {
                HStack {
                    Text("Rotation Scale")
                    Spacer()
                    TextField("", value: $vm.rotScale,
                              format: .number.precision(.fractionLength(0...4)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                HStack {
                    Text("Translation Scale")
                    Spacer()
                    TextField("", value: $vm.transScale,
                              format: .number.precision(.fractionLength(0...4)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                HStack {
                    Spacer()
                    Button("Apply") { vm.applyScales() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .frame(minWidth: 300, minHeight: 160)
    }
}

// MARK: - Status indicator

private struct StatusRow: View {
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Color.green : Color.secondary)
                .frame(width: 10, height: 10)
            Text(isConnected ? "SpaceMouse Compact — connected"
                             : "SpaceMouse Compact — not found")
                .foregroundStyle(isConnected ? Color.primary : Color.secondary)
        }
    }
}
