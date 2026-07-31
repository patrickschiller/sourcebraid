import Foundation

struct RecentCapture: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let path: String
    let savedAt: Date

    init(id: UUID = UUID(), title: String, path: String, savedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.path = path
        self.savedAt = savedAt
    }
}

enum RecentCaptureStore {
    static func load() -> [RecentCapture] {
        guard let defaults = UserDefaults(suiteName: SourceBraidEnvironment.appGroupIdentifier),
              let data = defaults.data(forKey: SourceBraidEnvironment.recentCapturesKey),
              let values = try? JSONDecoder().decode([RecentCapture].self, from: data) else {
            return []
        }
        return values
    }

    static func add(_ capture: RecentCapture) {
        guard let defaults = UserDefaults(suiteName: SourceBraidEnvironment.appGroupIdentifier) else {
            return
        }
        var values = load()
        values.removeAll { $0.path == capture.path }
        values.insert(capture, at: 0)
        values = Array(values.prefix(20))
        if let data = try? JSONEncoder().encode(values) {
            defaults.set(data, forKey: SourceBraidEnvironment.recentCapturesKey)
        }
    }
}
