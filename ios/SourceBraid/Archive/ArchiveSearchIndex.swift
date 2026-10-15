import Foundation
import SQLite3

struct ArchiveSearchHit: Sendable {
    let path: String
    let sha: String
    let title: String
    let body: String
}

actor ArchiveSearchIndex {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func update(_ clip: ArchiveClip) throws {
        try database { db in
            try execute(db, "BEGIN IMMEDIATE")
            do {
                try statement(db, "DELETE FROM clips WHERE path = ?", [clip.path]) { _ in }
                try statement(db, "INSERT INTO clips(path, sha, title, tags, body) VALUES(?, ?, ?, ?, ?)",
                              [clip.path, clip.sha, clip.title, (clip.tags + [clip.sourceURL ?? ""]).joined(separator: " "), clip.body]) { _ in }
                try execute(db, "COMMIT")
            } catch { try? execute(db, "ROLLBACK"); throw error }
        }
    }

    func reconcile(_ files: [ArchiveFile]) throws {
        let valid = Dictionary(files.map { ($0.path, $0.sha) }, uniquingKeysWith: { first, _ in first })
        try database { db in
            var obsolete: [String] = []
            try statement(db, "SELECT path, sha FROM clips", []) { row in
                if valid[string(row, 0)] != string(row, 1) { obsolete.append(string(row, 0)) }
            }
            for path in obsolete { try statement(db, "DELETE FROM clips WHERE path = ?", [path]) { _ in } }
        }
    }

    func search(_ query: String, limit: Int = 20) throws -> [ArchiveSearchHit] {
        let terms = Self.terms(query)
        guard !terms.isEmpty else { return [] }
        let match = terms.map { "\"\($0)\"" }.joined(separator: " OR ")
        return try database { db in
            var hits: [ArchiveSearchHit] = []
            try statement(db, "SELECT path, sha, title, body FROM clips WHERE clips MATCH ? ORDER BY bm25(clips), path LIMIT ?", [match, String(max(1, min(20, limit)))]) { row in
                hits.append(ArchiveSearchHit(path: string(row, 0), sha: string(row, 1), title: string(row, 2), body: string(row, 3)))
            }
            return hits
        }
    }

    func count() throws -> Int {
        try database { db in
            var count = 0
            try statement(db, "SELECT count(*) FROM clips", []) { count = Int(sqlite3_column_int64($0, 0)) }
            return count
        }
    }

    func indexedFiles() throws -> [String: String] {
        try database { db in
            var files: [String: String] = [:]
            try statement(db, "SELECT path, sha FROM clips", []) { files[string($0, 0)] = string($0, 1) }
            return files
        }
    }

    static func terms(_ query: String) -> [String] {
        let stop = Set(["the", "a", "an", "of", "in", "on", "and", "or", "to", "is", "are", "what", "how", "this", "that", "my", "about", "please", "die", "der", "das", "den", "dem", "ein", "eine", "und", "oder", "von", "zu", "ist", "sind", "wie", "was", "ich", "mein", "mir", "im", "mit", "bitte", "archiv", "archive"])
        return Array(query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stop.contains($0) }.prefix(32))
    }

    private func database<T>(_ action: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var db: OpaquePointer?
        guard sqlite3_open_v2(directory.appendingPathComponent("search.sqlite3").path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db else { throw ArchiveError.invalidResponse }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5000)
        // A bounded disposable index; SQLite reports FULL rather than growing without limit.
        try execute(db, "PRAGMA max_page_count=25600")
        var version: Int32 = 0
        try statement(db, "PRAGMA user_version", []) { version = sqlite3_column_int($0, 0) }
        if version != 1 {
            try execute(db, "DROP TABLE IF EXISTS clips")
            try execute(db, "CREATE VIRTUAL TABLE clips USING fts5(path UNINDEXED, sha UNINDEXED, title, tags, body, tokenize='unicode61')")
            try execute(db, "PRAGMA user_version=1")
        }
        return try action(db)
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw ArchiveError.invalidResponse }
    }
    private func statement(_ db: OpaquePointer, _ sql: String, _ values: [String], row: (OpaquePointer) throws -> Void) throws {
        var handle: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &handle, nil) == SQLITE_OK, let handle else { throw ArchiveError.invalidResponse }
        defer { sqlite3_finalize(handle) }
        for (offset, value) in values.enumerated() {
            guard sqlite3_bind_text(handle, Int32(offset + 1), value, -1, transient) == SQLITE_OK else { throw ArchiveError.invalidResponse }
        }
        while true {
            let result = sqlite3_step(handle)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw ArchiveError.invalidResponse }
            try row(handle)
        }
    }
    private func string(_ row: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(row, column).map { String(cString: $0) } ?? ""
    }
}

struct SourceExcerpt: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let sha: String
    let title: String
    let line: Int
    let text: String
}

enum ArchiveRetriever {
    static func excerpts(_ hits: [ArchiveSearchHit], question: String, characterBudget: Int = 4500) -> [SourceExcerpt] {
        let terms = ArchiveSearchIndex.terms(question)
        var remaining = characterBudget, results: [SourceExcerpt] = []
        for hit in hits.prefix(4) {
            guard remaining > 200 else { break }
            let lines = hit.body.components(separatedBy: "\n")
            let matching = lines.firstIndex { line in terms.contains { line.lowercased().contains($0) } } ?? 0
            var start = matching
            while start > 0 && !lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty && !lines[start].hasPrefix("#") { start -= 1 }
            let text = lines.dropFirst(start).prefix(24).joined(separator: "\n")
            let bounded = String(text.prefix(min(remaining, 1600)))
            remaining -= bounded.count
            results.append(SourceExcerpt(id: "S\(results.count + 1)", path: hit.path, sha: hit.sha, title: hit.title, line: start + 1, text: bounded))
        }
        return results
    }

    static func validateCitationIDs(_ ids: [String], sources: [SourceExcerpt]) throws -> [SourceExcerpt] {
        let allowed = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard !ids.isEmpty, ids.allSatisfy({ allowed[$0] != nil }) else { throw ArchiveError.noEvidence }
        return Array(Set(ids)).sorted().compactMap { allowed[$0] }
    }
}
