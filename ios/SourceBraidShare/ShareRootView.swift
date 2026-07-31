import SwiftUI

struct ShareRootView: View {
    @ObservedObject var model: ShareViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $model.title, axis: .vertical)
                        .lineLimit(1...3)
                    LabeledContent("Source", value: model.sourceSummary)
                        .lineLimit(1)
                }

                Section("Organize") {
                    TextField("Tags, separated by commas", text: $model.tags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Optional note", text: $model.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                switch model.state {
                case .loading:
                    statusRow("Reading shared item…")
                case .saving:
                    statusRow("Saving to GitHub…")
                case .saved:
                    Label("Saved to SourceBraid", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Could not save", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.footnote)
                        if !message.contains("Open the SourceBraid app") {
                            Button("Try again") { model.retry() }
                        }
                    }
                case .ready:
                    EmptyView()
                }
            }
            .navigationTitle("Save to SourceBraid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await model.save() }
                    }
                    .disabled(!model.canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func statusRow(_ text: String) -> some View {
        HStack {
            ProgressView()
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
