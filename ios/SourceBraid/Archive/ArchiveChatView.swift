import SwiftUI

struct ArchiveChatView: View {
    @ObservedObject var chat: ArchiveChat
    @ObservedObject var library: ArchiveLibrary
    let openSource: (SourceExcerpt, ArchiveSnapshot) -> Void
    var body: some View {
        Group {
            if chat.state.canGenerate {
                ArchiveChatHistory(chat: chat, selectedTitle: library.selected?.title, indexedCount: library.indexedCount,
                    clipCount: library.inventoryClipCount, hasSelection: library.selected != nil, summarize: {
                        chat.wholeArchive = false
                        chat.draft = archiveText("Summarize the key points in this clip.", "Fasse die wichtigsten Punkte dieses Beitrags zusammen.")
                        chat.send(library: library)
                    }, openSource: openSource)
                .safeAreaInset(edge: .bottom) { ArchiveChatComposer(chat: chat, send: { chat.send(library: library) }) }
            } else {
                VStack {
                    ContentUnavailableView(archiveText("Apple Intelligence", "Apple Intelligence"), systemImage: "sparkles", description: Text(chat.state.message))
                    Button(archiveText("Check availability again", "Verfügbarkeit erneut prüfen")) { chat.checkAvailability() }
                        .buttonStyle(.bordered)
                }.padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SourceBraidTheme.canvas)
        .toolbar {
            if !chat.messages.isEmpty {
                Button { chat.reset() } label: { Label(archiveText("Clear chat", "Chat leeren"), systemImage: "trash") }
            }
        }
        .onAppear { if library.selected == nil && chat.messages.isEmpty { chat.wholeArchive = true } }
    }
}

private struct ArchiveChatScope: View {
    @ObservedObject var chat: ArchiveChat
    let selectedTitle: String?
    let indexedCount: Int
    let clipCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(archiveText("Question scope", "Fragebereich"), selection: $chat.wholeArchive) {
                Text(archiveText("This clip", "Dieser Beitrag")).tag(false)
                Text(archiveText("Archive", "Archiv")).tag(true)
            }.pickerStyle(.segmented)
            if !chat.wholeArchive {
                Text(selectedTitle ?? archiveText("Select a clip in Latest first.", "Wähle zuerst einen Beitrag unter Neueste."))
                    .font(.subheadline).foregroundStyle(SourceBraidTheme.ink).lineLimit(2)
            }
            Text(archiveText("Apple Intelligence · on device · \(indexedCount)/\(clipCount) clips indexed",
                             "Apple Intelligence · auf dem Gerät · \(indexedCount)/\(clipCount) Beiträge indiziert"))
                .font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk)
        }
        .padding(.vertical)
    }
}

private struct ArchiveChatHistory: View {
    @ObservedObject var chat: ArchiveChat
    let selectedTitle: String?
    let indexedCount: Int
    let clipCount: Int
    let hasSelection: Bool
    let summarize: () -> Void
    let openSource: (SourceExcerpt, ArchiveSnapshot) -> Void
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ArchiveChatScope(chat: chat, selectedTitle: selectedTitle, indexedCount: indexedCount, clipCount: clipCount)
                    if chat.messages.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "text.bubble").font(.largeTitle).foregroundStyle(.tint)
                            Text(archiveText("Ask your archive", "Frage dein Archiv")).font(.title2.bold()).foregroundStyle(SourceBraidTheme.ink)
                            Text(archiveText("Ask about a saved clip or search across downloaded text. Answers use the supplied excerpts.",
                                             "Frage zu einem gespeicherten Beitrag oder durchsuche geladene Texte. Antworten beziehen sich auf die bereitgestellten Auszüge."))
                                .foregroundStyle(SourceBraidTheme.secondaryInk)
                            if hasSelection {
                                Button(action: summarize) { Label(archiveText("Summarize this clip", "Diesen Beitrag zusammenfassen"), systemImage: "text.alignleft") }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 24)
                    }
                    ForEach(chat.messages) { message in
                        ArchiveChatMessageView(message: message, openSource: openSource).id(message.id)
                    }
                    if !chat.error.isEmpty { Text(chat.error).font(.callout).foregroundStyle(.red) }
                }
                .padding(.horizontal).padding(.bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

private struct ArchiveChatMessageView: View {
    let message: ArchiveChatMessage
    let openSource: (SourceExcerpt, ArchiveSnapshot) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.isUser ? archiveText("You", "Du") : "SourceBraid").font(.caption.bold()).foregroundStyle(SourceBraidTheme.secondaryInk)
            Text(message.text.isEmpty ? "…" : message.text).foregroundStyle(SourceBraidTheme.ink).textSelection(.enabled)
            if message.incomplete && !message.isUser {
                Text(archiveText("Partial or unverified answer", "Teilantwort oder nicht überprüfte Antwort")).font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk)
            }
            ForEach(message.sources) { source in
                Button { if let snapshot = message.snapshot { openSource(source, snapshot) } } label: {
                    Label(source.title, systemImage: "doc.text").font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(message.isUser ? SourceBraidTheme.mutedSurface : SourceBraidTheme.surface,
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(SourceBraidTheme.separator, lineWidth: 1) }
    }
}

private struct ArchiveChatComposer: View {
    @ObservedObject var chat: ArchiveChat
    let send: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(archiveText("Ask about your Markdown…", "Frage zu deinem Markdown …"), text: $chat.draft,
                    prompt: Text(archiveText("Ask about your Markdown…", "Frage zu deinem Markdown …")).foregroundStyle(SourceBraidTheme.secondaryInk), axis: .vertical)
                    .lineLimit(1...5)
                    .foregroundStyle(SourceBraidTheme.ink)
                    .padding(.leading, 8).padding(.vertical, 6)
                    .focused($focused)
                    .accessibilityIdentifier("archive.chat.input")
                Button {
                    if chat.isWorking { chat.stop() } else { focused = false; send() }
                } label: {
                    Image(systemName: chat.isWorking ? "stop" : "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .foregroundStyle(SourceBraidTheme.onAccent)
                .disabled(!chat.isWorking && chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(chat.isWorking ? archiveText("Stop answer", "Antwort stoppen") : archiveText("Send question", "Frage senden"))
            }
            .padding(6)
            .background(SourceBraidTheme.surface, in: RoundedRectangle(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(focused ? Color.accentColor : SourceBraidTheme.secondaryInk, lineWidth: 1)
            }
            if focused {
                Button { focused = false } label: {
                    Label(archiveText("Dismiss keyboard", "Tastatur ausblenden"), systemImage: "keyboard.chevron.compact.down")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityIdentifier("archive.chat.dismissKeyboard")
            }
        }
        .padding(.horizontal).padding(.top, 10).padding(.bottom, 24)
        .background(SourceBraidTheme.canvas)
    }
}
