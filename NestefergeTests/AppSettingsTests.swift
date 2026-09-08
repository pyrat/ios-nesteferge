import Foundation
import Testing

@testable import Nesteferge

@Suite("Settings")
struct AppSettingsTests {

    private func makeSettings() -> AppSettings {
        // Isolated suite so tests never touch the real app's stored preferences.
        let name = "nesteferge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return AppSettings(defaults: defaults)
    }

    @Test("The base URL is a usable https endpoint")
    func baseURLIsUsable() {
        let url = AppSettings.baseURL
        #expect(url.scheme == "https" || url.scheme == "http")
        #expect(url.host?.isEmpty == false)
    }

    @Test("The base URL matches the value baked into Info.plist")
    func baseURLMatchesBundle() {
        // Guards against the Swift fallback and the NESTEFERGE_API_BASE_URL build
        // setting drifting apart: a test build should read the configured value,
        // not silently fall back.
        let raw = Bundle(for: BundleMarker.self)
            .object(forInfoDictionaryKey: "NestefergeAPIBaseURL") as? String
        guard let raw, !raw.hasPrefix("$("), !raw.isEmpty else { return }
        #expect(AppSettings.baseURL.absoluteString == raw)
    }

    @Test("The base URL is identical for every instance")
    func baseURLIsFixed() {
        // There is no in-app editor any more, so this must not vary by instance
        // or by whatever happens to be in UserDefaults.
        #expect(makeSettings().baseURL == makeSettings().baseURL)
        #expect(makeSettings().baseURL == AppSettings.baseURL)
    }

    @Test("Selection round-trips, and nil clears it")
    func selectionRoundTrip() {
        let settings = makeSettings()
        #expect(settings.loadSelection() == nil)

        let selection = FerrySelection(
            routeID: 154,
            routeName: "Festøya–Solavågen",
            origin: "Festøya",
            destination: "Solavågen"
        )
        settings.saveSelection(selection)
        #expect(settings.loadSelection() == selection)

        settings.saveSelection(nil)
        #expect(settings.loadSelection() == nil)
    }

    @Test("Selection persists across instances sharing a defaults suite")
    func selectionPersists() {
        let name = "nesteferge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        let selection = FerrySelection(
            routeID: 7,
            routeName: "Molde–Vestnes",
            origin: "Molde",
            destination: "Vestnes"
        )
        AppSettings(defaults: defaults).saveSelection(selection)

        #expect(AppSettings(defaults: defaults).loadSelection() == selection)
    }

    @Test("A one-sided selection still describes itself sensibly")
    func legDescriptionWithoutDestination() {
        let selection = FerrySelection(routeID: 1, routeName: "R", origin: "Festøya", destination: nil)
        #expect(selection.legDescription == "Festøya")
    }
}

/// Anchor for locating the app bundle from the test bundle.
private final class BundleMarker {}
