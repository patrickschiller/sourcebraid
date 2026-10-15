import Foundation
import CryptoKit

protocol ArchiveReading: Sendable {
    func snapshot() async throws -> ArchiveSnapshot
    func snapshot(updating previous: ArchiveSnapshot?, requestLimit: Int?) async throws -> ArchiveSnapshot
    func read(_ file: ArchiveFile, limit: Int) async throws -> Data
}

extension ArchiveReading {
    func snapshot(updating previous: ArchiveSnapshot?, requestLimit: Int?) async throws -> ArchiveSnapshot {
        try await snapshot()
    }
}

final class ArchiveRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Authenticated archive requests never follow redirects, even to another GitHub host.
        completionHandler(nil)
    }
}

enum ArchiveExternalImageLoader {
    static func read(_ url: URL) async throws -> (Data, String) {
        guard url.scheme == "https", ArchivePath.externalURL(url.absoluteString) != nil else { throw ArchiveError.invalidPath }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: ArchiveRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let type = response.mimeType, ["image/png", "image/jpeg", "image/gif", "image/webp", "image/heic"].contains(type),
              response.expectedContentLength <= ArchiveReadClient.assetLimit else { throw ArchiveError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < ArchiveReadClient.assetLimit else { throw ArchiveError.tooLarge }
            data.append(byte)
        }
        return (data, type)
    }
}

final class ArchiveReadClient: ArchiveReading, @unchecked Sendable {
    static let markdownLimit = 5 * 1024 * 1024
    static let assetLimit = 20 * 1024 * 1024
    let identity: ArchiveIdentity
    private let token: String
    private let session: URLSession

