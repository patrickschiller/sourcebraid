import Foundation
import BackgroundTasks

struct ArchiveRefreshReport: Sendable {
    enum State: Sendable { case refreshed, unchanged, cancelled, failed }
    let state: State
    let processed: Int
    let remaining: Int
    var succeeded: Bool { state == .refreshed || state == .unchanged }
}

enum ArchiveRefreshScope: Sendable {
    case bootstrap, background, manual
    var fileLimit: Int { switch self { case .bootstrap: return 7; case .background: return 20; case .manual: return .max } }
    var byteLimit: Int { self == .manual ? .max : 10 * 1024 * 1024 }
    var inventoryRequestLimit: Int? { self == .manual ? nil : 32 }
}

private enum ArchiveRefreshError: LocalizedError {
    case busy
    var errorDescription: String? { archiveText("An archive refresh is already running.", "Das Archiv wird bereits aktualisiert.") }
}

struct ArchiveRefreshRecovery: Sendable {
    let manifest: ArchiveCache.Manifest
    let indexedCount: Int
}

struct ArchiveRefreshFailure: Error {
    let cause: any Error
    let recovery: ArchiveRefreshRecovery?
}

/// One writer per archive across windows and scheduled refreshes. Data removal blocks
/// new writers, cancels the existing writer, and waits before deleting the cache.
@MainActor
enum ArchiveRefreshCoordinator {
    private struct Job {
        let id: UUID
        let cancel: @Sendable () -> Void
        let finished: Task<Void, Never>
    }
    private static var jobs: [ArchiveIdentity: Job] = [:]
    private static var pauses: [UUID: ArchiveIdentity?] = [:]

    static func perform(identity: ArchiveIdentity, client: any ArchiveReading, cache: ArchiveCache,
                        index: ArchiveSearchIndex?, scope: ArchiveRefreshScope,
                        progress: @escaping @MainActor @Sendable (String) -> Void) async throws -> ArchiveRefreshResult {
        try Task.checkCancellation()
        guard !pauses.values.contains(where: { $0 == nil || $0 == identity }) else { throw CancellationError() }
        guard jobs[identity] == nil else { throw ArchiveRefreshError.busy }
        let id = UUID()
        let task = Task {
            do { return try await ArchiveRefreshEngine.run(client: client, cache: cache, index: index, scope: scope, progress: progress) }
            catch {
                // Recovery may open the disposable search database. Keep that I/O
                // inside the tracked job, so data removal waits for it as well as
                // the engine. A paused archive must never be reopened by recovery.
                var recovery: ArchiveRefreshRecovery?
                if !isPaused(identity), let manifest = try? await cache.load(),
                   !isPaused(identity), manifest.snapshot?.identity == identity {
                    let count = (try? await index?.count()) ?? 0
                    if !isPaused(identity) { recovery = .init(manifest: manifest, indexedCount: count) }
                }
                throw ArchiveRefreshFailure(cause: error, recovery: recovery)
            }
        }
        jobs[identity] = Job(id: id, cancel: { task.cancel() }, finished: Task { _ = try? await task.value })
        defer { if jobs[identity]?.id == id { jobs.removeValue(forKey: identity) } }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            if Task.isCancelled { throw ArchiveRefreshFailure(cause: CancellationError(), recovery: .init(manifest: result.manifest, indexedCount: result.indexedCount)) }
            return result
        } onCancel: { task.cancel() }
    }

    static func store(identity: ArchiveIdentity, cache: ArchiveCache, index: ArchiveSearchIndex?,
                      bytes: Data, file: ArchiveFile, clip: ArchiveClip? = nil) async throws -> ArchiveCache.Manifest? {
        try Task.checkCancellation()
        guard !pauses.values.contains(where: { $0 == nil || $0 == identity }) else { throw CancellationError() }
        // A reader may still display its immutable bytes while a refresh is writing.
        // Avoid competing cache/index writes; the refresh or a later read can cache them.
        guard jobs[identity] == nil else { return nil }
        let id = UUID()
        let task = Task {
            try Task.checkCancellation()
            try await cache.store(bytes, sha: file.sha)
            try Task.checkCancellation()
            if let clip {
                try await cache.addMetadata(clip)
                try Task.checkCancellation()
                try await index?.update(clip)
            }
            try Task.checkCancellation()
            return try await cache.load()
        }
        jobs[identity] = Job(id: id, cancel: { task.cancel() }, finished: Task { _ = try? await task.value })
        defer { if jobs[identity]?.id == id { jobs.removeValue(forKey: identity) } }
        return try await withTaskCancellationHandler {
            let manifest = try await task.value
            try Task.checkCancellation()
            return manifest
        } onCancel: { task.cancel() }
    }

    static func pause(for identity: ArchiveIdentity? = nil) async -> UUID {
        let token = UUID()
        // updateValue stores an optional nil value rather than removing the dictionary key.
        pauses.updateValue(identity, forKey: token)
        let active = jobs.filter { identity == nil || $0.key == identity }.map(\.value)
        for job in active { job.cancel() }
        for job in active { await job.finished.value }
        return token
    }

    static func resume(_ token: UUID) { pauses.removeValue(forKey: token) }

    private static func isPaused(_ identity: ArchiveIdentity) -> Bool {
        pauses.values.contains { $0 == nil || $0 == identity }
    }
}

