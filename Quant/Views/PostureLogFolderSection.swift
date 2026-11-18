import SwiftUI
import UniformTypeIdentifiers

/// Choosing the folder the posture log is copied into (2026-11-17). See `PostureLogFolder`.
struct PostureLogFolderSection: View {
    @ObservedObject var folder: PostureLogFolder
    @State private var choosing = false

    var body: some View {
        Section {
            LabeledContent("Copies to", value: folder.name ?? "Not set")
            if let problem = folder.problem {
                Text(problem)
                    .foregroundStyle(.red)
            } else if let lastSaved = folder.lastSaved {
                LabeledContent("Last copied") {
                    Text(lastSaved, style: .time)
                }
            }
            Button(folder.name == nil ? "Choose Folder…" : "Change Folder…") {
                choosing = true
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    Task { await folder.choose(url) }
                }
            }
            if folder.name != nil {
                Button("Stop Copying", role: .destructive) {
                    folder.stop()
                }
            }
        } header: {
            Text("Posture Log")
                .readableSecondary()
        } footer: {
            Text("Each day's log is copied here as it's written: every 5 minutes, and when Aware "
                 + "goes to the background. Choose a folder in iCloud Drive to read it on your Mac. "
                 + "Off until you choose one.")
                .readableSecondary()
        }
    }
}
