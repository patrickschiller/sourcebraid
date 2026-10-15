import SwiftUI

enum ArchiveSection: Hashable {
    case recent, search, chat
    var title: LocalizedStringResource {
        switch self {
        case .recent: "Latest"
        case .search: "Search"
        case .chat: "Chat"
        }
    }
}

struct ContentView: View {
    @StateObject private var library = ArchiveLibrary()
    @StateObject private var chat = ArchiveChat()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var phase
    @State private var section = ArchiveSection.recent
    @State private var preferredColumn: NavigationSplitViewColumn = .sidebar
    @State private var settings = false
    @State private var clearData = false
    @State private var signOut = false
    @State private var searchQuery = ""
    @State private var searchResults: [ArchiveClip] = []
    @State private var searchError = ""

    init() {
#if DEBUG
        if ProcessInfo.processInfo.environment["SOURCEBRAID_DEMO"] == "1" {
            if ProcessInfo.processInfo.environment["SOURCEBRAID_CHAT_EXAMPLE"] == "1" {
                _chat = StateObject(wrappedValue: ArchiveChat(service: ArchiveDemoAnswering(), availability: { .ready }))
            } else if ProcessInfo.processInfo.environment["SOURCEBRAID_CHAT_LAYOUT"] == "1" {
                _chat = StateObject(wrappedValue: ArchiveChat(availability: { .ready }))
            }
        }
#endif
    }

    var body: some View {
        Group {
#if DEBUG
            if ProcessInfo.processInfo.environment["SOURCEBRAID_NATIVE_PREVIEW"] == "1" { ArchiveNativeProbe() }
            else {
                ArchiveWorkspace(library: library, chat: chat, section: $section, preferredColumn: $preferredColumn,
                    searchQuery: $searchQuery, searchResults: $searchResults, searchError: $searchError,
                    settings: $settings, clearData: $clearData, signOut: $signOut)
            }
#else
            ArchiveWorkspace(library: library, chat: chat, section: $section, preferredColumn: $preferredColumn,
                searchQuery: $searchQuery, searchResults: $searchResults, searchError: $searchError,
                settings: $settings, clearData: $clearData, signOut: $signOut)
#endif
        }
        .task { await library.configure(); if library.consumeOpenRequest() { preferredColumn = .detail } }
        .onReceive(NotificationCenter.default.publisher(for: .archiveOpenRequested)) { _ in
            if library.consumeOpenRequest() { preferredColumn = .detail }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sourceBraidConfigurationChanged)) { _ in
            chat.reset()
            Task { await ArchiveBackgroundRefresh.invalidateAndWait(); await library.configure(); ArchiveBackgroundRefresh.schedule() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .archiveDataRemoved)) { notification in
            guard notification.object as? ArchiveLibrary !== library else { return }
            chat.reset()
            Task { await library.removeLocalData(signOut: notification.userInfo?["signOut"] as? Bool ?? false, broadcast: false) }
        }
        .onChange(of: library.clips) { _, _ in if library.consumeOpenRequest() { preferredColumn = .detail } }
        .modifier(ArchiveFoldNavigation(preferredColumn: $preferredColumn))
        .onChange(of: sizeClass) { _, value in if value == .compact { preferredColumn = .sidebar } }
        .onChange(of: phase) { _, value in
            if value == .active { chat.checkAvailability(); Task { await library.configure() } }
            if value == .background { chat.stop(); ArchiveBackgroundRefresh.schedule() }
        }
        .onChange(of: library.generation) { _, _ in
            chat.reset(); searchQuery = ""; searchResults = []; searchError = ""
        }
#if DEBUG
        .onChange(of: library.clips) { _, clips in
            if ProcessInfo.processInfo.environment["SOURCEBRAID_DEMO_READER"] == "1", library.selectedPath == nil, let clip = clips.first {
                library.select(clip.path); preferredColumn = .detail
            }
        }
#endif
        .sheet(isPresented: $settings) { SettingsView() }
        .confirmationDialog(archiveText("Remove downloads and the search cache from this device?", "Downloads und Suchcache von diesem Gerät entfernen?"), isPresented: $clearData, titleVisibility: .visible) {
            Button(archiveText("Remove local data", "Lokale Daten entfernen"), role: .destructive) { Task { await library.removeLocalData() } }
        }
        .confirmationDialog(archiveText("Remove credentials and local archive data?", "Zugangsdaten und lokale Archivdaten entfernen?"), isPresented: $signOut, titleVisibility: .visible) {
            Button(archiveText("Sign out", "Abmelden"), role: .destructive) { Task { await library.removeLocalData(signOut: true) } }
        }
    }
}

