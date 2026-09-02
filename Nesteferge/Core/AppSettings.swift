import Foundation
import Observation

/// User-adjustable configuration, persisted in `UserDefaults` so the CarPlay
/// scene and the phone UI read the same values.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Compiled-in fallback. Override at runtime in the app's Settings screen,
    /// or at build time via the `NESTEFERGE_API_BASE_URL` Info.plist value.
    static let defaultBaseURLString: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "NestefergeAPIBaseURL") as? String,
           !value.trimmingCharacters(in: .whitespaces).isEmpty,
           !value.hasPrefix("$(") {
            return value
        }
        return "http://localhost:8000"
    }()

    private enum Keys {
        static let baseURL = "nesteferge.apiBaseURL"
        static let selection = "nesteferge.selection"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.baseURLString = defaults.string(forKey: Keys.baseURL) ?? Self.defaultBaseURLString
    }

    var baseURLString: String {
        didSet {
            guard baseURLString != oldValue else { return }
            defaults.set(baseURLString, forKey: Keys.baseURL)
        }
    }

    /// The configured base URL, falling back to the default when the user has
    /// typed something unusable.
    var baseURL: URL {
        Self.normalizedURL(from: baseURLString)
            ?? Self.normalizedURL(from: Self.defaultBaseURLString)
            ?? URL(string: "http://localhost:8000")!
    }

    var isBaseURLValid: Bool {
        Self.normalizedURL(from: baseURLString) != nil
    }

    func resetBaseURL() {
        baseURLString = Self.defaultBaseURLString
    }

    /// Accepts `host:port` as well as full URLs, and rejects anything without a host.
    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    // MARK: - Last selection

    func loadSelection() -> FerrySelection? {
        guard let data = defaults.data(forKey: Keys.selection) else { return nil }
        return try? JSONDecoder().decode(FerrySelection.self, from: data)
    }

    func saveSelection(_ selection: FerrySelection?) {
        guard let selection, let data = try? JSONEncoder().encode(selection) else {
            defaults.removeObject(forKey: Keys.selection)
            return
        }
        defaults.set(data, forKey: Keys.selection)
    }
}