    init(identity: ArchiveIdentity, token: String, session: URLSession? = nil) {
        self.identity = identity; self.token = token
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false; configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: configuration, delegate: ArchiveRedirectPolicy(), delegateQueue: nil)
        }
    }
    deinit { session.invalidateAndCancel() }

    func snapshot() async throws -> ArchiveSnapshot {
        try await snapshot(updating: nil, requestLimit: nil)
    }

    func snapshot(updating previous: ArchiveSnapshot?, requestLimit: Int? = nil) async throws -> ArchiveSnapshot {
        struct Commit: Decodable {
            struct Details: Decodable { struct Tree: Decodable { let sha: String }; let tree: Tree }
            let sha: String; let commit: Details
        }
        let budget = requestLimit.map { RequestBudget(remaining: max(1, $0)) }
        let commit: Commit = try await json(["commits", identity.branch], budget: budget)
        guard Self.validSHA(commit.sha), Self.validSHA(commit.commit.tree.sha) else { throw ArchiveError.invalidResponse }
        // A stable commit is sufficient to reuse its immutable inventory. Do not walk trees again.
        if let previous, previous.identity == identity, previous.commit == commit.sha {
            return ArchiveSnapshot(identity: identity, commit: commit.sha, files: previous.files, checkedAt: Date())
        }
        var treeSHA = commit.commit.tree.sha
        for component in identity.root.split(separator: "/") {
            let tree: Tree = try await json(["git", "trees", treeSHA], budget: budget)
            guard !tree.truncated else { throw ArchiveError.incompleteTree }
            guard let child = tree.tree.first(where: { $0.path == component && $0.type == "tree" && $0.mode == "040000" }) else {
                throw ArchiveError.http(404)
            }
            treeSHA = child.sha
            guard Self.validSHA(treeSHA) else { throw ArchiveError.invalidResponse }
        }
        let tree: Tree = try await json(["git", "trees", treeSHA], query: [URLQueryItem(name: "recursive", value: "1")], budget: budget)
        let entries: [Entry]
        if tree.truncated {
            var requests = 0
            entries = try await walk(treeSHA, prefix: "", requests: &requests, budget: budget)
        } else { entries = tree.tree }
        guard entries.count <= 100_000 else { throw ArchiveError.incompleteTree }
        let files = try entries.filter { $0.type == "blob" && ["100644", "100755"].contains($0.mode) }.map {
            let path = try ArchivePath.normalize(identity.root + "/" + $0.path)
            guard ArchivePath.isInside(path, root: identity.root), Self.validSHA($0.sha) else { throw ArchiveError.invalidResponse }
            return ArchiveFile(path: path, sha: $0.sha, size: $0.size ?? 0)
        }
        return ArchiveSnapshot(identity: identity, commit: commit.sha, files: files, checkedAt: Date())
    }

    private func walk(_ sha: String, prefix: String, requests: inout Int, budget: RequestBudget?) async throws -> [Entry] {
        requests += 1
        guard requests <= 2048 else { throw ArchiveError.incompleteTree }
        let tree: Tree = try await json(["git", "trees", sha], budget: budget)
        guard !tree.truncated else { throw ArchiveError.incompleteTree }
        var result: [Entry] = []
        for entry in tree.tree {
            try Task.checkCancellation()
            let path = prefix + entry.path
            if entry.type == "tree" && entry.mode == "040000" {
                guard Self.validSHA(entry.sha) else { throw ArchiveError.invalidResponse }
                result += try await walk(entry.sha, prefix: path + "/", requests: &requests, budget: budget)
            } else {
                result.append(Entry(path: path, mode: entry.mode, type: entry.type, sha: entry.sha, size: entry.size))
            }
            guard result.count <= 100_000 else { throw ArchiveError.incompleteTree }
        }
        return result
    }

    func read(_ file: ArchiveFile, limit: Int = markdownLimit) async throws -> Data {
        guard ArchivePath.isInside(file.path, root: identity.root), Self.validSHA(file.sha), file.size >= 0 else { throw ArchiveError.invalidPath }
        guard file.size <= limit else { throw ArchiveError.tooLarge }
        struct Blob: Decodable { let content: String; let encoding: String; let sha: String }
        // GitHub base64 uses wrapped lines, whose JSON escapes also consume bytes.
        let envelope = try await request(["git", "blobs", file.sha], limit: limit * 3 / 2 + 8192)
        let blob = try JSONDecoder().decode(Blob.self, from: envelope)
        guard blob.encoding == "base64", blob.sha == file.sha,
              let bytes = Data(base64Encoded: blob.content, options: .ignoreUnknownCharacters) else { throw ArchiveError.invalidResponse }
        guard bytes.count <= limit else { throw ArchiveError.tooLarge }
        // A blob SHA binds this read to the inventory's immutable content.
        let gitObject = Data("blob \(bytes.count)\0".utf8) + bytes
        let digest = Insecure.SHA1.hash(data: gitObject).map { String(format: "%02x", $0) }.joined()
        guard bytes.count == file.size, digest == file.sha else { throw ArchiveError.invalidResponse }
        return bytes
    }

    private func json<T: Decodable>(_ path: [String], query: [URLQueryItem] = [], budget: RequestBudget? = nil) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request(path, query: query, limit: 8 * 1024 * 1024, budget: budget))
    }

    private func request(_ path: [String], query: [URLQueryItem] = [], limit: Int, budget: RequestBudget? = nil) async throws -> Data {
        guard !token.isEmpty else { throw ArchiveError.missingCredentials }
        var components = URLComponents()
        components.scheme = "https"; components.host = "api.github.com"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let segments = ["repos", identity.owner, identity.repository] + path
        components.percentEncodedPath = "/" + segments.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw ArchiveError.invalidPath }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SourceBraid-iOS-Reader", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<3 {
            try Task.checkCancellation()
            try await budget?.consume()
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, response.url?.host == "api.github.com" else { throw ArchiveError.invalidResponse }
            if response.statusCode == 403 && response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw ArchiveError.rateLimited
            }
            if [429, 503].contains(response.statusCode) || (response.statusCode == 403 && response.value(forHTTPHeaderField: "Retry-After") != nil) {
                guard attempt < 2 else { throw ArchiveError.http(response.statusCode) }
                let seconds = min(60, max(1, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(2 << attempt)))
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); continue
            }
            guard response.statusCode == 200 else { throw ArchiveError.http(response.statusCode) }
            if response.expectedContentLength > Int64(limit) { throw ArchiveError.tooLarge }
            var result = Data()
            for try await byte in bytes {
                guard result.count < limit else { throw ArchiveError.tooLarge }
                result.append(byte)
            }
            return result
        }
        throw ArchiveError.invalidResponse
    }

    static func validSHA(_ sha: String) -> Bool {
        sha.count == 40 && sha.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
    private struct Tree: Decodable { let tree: [Entry]; let truncated: Bool }
    private struct Entry: Decodable {
        let path: String; let mode: String; let type: String; let sha: String; let size: Int?
    }
    private actor RequestBudget {
        private var remaining: Int
        init(remaining: Int) { self.remaining = remaining }
        func consume() throws {
            try Task.checkCancellation()
            guard remaining > 0 else { throw ArchiveError.incompleteTree }
            remaining -= 1
        }
    }
}
