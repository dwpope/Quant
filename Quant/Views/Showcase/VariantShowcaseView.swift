import SwiftUI

struct VariantShowcaseView: View {
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mockSource: MockPostureDataSource
    @StateObject private var observer: PostureDisplayObserver

    @State private var dataSourceMode: DataSourceMode = .mock
    @State private var selectedVariant: VariantDescriptor?
    @State private var showingSettings = false
    @State private var showingMockControls = false
    @State private var liveSource: LivePostureDataSource?

    init() {
        let mock = MockPostureDataSource()
        _mockSource = StateObject(wrappedValue: mock)
        _observer = StateObject(wrappedValue: PostureDisplayObserver(source: mock))
    }

    var body: some View {
        NavigationSplitView {
            VariantCatalogList(selectedVariant: $selectedVariant)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        DataSourceToggleView(mode: $dataSourceMode)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button {
                                showingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            Button("Done") { dismiss() }
                        }
                    }
                }
        } detail: {
            if let variant = selectedVariant {
                variant.makeView()
                    .environmentObject(observer)
                    .postureVariantAccessibility()
                    .overlay(alignment: .bottomTrailing) {
                        if dataSourceMode == .mock {
                            mockControlsButton
                        }
                    }
            } else {
                placeholderDetail
            }
        }
        .onAppear {
            liveSource = LivePostureDataSource(appModel: appModel)
        }
        .onChange(of: dataSourceMode) { _, newMode in
            switch newMode {
            case .mock:
                observer.switchSource(to: mockSource)
            case .live:
                if let liveSource {
                    observer.switchSource(to: liveSource)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
        }
        .sheet(isPresented: $showingMockControls) {
            MockControlsInspector(mockSource: mockSource)
                .presentationDetents([.medium, .large])
        }
    }

    private var placeholderDetail: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Select a variant")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var mockControlsButton: some View {
        Button {
            showingMockControls = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .padding(12)
                .postureBackground()
                .clipShape(Circle())
        }
        .padding()
    }
}

#Preview {
    VariantShowcaseView()
        .environmentObject(AppModel())
}
