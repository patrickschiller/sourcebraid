import SwiftUI

struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()
    @State private var notices = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        model.isConfigured ? archiveText("Ready to save", "Bereit zum Speichern") : archiveText("Setup required", "Einrichtung erforderlich"),
                        systemImage: model.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.isConfigured ? Color.accentColor : Color.orange)

                    Text(archiveText("Weave the web into durable Markdown in your own GitHub repository.", "Web-Inhalte als dauerhaftes Markdown im eigenen GitHub-Repository speichern."))
                        .font(.subheadline)
                        .foregroundStyle(SourceBraidTheme.secondaryInk)
                } header: {
                    Text(archiveText("Share Extension", "Share Extension"))
                }
                .listRowBackground(SourceBraidTheme.surface)

                Section(archiveText("GitHub repository", "GitHub-Repository")) {
                    TextField(archiveText("Owner or organization", "Eigentümer oder Organisation"), text: $model.owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(archiveText("Repository", "Repository"), text: $model.repository)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(archiveText("Branch", "Branch"), text: $model.branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(archiveText("Root folder", "Stammordner"), text: $model.rootFolder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .listRowBackground(SourceBraidTheme.surface)

                Section {
                    SecureField("github_pat_…", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(archiveText("Use a fine-grained token restricted to this repository with Contents: Read and write. It is stored in the shared iOS Keychain.", "Verwende einen auf dieses Repository beschränkten Fine-grained-Token mit Contents: Read and write. Er wird im gemeinsamen iOS-Schlüsselbund gespeichert."))
                        .font(.caption)
                        .foregroundStyle(SourceBraidTheme.secondaryInk)
                } header: {
                    Text(archiveText("GitHub token", "GitHub-Token"))
                }
                .listRowBackground(SourceBraidTheme.surface)

                Section {
                    Button(archiveText("Save settings", "Einstellungen speichern")) {
                        model.save()
                    }
                    Button {
                        Task { await model.testConnection() }
                    } label: {
                        HStack {
                            Text(archiveText("Test connection", "Verbindung testen"))
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
                            .foregroundStyle(model.statusIsError ? Color.red : Color.accentColor)
                    }
                }
                .listRowBackground(SourceBraidTheme.surface)

                Section {
                    Button(archiveText("Third-party licenses", "Lizenzen von Drittanbietern")) { notices = true }
                }
                .listRowBackground(SourceBraidTheme.surface)

                Section(archiveText("What gets saved", "Was gespeichert wird")) {
                    Label(archiveText("URL content from any app", "URL-Inhalte aus beliebigen Apps"), systemImage: "link")
                    Label(archiveText("Readable page text from Safari", "Lesbarer Seitentext aus Safari"), systemImage: "doc.text")
                    Label(archiveText("Selected or shared text", "Ausgewählter oder geteilter Text"), systemImage: "text.quote")
                    Label(archiveText("PDF and file attachments up to 25 MB", "PDF- und Dateianhänge bis 25 MB"), systemImage: "paperclip")
                }
                .listRowBackground(SourceBraidTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(SourceBraidTheme.canvas)
            .toolbarBackground(SourceBraidTheme.canvas, for: .navigationBar)
            .navigationTitle("SourceBraid")
            .sheet(isPresented: $notices) {
                NavigationStack {
                    ScrollView { Text(licenseText).font(.caption.monospaced()).textSelection(.enabled).padding() }
                    .navigationTitle(archiveText("Licenses", "Lizenzen"))
                    .toolbar { Button(archiveText("Done", "Fertig")) { notices = false } }
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(archiveText("Done", "Fertig")) { dismiss() } } }
        }
    }
    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return archiveText("Licenses unavailable", "Lizenzen nicht verfügbar") }
        return text
    }
}

#Preview {
    SettingsView()
}
