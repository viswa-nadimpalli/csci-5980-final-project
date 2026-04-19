import Foundation

enum PatchPalsShared {
    static let appGroupIdentifier = "group.mlsv.PatchPals.shared"
    static let loggedInUserIDKey = "loggedInUserID"
}

enum SessionStore {
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: PatchPalsShared.appGroupIdentifier) ?? .standard
    }

    static var loggedInUserID: String? {
        get {
            let value = defaults.string(forKey: PatchPalsShared.loggedInUserIDKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                defaults.set(trimmed, forKey: PatchPalsShared.loggedInUserIDKey)
            } else {
                defaults.removeObject(forKey: PatchPalsShared.loggedInUserIDKey)
            }
        }
    }
}