struct ArchiveRefreshResult: Sendable {
    let manifest: ArchiveCache.Manifest
    let indexedCount: Int
    let report: ArchiveRefreshReport
    let status: String
}

@MainActor
private enum ArchiveRefreshEngine {
    static func run(client: any ArchiveReading, cache: ArchiveCache, index: ArchiveSearchIndex?, scope: ArchiveRefreshScope,
                    progress: @escaping @MainActor @Sendable (String) -> Void) async throws -> ArchiveRefreshResult {
        let previous = try await cache.load()
        progress(archiveText("Checking archive…", "Archiv wird geprüft …"))
        let inventory = try await client.snapshot(updating: previous.snapshot, requestLimit: scope.inventoryRequestLimit)
        try Task.checkCancellation()
        let previousIndexCount = (try? await index?.count()) ?? 0
        if previous.snapshot?.commit == inventory.commit, previous.metadataComplete, previous.indexComplete == true,
           previousIndexCount == previous.clips.count {
            try await cache.checked(inventory)
            try Task.checkCancellation()
            return ArchiveRefreshResult(manifest: try await cache.load(), indexedCount: previousIndexCount,
                                        report: .init(state: .unchanged, processed: 0, remaining: 0),
                                        status: archiveText("Up to date", "Aktuell"))
        }
        try await cache.begin(inventory)
        try Task.checkCancellation()
        var indexFailed = false
        var indexed: [String: String] = [:]
        do {
            try await index?.reconcile(inventory.files)
            indexed = try await index?.indexedFiles() ?? [:]
        } catch { indexFailed = true }
        try Task.checkCancellation()
        var metadata = Dictionary(previous.clips.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let markdown = inventory.files.filter { $0.path.lowercased().hasSuffix(".md") }
        let pending = markdown.filter { metadata[$0.path]?.sha != $0.sha || indexed[$0.path] != $0.sha }.sorted {
            let lhs = metadata[$0.path]?.sha == $0.sha ? metadata[$0.path]! : ClipMetadataReader.read("", file: $0)
            let rhs = metadata[$1.path]?.sha == $1.sha ? metadata[$1.path]! : ClipMetadataReader.read("", file: $1)
            return ArchiveClip.newestFirst(lhs, rhs)
        }
        // A previous launch may have committed only part of its initial seed.
        // Resume up to seven total loaded clips, rather than fetching seven more
        // every time an interrupted launch returns to the foreground.
        let loadedCount = markdown.filter { metadata[$0.path]?.sha == $0.sha && indexed[$0.path] == $0.sha }.count
        let fileLimit = scope == .bootstrap ? max(0, scope.fileLimit - loadedCount) : scope.fileLimit
        var attempted = 0, processed = 0, failed = 0, consumedBytes = 0
        for file in pending {
            try Task.checkCancellation()
            guard attempted < fileLimit, consumedBytes < scope.byteLimit else { break }
            // Declared sizes bound a scheduled batch before any body request is made.
            if file.size > scope.byteLimit - consumedBytes { continue }
            attempted += 1
            progress("\(attempted) / \(min(pending.count, fileLimit))")
            do {
                guard file.size >= 0, file.size <= ArchiveReadClient.markdownLimit else { throw ArchiveError.tooLarge }
                let available = scope.byteLimit - consumedBytes
                let allowance = min(ArchiveReadClient.markdownLimit, file.size > 0 ? file.size : available)
                // Charge before fetching so invalid responses, decoding errors, and failed
                // reads still consume the batch budget. A zero size reserves its whole allowance.
                let reservation = file.size > 0 ? file.size : allowance
                consumedBytes += reservation
                let bytes: Data
                if let local = try await cache.data(sha: file.sha, limit: allowance) { bytes = local }
                else { bytes = try await client.read(file, limit: allowance) }
                try Task.checkCancellation()
                consumedBytes += max(0, bytes.count - reservation)
                guard bytes.count <= allowance, consumedBytes <= scope.byteLimit,
                      let raw = String(data: bytes, encoding: .utf8) else { throw ArchiveError.tooLarge }
                let clip = ClipMetadataReader.read(raw, file: file)
                try await cache.add(clip, raw: bytes)
                try Task.checkCancellation()
                metadata[clip.path] = clip
                do {
                    try await index?.update(clip)
                    if index != nil { indexed[clip.path] = clip.sha }
                } catch { indexFailed = true }
                processed += 1
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                failed += 1
                // Keep failed known paths selectable without inventing their provenance.
                let placeholder = ClipMetadataReader.read("", file: file)
                try await cache.addMetadata(placeholder)
                metadata[file.path] = placeholder
            }
        }
        try Task.checkCancellation()
        let remaining = markdown.filter { metadata[$0.path]?.sha != $0.sha || indexed[$0.path] != $0.sha }.count
        let complete = remaining == 0 && failed == 0 && !indexFailed
        try await cache.finish(complete: complete, indexComplete: complete)
        try Task.checkCancellation()
        var status = complete ? archiveText("Up to date", "Aktuell") : archiveText("\(remaining) articles pending. Search covers downloaded articles.", "\(remaining) Beiträge ausstehend. Die Suche umfasst geladene Beiträge.")
        if failed > 0 { status += " · " + archiveText("\(failed) files could not be loaded.", "\(failed) Dateien konnten nicht geladen werden.") }
        if indexFailed { status += " · " + archiveText("Search cache is partial. Refresh to retry.", "Suchcache ist unvollständig. Zum Wiederholen aktualisieren.") }
        return ArchiveRefreshResult(manifest: try await cache.load(), indexedCount: (try? await index?.count()) ?? 0,
                                    report: .init(state: failed == 0 && !indexFailed ? .refreshed : .failed, processed: processed, remaining: remaining), status: status)
    }
}

@MainActor
enum ArchiveBackgroundRefresh {
    static let identifier = "de.patrickschiller.sourcebraid.archive.refresh"
    private static var registered = false
    private static var active: Task<ArchiveRefreshReport, Never>?
    private static var notificationTokens: [NSObjectProtocol] = []
    private static var generation = UUID()
    private static var permitsScheduling = true

