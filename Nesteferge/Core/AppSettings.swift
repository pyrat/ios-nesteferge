import Foundation
import Observation

/// App configuration and the small amount of state that must outlive a launch.
///
/// The API address is fixed at build time — there is deliberately no in-app
/// editor for it. Only the user's last ferry choice is persisted, in
/// `UserDefaults`, so the CarPlay scene and the phone UI agree on it.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// The Nesteferge API, baked in from the `NESTEFERGE_API_BASE_URL` build
    /// setting via the `NestefergeAPIBaseURL` Info.plist key.
    ///
    /// To develop against a local `cmd/ferrytimes-api`, change that build setting
    /// to `http://localhost:8000`; the ATS exception in Info.plist permits the
    /// plain-HTTP load. The literal below is the fallback for when the setting is
    /// missing or left unexpanded (Info.plist keeps the raw `$(...)` token then).
    static let baseURL: URL = {
        let fallback = URL(string: "https://nesteferge.no")!
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "NestefergeAPIBaseURL") as? String
        else { return fallback }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return fallback }

        return url
    }()

    private enum Keys {
        static let selection = "nesteferge.selection"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Instance accessor, so call sites and tests need not reach for the type.
    var baseURL: URL { Self.baseURL }

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
