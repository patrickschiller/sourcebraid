import SwiftUI

struct ContentView: View {
    @StateObject private var model = SettingsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        model.isConfigured ? "Ready to save" : "Setup required",
                        systemImage: model.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.isConfigured ? Color.green : Color.orange)

                    Text("In FAZ or any other app, tap Share and choose “SourceBraid”.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Share Extension")
                }

                Section("GitHub repository") {
                    TextField("Owner or organization", text: $model.owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Repository", text: $model.repository)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Branch", text: $model.branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Root folder", text: $model.rootFolder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    SecureField("github_pat_…", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Use a fine-grained token restricted to this repository with Contents: Read and write. It is stored in the shared iOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("GitHub token")
                }

                Section {
                    Button("Save settings") {
                        model.save()
                    }
                    Button {
                        Task { await model.testConnection() }
                    } label: {
                        HStack {
                            Text("Test connection")
                            if model.isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.isWorking)

                    if !model.statusMessage.isEmpty {
                        Text(model.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(model.statusIsError ? Color.red : Color.green)
                    }
                }

                if !model.recentCaptures.isEmpty {
                    Section("Recently saved") {
                        ForEach(model.recentCaptures) { capture in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(capture.title)
                                    .lineLimit(2)
                                Text(capture.path)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Section("What gets saved") {
                    Label("URLs from apps such as FAZ", systemImage: "link")
                    Label("Readable page text from Safari", systemImage: "doc.text")
                    Label("Selected or shared text", systemImage: "text.quote")
                    Label("PDF and file attachments up to 25 MB", systemImage: "paperclip")
                }
            }
            .navigationTitle("SourceBraid")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.refreshRecentCaptures()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