    private static var isDemo: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["SOURCEBRAID_DEMO"] == "1"
#else
        false
#endif
    }

    static func register() {
        guard !registered, !isDemo else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in await handle(task) }
        }
        guard registered else { return }
        for name in [Notification.Name.archiveDataRemoved, .sourceBraidConfigurationChanged] {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                let signOut = notification.userInfo?["signOut"] as? Bool ?? false
                Task { @MainActor in
                    if signOut { permitsScheduling = false }
                    else if notification.name == .sourceBraidConfigurationChanged { permitsScheduling = true }
                    await invalidateAndWait()
                    if signOut || notification.name == .archiveDataRemoved { cancel() }
                    else { schedule() }
                }
            })
        }
    }

    static func schedule() {
        guard registered, permitsScheduling, !isDemo, SourceBraidSettings.load().isComplete else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // This is a minimum delay. iOS chooses whether and when the refresh runs.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* Disabled background refresh and simulator scheduling are normal. Manual refresh remains available. */ }
    }

    static func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }

    static func invalidateAndWait() async {
        generation = UUID()
        let previous = active
        previous?.cancel()
        _ = await previous?.value
        let pause = await ArchiveRefreshCoordinator.pause()
        ArchiveRefreshCoordinator.resume(pause)
    }

    private static func handle(_ task: BGAppRefreshTask) async {
        guard !isDemo, active == nil else { task.setTaskCompleted(success: false); return }
        let epoch = generation
        let work = Task { @MainActor in
            let library = ArchiveLibrary()
            await library.configure(bootstrapIfEmpty: false)
            return await library.refreshInBackground()
        }
        active = work
        task.expirationHandler = { work.cancel() }
        // Leave time for cancellation and task completion within the OS refresh window.
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)
            if !Task.isCancelled { work.cancel() }
        }
        let report = await work.value
        timeout.cancel(); task.expirationHandler = nil; active = nil
        task.setTaskCompleted(success: report.succeeded)
        if generation == epoch, permitsScheduling, SourceBraidSettings.load().isComplete { schedule() }
    }
}
