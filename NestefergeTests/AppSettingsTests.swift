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

    @Test("Bare host:port is upgraded to an http URL")
    func normalizesBareHost() {
        let url = AppSettings.normalizedURL(from: "localhost:8000")
        #expect(url?.absoluteString == "http://localhost:8000")
    }

    @Test("Explicit schemes are preserved")
    func preservesScheme() {
        #expect(AppSettings.normalizedURL(from: "https://api.example.com")?.scheme == "https")
    }

    @Test("Surrounding whitespace is trimmed")
    func trimsWhitespace() {
        #expect(AppSettings.normalizedURL(from: "  http://example.com  ")?.host == "example.com")
    }

    @Test("A bare word is accepted as an intranet hostname")
    func acceptsBareHostname() {
        // `http://nesteferge-box` is a legitimate address on a local network, so
        // this must not be rejected just because it has no dot.
        #expect(AppSettings.normalizedURL(from: "nesteferge-box")?.host == "nesteferge-box")
    }

    @Test("Unusable input is rejected", arguments: ["", "   ", "ftp://example.com", "not a url", "http://"])
    func rejectsBadInput(_ raw: String) {
        #expect(AppSettings.normalizedURL(from: raw) == nil)
    }

    @Test("An invalid stored value falls back to the default base URL")
    func fallsBackWhenInvalid() {
        let settings = makeSettings()
        settings.baseURLString = "ftp://example.com"
        #expect(settings.isBaseURLValid == false)
        #expect(settings.baseURL == AppSettings.normalizedURL(from: AppSettings.defaultBaseURLString))
    }

    @Test("Base URL persists across instances sharing a defaults suite")
    func persistsBaseURL() {
        let name = "nesteferge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!

        let first = AppSettings(defaults: defaults)
        first.baseURLString = "https://ferry.example.com"

        let second = AppSettings(defaults: defaults)
        #expect(second.baseURLString == "https://ferry.example.com")
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

    @Test("A one-sided selection still describes itself sensibly")
    func legDescriptionWithoutDestination() {
        let selection = FerrySelection(routeID: 1, routeName: "R", origin: "Festøya", destination: nil)
        #expect(selection.legDescription == "Festøya")
    }
}
