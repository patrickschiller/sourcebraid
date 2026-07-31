import Foundation

struct GitHubClient {
    let configuration: SourceBraidConfiguration
    let token: String
    var session: URLSession = .shared

    func testConnection() async throws {
        let path = "/repos/\(encoded(configuration.owner))/\(encoded(configuration.repository))"
        let (_, response) = try await request(path: path, method: "GET")
        guard response.statusCode == 200 else {
            throw try githubError(response: response, data: Data(), fallback: "Repository connection failed")
        }
    }

    func save(_ draft: CaptureDraft) async throws {
        if let attachment = draft.attachment {
            try await putReplacing(path: attachment.path, data: attachment.data, message: "Save SourceBraid attachment: \(draft.title)")
        }
        try await putReplacing(path: draft.path, data: Data(draft.markdown.utf8), message: "Save SourceBraid capture: \(draft.title)")
        try await updateIndex(with: draft.indexEntry)
    }

    private func updateIndex(with entry: SourceBraidIndexEntry) async throws {
        let indexPath = "\(configuration.rootFolder)/index/\(urlHash(entry.url).prefix(2)).jsonl"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encodedEntry = try encoder.encode(entry)
        guard let entryLine = String(data: encodedEntry, encoding: .utf8) else {
            throw GitHubClientError.invalidResponse
        }

        for attempt in 0..<3 {
            let existing = try await getContent(path: indexPath)
            let existingText: String
            if let data = existing?.data {
                existingText = String(data: data, encoding: .utf8) ?? ""
            } else {
                existingText = ""
            }
            let lines = existingText
                .split(separator: "\n")
                .map(String.init)
                .filter { line in
                    guard let data = line.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        return false
                    }
                    return object["url"] as? String != entry.url && object["path"] as? String != entry.path
                }
            let next = (lines + [entryLine]).joined(separator: "\n") + "\n"
            do {
                try await putContent(
                    path: indexPath,
                    data: Data(next.utf8),
                    message: "Update SourceBraid index: \(entry.title)",
                    sha: existing?.sha
                )
                return
            } catch GitHubClientError.httpStatus(let status, _) where status == 409 && attempt < 2 {
                continue
            }
        }
        throw GitHubClientError.conflict
    }

    private func putReplacing(path: String, data: Data, message: String) async throws {
        let existing = try await getContent(path: path)
        try await putContent(path: path, data: data, message: message, sha: existing?.sha)
    }

    private func getContent(path: String) async throws -> GitHubContent? {
        let query = "?ref=\(encoded(configuration.branch))"
        let (data, response) = try await request(path: contentsPath(path) + query, method: "GET")
        if response.statusCode == 404 {
            return nil
        }
        guard response.statusCode == 200 else {
            throw try githubError(response: response, data: data, fallback: "Could not read \(path)")
        }
        let value = try JSONDecoder().decode(GitHubContentResponse.self, from: data)
        guard let decoded = Data(base64Encoded: value.content.replacingOccurrences(of: "\n", with: "")) else {
            throw GitHubClientError.invalidResponse
        }
        return GitHubContent(sha: value.sha, data: decoded)
    }

    private func putContent(path: String, data: Data, message: String, sha: String?) async throws {
        let body = GitHubPutRequest(
            message: message,
            content: data.base64EncodedString(),
            branch: configuration.branch,
            sha: sha
        )
        let requestData = try JSONEncoder().encode(body)
        let (responseData, response) = try await request(path: contentsPath(path), method: "PUT", body: requestData)
        guard (200...201).contains(response.statusCode) else {
            throw try githubError(response: response, data: responseData, fallback: "Could not write \(path)")
        }
    }

    private func contentsPath(_ path: String) -> String {
        let encodedPath = path.split(separator: "/").map { encoded(String($0)) }.joined(separator: "/")
        return "/repos/\(encoded(configuration.owner))/\(encoded(configuration.repository))/contents/\(encodedPath)"
    }

    private func request(path: String, method: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw GitHubClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("SourceBraid-iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }
        return (data, http)
    }

    private func githubError(response: HTTPURLResponse, data: Data, fallback: String) throws -> GitHubClientError {
        let message = (try? JSONDecoder().decode(GitHubErrorResponse.self, from: data).message) ?? fallback
        return .httpStatus(response.statusCode, message)
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?"))) ?? value
    }

    private func urlHash(_ value: String) -> String {
        var hash: UInt32 = 0x811c9dc5
        for unit in value.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x01000193
        }
        return String(format: "%08x", hash).prefix(6).description
    }
}

private struct GitHubContent {
    let sha: String
    let data: Data
}

private struct GitHubContentResponse: Decodable {
    let sha: String
    let content: String
}

private struct GitHubPutRequest: Encodable {
    let message: String
    let content: String
    let branch: String
    let sha: String?
}

private struct GitHubErrorResponse: Decodable {
    let message: String
}

enum GitHubClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case conflict

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The GitHub API URL is invalid."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .httpStatus(let status, let message):
            return "GitHub error \(status): \(message)"
        case .conflict:
            return "The SourceBraid index changed repeatedly. Please try saving again."
        }
    }
}