private struct ArchiveWorkspace: View {
    @ObservedObject var library: ArchiveLibrary
    @ObservedObject var chat: ArchiveChat
    @Binding var section: ArchiveSection
    @Binding var preferredColumn: NavigationSplitViewColumn
    @Binding var searchQuery: String
    @Binding var searchResults: [ArchiveClip]
    @Binding var searchError: String
    @Binding var settings: Bool
    @Binding var clearData: Bool
    @Binding var signOut: Bool
    @State private var searchPresented = false
    var body: some View {
        Group {
            if #available(iOS 18.0, *), library.isConfigured {
                TabView(selection: $section) {
                    Tab(value: ArchiveSection.recent) {
                        ArchiveSectionScene(destination: .recent, library: library, chat: chat, section: $section, preferredColumn: $preferredColumn,
                            query: $searchQuery, results: $searchResults, error: $searchError,
                            settings: $settings, clearData: $clearData, signOut: $signOut)
                    } label: { Label(ArchiveSection.recent.title, systemImage: "clock") }
                    Tab(value: ArchiveSection.search, role: .search) {
                        ArchiveSectionScene(destination: .search, library: library, chat: chat, section: $section, preferredColumn: $preferredColumn,
                            query: $searchQuery, results: $searchResults, error: $searchError,
                            settings: $settings, clearData: $clearData, signOut: $signOut)
                            .searchable(text: $searchQuery, isPresented: $searchPresented,
                                prompt: archiveText("Search downloaded text", "Geladenen Text durchsuchen"))
                    } label: { Label(ArchiveSection.search.title, systemImage: "magnifyingglass") }
                    Tab(value: ArchiveSection.chat) {
                        ArchiveSectionScene(destination: .chat, library: library, chat: chat, section: $section, preferredColumn: $preferredColumn,
                            query: $searchQuery, results: $searchResults, error: $searchError,
                            settings: $settings, clearData: $clearData, signOut: $signOut)
                    } label: { Label(ArchiveSection.chat.title, systemImage: "bubble.left.and.bubble.right") }
                }
            } else {
                ArchiveSectionScene(destination: nil, library: library, chat: chat, section: $section, preferredColumn: $preferredColumn,
                    query: $searchQuery, results: $searchResults, error: $searchError,
                    settings: $settings, clearData: $clearData, signOut: $signOut)
                    .searchable(text: $searchQuery, isPresented: $searchPresented,
                        prompt: archiveText("Search downloaded text", "Geladenen Text durchsuchen"))
            }
        }
        .onChange(of: section) { _, value in searchPresented = value == .search }
        .onChange(of: searchPresented) { _, value in
            if value { section = .search; preferredColumn = .sidebar }
        }
    }
}

private struct ArchiveSectionScene: View {
    let destination: ArchiveSection?
    @ObservedObject var library: ArchiveLibrary
    @ObservedObject var chat: ArchiveChat
    @Binding var section: ArchiveSection
    @Binding var preferredColumn: NavigationSplitViewColumn
    @Binding var query: String
    @Binding var results: [ArchiveClip]
    @Binding var error: String
    @Binding var settings: Bool
    @Binding var clearData: Bool
    @Binding var signOut: Bool
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            Group {
                if !library.isConfigured {
                    ArchiveConnectView(status: library.status, settings: $settings)
                } else if let destination {
                    switch destination {
                    case .recent: ArchiveRecentList(library: library, preferredColumn: $preferredColumn)
                    case .search: ArchiveSearchView(library: library, query: $query, results: $results,
                        error: $error, preferredColumn: $preferredColumn)
                    case .chat:
                        ArchiveChatView(chat: chat, library: library) { source, snapshot in
                            Task {
                                do { try await library.openCitation(source, snapshot: snapshot); preferredColumn = .detail }
                                catch { library.status = error.localizedDescription }
                            }
                        }
                    }
                } else {
                    ArchiveLegacySections(library: library, chat: chat, section: $section,
                        preferredColumn: $preferredColumn, query: $query, results: $results, error: $error)
                }
            }
            .navigationTitle(Text(library.isConfigured ? (destination ?? section).title : "SourceBraid"))
            .navigationBarTitleDisplayMode(.large)
            .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
            .toolbar { ArchiveToolbar(library: library, settings: $settings, clearData: $clearData, signOut: $signOut) }
        } detail: {
            ArchiveDetail(library: library) {
                chat.wholeArchive = false; section = .chat; preferredColumn = .sidebar
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(SourceBraidTheme.canvas, for: .navigationBar, .tabBar)
        .background(SourceBraidTheme.canvas)
    }
}

