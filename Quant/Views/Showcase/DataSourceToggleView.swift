import SwiftUI

struct DataSourceToggleView: View {
    @Binding var mode: DataSourceMode

    var body: some View {
        Picker("Source", selection: $mode) {
            Text("Mock").tag(DataSourceMode.mock)
            Text("Live").tag(DataSourceMode.live)
        }
        .pickerStyle(.segmented)
        .frame(width: 140)
    }
}
