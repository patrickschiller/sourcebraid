import Foundation

enum SourceBraidEnvironment {
    static let appGroupIdentifier = "group.de.patrickschiller.sourcebraid"
    static let keychainService = "de.patrickschiller.sourcebraid"
    static let keychainAccount = "github-token"
    static let recentCapturesKey = "recent-captures"

    static var keychainAccessGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SourceBraidKeychainAccessGroup") as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }
        return value
    }
}