private struct ArchiveLegacySections: View {
    @ObservedObject var library: ArchiveLibrary
    @ObservedObject var chat: ArchiveChat
    @Binding var section: ArchiveSection
    @Binding var preferredColumn: NavigationSplitViewColumn
    @Binding var query: String
    @Binding var results: [ArchiveClip]
    @Binding var error: String
    var body: some View {
        Group {
            switch section {
            case .recent: ArchiveRecentList(library: library, preferredColumn: $preferredColumn)
            case .search: ArchiveSearchView(library: library, query: $query, results: $results, error: $error, preferredColumn: $preferredColumn)
            case .chat:
                ArchiveChatView(chat: chat, library: library) { source, snapshot in
                    Task {
                        do { try await library.openCitation(source, snapshot: snapshot); preferredColumn = .detail }
                        catch { library.status = error.localizedDescription }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { section = .recent } label: { Label(ArchiveSection.recent.title, systemImage: "clock") }
                Spacer()
                Button { section = .search } label: { Label(ArchiveSection.search.title, systemImage: "magnifyingglass") }
                Spacer()
                Button { section = .chat } label: { Label(ArchiveSection.chat.title, systemImage: "bubble.left.and.bubble.right") }
            }
        }
    }
}

private struct ArchiveRecentList: View {
    @ObservedObject var library: ArchiveLibrary
    @Binding var preferredColumn: NavigationSplitViewColumn
    var body: some View {
        List {
            Section {
                ForEach(library.recent) { clip in
                    ArchiveClipButton(clip: clip, selected: library.selectedPath == clip.path) {
                        library.select(clip.path); preferredColumn = .detail
                    }
                }
                if library.recent.isEmpty {
                    ContentUnavailableView(archiveText("No saved clips yet", "Noch keine Beiträge"), systemImage: "doc.text",
                        description: Text(archiveText("Refresh to load the newest clips.", "Aktualisiere das Archiv, um die neuesten Beiträge zu laden.")))
                }
            } footer: {
                ArchiveSyncFooter(isSyncing: library.isSyncing, progress: library.progress, status: library.status,
                    metadataComplete: library.metadataComplete, checkedAt: library.snapshot?.checkedAt)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(SourceBraidTheme.canvas)
        .accessibilityIdentifier("archive.recent.list")
        .refreshable { library.synchronize(); await library.waitForSync() }
    }
}

private struct ArchiveClipButton: View {
    let clip: ArchiveClip
    let selected: Bool
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(clip.title).font(.headline).foregroundStyle(SourceBraidTheme.ink).lineLimit(3)
                    ArchiveCaptureDateView(date: clip.sortDate, precision: clip.datePrecision)
                        .font(.subheadline).foregroundStyle(SourceBraidTheme.secondaryInk)
                    if clip.dateSource == "path" {
                        Text(archiveText("Date from filename", "Datum aus Dateiname")).font(.caption2).foregroundStyle(SourceBraidTheme.secondaryInk)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark" : "chevron.forward")
                    .font(.caption.weight(.semibold)).foregroundStyle(selected ? Color.accentColor : SourceBraidTheme.secondaryInk)
            }
            .padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? SourceBraidTheme.mutedSurface : SourceBraidTheme.surface)
        .listRowSeparatorTint(SourceBraidTheme.separator)
        .accessibilityIdentifier("archive.clip.\(clip.path)")
        .accessibilityHint(archiveText("Open this clip", "Diesen Beitrag öffnen"))
    }
}

struct ArchiveCaptureDateView: View {
    let date: Date?
    let precision: String?
    @Environment(\.locale) private var locale
    var body: some View {
        if let date {
            Text(date, format: Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale,
                timeZone: precision == "day" ? TimeZone(secondsFromGMT: 0)! : .current))
        }
    }
}

private struct ArchiveSyncFooter: View {
    let isSyncing: Bool
    let progress: String
    let status: String
    let metadataComplete: Bool
    let checkedAt: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isSyncing { Label(progress, systemImage: "arrow.triangle.2.circlepath") }
            if !metadataComplete && checkedAt != nil {
                Text(archiveText("Showing loaded clips. More update in the background.", "Geladene Beiträge. Weitere werden im Hintergrund aktualisiert."))
            }
            if !status.isEmpty { Text(status) }
        }
        .font(.caption).foregroundStyle(SourceBraidTheme.secondaryInk)
    }
}

