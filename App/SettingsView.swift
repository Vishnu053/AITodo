import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var remindersDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("On-device AI", isOn: Binding(get: { model.aiEnabled }, set: { model.setAIEnabled($0) }))
                        .disabled(model.assistant.availability != .available)
                } header: { Text("Apple Intelligence") } footer: {
                    switch model.assistant.availability {
                    case .available: Text("Refines todos using your related past todos and writes a daily brief. Runs entirely on this device; nothing is sent anywhere.")
                    case .unavailable(let why): Text(why)
                    }
                }

                Section {
                    Toggle("Reminders", isOn: Binding(
                        get: { model.remindersEnabled },
                        set: { on in Task { remindersDenied = !(await model.setRemindersEnabled(on)) } }))
                } footer: {
                    Text(remindersDenied ? "Notifications are turned off for AI Todo. Enable them in the Settings app." : "Timed todos remind you at their time; all-day todos at 9:00 on the day.")
                }

                Section {
                    Text(model.stats).foregroundStyle(.secondary)
                    if let exportURL { ShareLink("Export everything", item: exportURL) }
                    Button("Import…") { importing = true }
                } header: { Text("Memory") } footer: {
                    Text("Nothing is ever really deleted, so finished and deleted todos stay recallable. Import also accepts exports from the web version.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { exportURL = model.exportFile() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { model.importFile(url); exportURL = model.exportFile() }
            }
        }
    }
}
