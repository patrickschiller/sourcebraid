import Foundation
import CryptoKit

func archiveText(_ english: String, _ german: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("de") == true ? german : english
}

struct ArchiveIdentity: Codable, Hashable, Sendable {
    let owner: String
    let repository: String
    let branch: String
    let root: String

    init(configuration: SourceBraidConfiguration) throws {
        let value = configuration.normalized()
        let component = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        guard value.isComplete,
              [value.owner, value.repository].allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(component.contains) }),
              value.branch.rangeOfCharacter(from: .controlCharacters) == nil else { throw ArchiveError.invalidPath }
        owner = value.owner; repository = value.repository; branch = value.branch
        root = try ArchivePath.normalize(configuration.rootFolder.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var cacheKey: String {
        // Hash an explicit length-prefixed identity, independent of JSON key order.
        let value = ["github.com", owner.lowercased(), repository.lowercased(), branch, root]
            .map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum ArchivePath {
    static func normalize(_ path: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              path.rangeOfCharacter(from: .controlCharacters) == nil else { throw ArchiveError.invalidPath }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !path.contains("%") else { throw ArchiveError.invalidPath }
        return components.map(String.init).joined(separator: "/")
    }

    static func isInside(_ path: String, root: String) -> Bool {
        (try? normalize(path)) == path && path.hasPrefix(root + "/")
    }

    static func resolve(_ relative: String, from path: String, root: String) throws -> String {
        guard !relative.hasPrefix("/"), !relative.contains(":"), !relative.contains("\\"),
              relative.rangeOfCharacter(from: .controlCharacters) == nil,
              let decoded = relative.removingPercentEncoding, !decoded.contains("%"),
              !decoded.hasPrefix("/"), !decoded.contains(":"), !decoded.contains("\\") else { throw ArchiveError.invalidPath }
        var parts = path.split(separator: "/").dropLast().map(String.init)
        for part in decoded.split(separator: "/") {
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { throw ArchiveError.invalidPath }
                parts.removeLast()
            } else { parts.append(String(part)) }
        }
        let resolved = try normalize(parts.joined(separator: "/"))
        guard isInside(resolved, root: root) else { throw ArchiveError.invalidPath }
        return resolved
    }

    static func externalURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

struct ArchiveFile: Codable, Hashable, Sendable {
    let path: String
    let sha: String
    let size: Int
}

struct ArchiveSnapshot: Codable, Equatable, Sendable {
    let identity: ArchiveIdentity
    let commit: String
    let files: [ArchiveFile]
    let checkedAt: Date
    func githubURL(for path: String) -> URL? {
        guard ArchiveReadClient.validSHA(commit), ArchivePath.isInside(path, root: identity.root),
              files.contains(where: { $0.path == path }) else { return nil }
        let segments = [identity.owner, identity.repository, "blob", commit] + path.split(separator: "/").map(String.init)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return URL(string: "https://github.com/" + segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }.joined(separator: "/"))
    }
}

struct ArchiveClip: Codable, Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let sha: String
    let title: String
    let titleIsFilename: Bool
    let sourceURL: String?
    let author: String?
    let captureMethod: String?
    let conversionStatus: String?
    let tags: [String]
    let sortDate: Date?
    let dateLabel: String?
    let datePrecision: String?
    let dateSource: String?
    let body: String

    func withBody(_ value: String) -> Self {
        Self(path: path, sha: sha, title: title, titleIsFilename: titleIsFilename,
             sourceURL: sourceURL, author: author, captureMethod: captureMethod,
             conversionStatus: conversionStatus, tags: tags, sortDate: sortDate,
             dateLabel: dateLabel, datePrecision: datePrecision, dateSource: dateSource, body: value)
    }

    static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.sortDate != rhs.sortDate {
            return (lhs.sortDate ?? .distantPast) > (rhs.sortDate ?? .distantPast)
        }
        return lhs.path.utf8.lexicographicallyPrecedes(rhs.path.utf8)
    }
}