private struct ArchiveSearchView: View {
    @ObservedObject var library: ArchiveLibrary
    @Binding var query: String
    @Binding var results: [ArchiveClip]
    @Binding var error: String
    @Binding var preferredColumn: NavigationSplitViewColumn
    var body: some View {
        List {
            Section {
                ForEach(results) { clip in
                    ArchiveClipButton(clip: clip, selected: library.selectedPath == clip.path) {
                        library.select(clip.path); preferredColumn = .detail
                    }
                }
                if !query.isEmpty && results.isEmpty && error.isEmpty { ContentUnavailableView.search(text: query) }
            } footer: {
                Text(archiveText("\(library.indexedCount) of \(library.inventoryClipCount) clips searchable offline.",
                    "\(library.indexedCount) von \(library.inventoryClipCount) Beiträgen offline durchsuchbar."))
                    .foregroundStyle(SourceBraidTheme.secondaryInk)
                if !error.isEmpty { Text(error) }
            }
        }
        .listStyle(.insetGrouped)
        .task(id: query + library.generation.uuidString) { await refreshResults() }
        .scrollContentBackground(.hidden)
        .background(SourceBraidTheme.canvas)
        .onChange(of: library.clips) { _, _ in Task { await refreshResults() } }
        .accessibilityIdentifier("archive.search.list")
    }
    private func refreshResults() async {
        let request = query, epoch = library.generation
        do {
            let hits = request.isEmpty ? [] : try await library.search(request)
            try Task.checkCancellation()
            guard query == request, library.generation == epoch else { return }
            let versions = Dictionary(hits.map { ($0.path, $0.sha) }, uniquingKeysWith: { first, _ in first })
            results = request.isEmpty ? library.clips : library.clips.filter { versions[$0.path] == $0.sha }
            error = ""
        } catch is CancellationError { } catch {
            guard query == request, library.generation == epoch else { return }
            self.error = error.localizedDescription
        }
    }
}

private struct ArchiveConnectView: View {
    let status: String
    @Binding var settings: Bool
    var body: some View {
        VStack {
            ContentUnavailableView(archiveText("Connect your archive", "Archiv verbinden"), systemImage: "books.vertical", description: Text(status))
            Button(archiveText("Settings", "Einstellungen")) { settings = true }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(SourceBraidTheme.onAccent)
        }.padding().background(SourceBraidTheme.canvas)
    }
}

private struct ArchiveDetail: View {
    @ObservedObject var library: ArchiveLibrary
    let ask: () -> Void
    var body: some View {
        if let clip = library.selected {
            ArchiveReaderView(library: library, clip: clip, askAboutClip: ask)
                .id(clip.path + clip.sha + library.generation.uuidString)
        } else {
            ContentUnavailableView(archiveText("Select a clip", "Beitrag auswählen"), systemImage: "doc.richtext",
                description: Text(archiveText("Your Markdown archive, with its original sources.", "Dein Markdown-Archiv mit seinen Originalquellen.")))
                .background(SourceBraidTheme.canvas)
        }
    }
}

private struct ArchiveToolbar: ToolbarContent {
    @ObservedObject var library: ArchiveLibrary
    @Binding var settings: Bool
    @Binding var clearData: Bool
    @Binding var signOut: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if library.isSyncing { library.stopSync() } else { library.synchronize() }
            } label: {
                Label(library.isSyncing ? archiveText("Stop refresh", "Aktualisierung stoppen") : archiveText("Refresh", "Aktualisieren"),
                    systemImage: library.isSyncing ? "stop" : "arrow.clockwise")
            }
            .disabled(!library.isConfigured).accessibilityIdentifier("archive.refresh")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button(archiveText("Settings", "Einstellungen"), systemImage: "gear") { settings = true }
                Button(archiveText("Remove local data…", "Lokale Daten entfernen …"), systemImage: "trash", role: .destructive) { clearData = true }
                Button(archiveText("Sign out…", "Abmelden …"), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { signOut = true }
            } label: { Label(archiveText("Archive options", "Archiv-Optionen"), systemImage: "ellipsis") }
            .accessibilityIdentifier("archive.options")
        }
    }
}

private struct ArchiveFoldNavigation: ViewModifier {
    @Binding var preferredColumn: NavigationSplitViewColumn
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, next in
                if next.hinge?.status == .closed { preferredColumn = .sidebar }
            }
        } else { content }
    }
}
