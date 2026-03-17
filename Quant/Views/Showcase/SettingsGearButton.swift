import SwiftUI

struct SettingsGearButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(10)
                .contentShape(Circle())
        }
        .accessibilityLabel("Settings")
    }
}