/// Reads the scalar/list subset written by SourceBraid, without executing YAML tags.
/// Unsupported metadata stays in the immutable raw document; never guess provenance.
enum ClipMetadataReader {
    static func read(_ markdown: String, file: ArchiveFile) -> ArchiveClip {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var body = normalized, fields: [String: String] = [:], tags: [String] = []
        if normalized.hasPrefix("---\n"), let end = normalized.range(of: "\n---", range: normalized.index(normalized.startIndex, offsetBy: 4)..<normalized.endIndex),
           end.upperBound == normalized.endIndex || normalized[end.upperBound] == "\n" {
            let header = normalized[normalized.index(normalized.startIndex, offsetBy: 4)..<end.lowerBound]
            body = String(normalized[end.upperBound...]).trimmingCharacters(in: .newlines)
            var inTags = false
            for line in header.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = line.trimmingCharacters(in: .whitespaces)
                if inTags && text.hasPrefix("- ") { tags.append(scalar(String(text.dropFirst(2)))); continue }
                if line.hasPrefix(" ") || line.hasPrefix("\t") { continue }
                inTags = false
                guard let separator = text.firstIndex(of: ":") else { continue }
                let key = String(text[..<separator])
                let raw = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                if key == "tags" {
                    inTags = raw.isEmpty
                    if let data = raw.data(using: .utf8), let list = try? JSONDecoder().decode([String].self, from: data) { tags = list }
                    else if raw.hasPrefix("["), raw.hasSuffix("]") { tags = raw.dropFirst().dropLast().split(separator: ",").map { scalar(String($0)) } }
                } else if !raw.isEmpty && !["null", "~", "|", ">"].contains(raw) && !raw.hasPrefix("!") {
                    fields[key] = scalar(raw)
                }
            }
        }
        let timestamp = fields["captured_at"].flatMap(parseTimestamp)
        let legacyDay = fields["capture_method"] != nil ? fields["date"] : nil
        let dated = [("capture_date", fields["capture_date"]), ("date", legacyDay), ("path", pathDate(file.path))].first { $0.1.flatMap(parseDay) != nil }
        let day = dated?.1
        let title = fields["title"].flatMap { $0.isEmpty ? nil : $0 }
        return ArchiveClip(path: file.path, sha: file.sha,
            title: title ?? URL(fileURLWithPath: file.path).lastPathComponent,
            titleIsFilename: title == nil, sourceURL: fields["canonical_url"] ?? fields["url"],
            author: fields["author"], captureMethod: fields["capture_method"],
            conversionStatus: fields["conversion_status"], tags: tags,
            sortDate: timestamp ?? day.flatMap(parseDay), dateLabel: timestamp != nil ? fields["captured_at"] : day,
            datePrecision: timestamp != nil ? "timestamp" : (day == nil ? nil : "day"), dateSource: timestamp != nil ? "captured_at" : dated?.0, body: body)
    }

    static func scalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\""), let data = trimmed.data(using: .utf8), let decoded = try? JSONDecoder().decode(String.self, from: data) { return decoded }
        if trimmed.hasPrefix("'"), trimmed.hasSuffix("'") { return String(trimmed.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return trimmed
    }

    static func parseTimestamp(_ value: String) -> Date? {
        guard value.range(of: "(?:Z|[+-][0-9]{2}:[0-9]{2})$", options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func parseDay(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    private static func pathDate(_ path: String) -> String? {
        let name = path.split(separator: "/").last.map(String.init) ?? ""
        return name.count >= 10 ? String(name.prefix(10)) : nil
    }
}

enum ArchiveError: LocalizedError, Equatable {
    case invalidPath, invalidResponse, invalidEncoding, tooLarge, incompleteTree, missingCredentials, noEvidence, unavailable, rateLimited, previewUnavailable
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidPath: return archiveText("Invalid archive path or link.", "Ungültiger Archivpfad oder Link.")
        case .invalidResponse: return archiveText("Invalid GitHub response.", "Ungültige GitHub-Antwort.")
        case .invalidEncoding: return archiveText("This Markdown file is not valid UTF-8. Open it on GitHub or save it as UTF-8.", "Diese Markdown-Datei ist kein gültiges UTF-8. Auf GitHub öffnen oder als UTF-8 speichern.")
        case .tooLarge: return archiveText("The local file or context limit was reached. Try a smaller file or question.", "Das lokale Datei- oder Kontextlimit wurde erreicht. Kleinere Datei oder Frage versuchen.")
        case .incompleteTree: return archiveText("Archive inventory is incomplete.", "Archivbestand ist unvollständig.")
        case .missingCredentials: return archiveText("Configure GitHub in Settings first.", "Zuerst GitHub in den Einstellungen konfigurieren.")
        case .noEvidence: return archiveText("No matching downloaded source. Search coverage may be incomplete.", "Keine passende geladene Quelle. Die Suchabdeckung ist möglicherweise unvollständig.")
        case .unavailable: return archiveText("Apple Intelligence is not available right now.", "Apple Intelligence ist derzeit nicht verfügbar.")
        case .previewUnavailable: return archiveText("No local preview for this file. You can open it on GitHub.", "Für diese Datei gibt es keine lokale Vorschau. Du kannst sie auf GitHub öffnen.")
        case .rateLimited: return archiveText("GitHub's rate limit was reached. Refresh later; downloaded clips remain available.", "Das GitHub-Anfragelimit wurde erreicht. Später aktualisieren; geladene Beiträge bleiben verfügbar.")
        case .http(let status): return archiveText("GitHub request failed (\(status)).", "GitHub-Anfrage fehlgeschlagen (\(status)).")
        }
    }
}
