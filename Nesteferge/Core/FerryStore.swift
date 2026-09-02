import Foundation
import Observation

/// Single source of truth for the phone UI and the CarPlay scene.
///
/// Owns the guess/selection/departure lifecycle plus the 1 Hz countdown and the
/// 60 s schedule refresh (which is what keeps the list correct across midnight).
@Observable
@MainActor
final class FerryStore {
    static let shared = FerryStore()

    enum Phase: Equatable {
        case idle
        case locating
        case loaded
        case failed(String)
    }

    // MARK: - Observable state

    private(set) var phase: Phase = .idle
    private(set) var candidates: [GuessCandidate] = []
    /// True when the current candidate list came from `/api/guess` with a heading,
    /// which is what makes the "off course" figures meaningful.
    private(set) var hasHeading = false
    /// True when the list came from search rather than a location guess, in which
    /// case there is no "best guess" to badge.
    private(set) var candidatesAreFromSearch = false

    private(set) var selection: FerrySelection?
    private(set) var departures: [UpcomingDeparture] = []
    private(set) var isLoadingDepartures = false
    private(set) var departuresError: String?
    /// Seconds to the next departure; nil when nothing is scheduled.
    private(set) var secondsUntilNextDeparture: Int?

    private(set) var searchResults: [RouteSearchResult] = []
    private(set) var isSearching = false
    private(set) var searchError: String?

    // MARK: - Dependencies

    private let api: APIClient
    private let settings: AppSettings
    private let location: LocationService

    private var guessTask: Task<Void, Never>?
    private var departuresTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        api: APIClient = .shared,
        settings: AppSettings = .shared,
        // Resolved in the body rather than as a default argument: default arguments
        // are evaluated in a nonisolated context, and `LocationService.shared` is
        // main-actor isolated.
        location: LocationService? = nil
    ) {
        self.api = api
        self.settings = settings
        self.location = location ?? .shared
        self.selection = settings.loadSelection()
    }

    var nextDeparture: UpcomingDeparture? { departures.first }
    var followingDepartures: [UpcomingDeparture] { Array(departures.dropFirst()) }

    var isLocationDenied: Bool { location.isDenied }

    /// The best-guess candidate, if the list came from a location guess.
    var bestGuess: GuessCandidate? {
        candidatesAreFromSearch ? nil : candidates.first
    }

    func isSelected(_ candidate: GuessCandidate) -> Bool {
        guard let selection else { return false }
        return selection.routeID == candidate.routeID && selection.origin == candidate.origin
    }

    // MARK: - Lifecycle

    /// Called when a UI appears. Restores the previous selection's countdown
    /// immediately, then scans for nearby ferries.
    func start() {
        if selection != nil, departures.isEmpty, !isLoadingDepartures {
            loadDepartures()
        }
        if candidates.isEmpty, phase != .locating {
            locateAndGuess()
        }
    }

    /// Stop background work while nothing is on screen.
    func suspendTimers() {
        tickerTask?.cancel(); tickerTask = nil
        refreshTask?.cancel(); refreshTask = nil
    }

    func resumeTimers() {
        guard selection != nil else { return }
        startTicker()
        startRefreshLoop()
        // Coming back from background, the cached schedule may be stale.
        loadDepartures()
    }

    // MARK: - Guess

    func locateAndGuess() {
        guessTask?.cancel()
        phase = .locating
        searchError = nil

        guessTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fix = try await self.location.requestFix()
                try Task.checkCancellation()
                let response = try await self.api.guess(
                    baseURL: self.settings.baseURL,
                    lat: fix.latitude,
                    lng: fix.longitude,
                    heading: fix.heading
                )
                try Task.checkCancellation()
                self.applyGuess(response, hadHeading: fix.heading != nil)
            } catch is CancellationError {
                return
            } catch {
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func applyGuess(_ response: GuessResponse, hadHeading: Bool) {
        candidates = response.candidates
        hasHeading = hadHeading
        candidatesAreFromSearch = false

        guard !candidates.isEmpty else {
            // The API already searches a 600 km radius, so an empty result almost
            // always means the device isn't in Norway at all — not that the user is
            // slightly too far from a quay. (In the Simulator this usually means the
            // location is still at its Cupertino default.)
            phase = .failed(String(
                localized: "guess.none",
                defaultValue: "No Norwegian ferry quays within 600 km of you. Search for a route instead, or rescan when you're closer."
            ))
            return
        }

        phase = .loaded

        // Keep the user's pick if it survived the rescan, otherwise take the best guess.
        var preserved: GuessCandidate?
        if let current = selection {
            preserved = candidates.first { candidate in
                candidate.routeID == current.routeID && candidate.origin == current.origin
            }
        }
        select((preserved ?? candidates[0]).selection)
    }

    // MARK: - Selection & departures

    func select(_ candidate: GuessCandidate) {
        select(candidate.selection)
    }

    func select(_ result: RouteSearchResult) {
        // Promote the whole result set to the candidate list so the chosen route
        // is visible in context (and in CarPlay, which has no search UI).
        candidates = searchResults.map { hit in
            GuessCandidate(
                routeID: hit.routeID,
                routeName: hit.routeName,
                county: hit.county,
                origin: hit.origin,
                destination: hit.destination,
                originLat: 0,
                originLng: 0,
                distanceKm: .nan,
                bearingToOrigin: nil,
                headingOffsetDeg: nil,
                score: 0
            )
        }
        candidatesAreFromSearch = true
        hasHeading = false
        phase = .loaded
        select(result.selection)
    }

    func select(_ newSelection: FerrySelection) {
        selection = newSelection
        settings.saveSelection(newSelection)
        departures = []
        secondsUntilNextDeparture = nil
        departuresError = nil
        loadDepartures()
        startTicker()
        startRefreshLoop()
    }

    private func loadDepartures() {
        guard let selection else { return }
        departuresTask?.cancel()
        isLoadingDepartures = true

        departuresTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingDepartures = false }
            do {
                let response = try await self.api.nextDepartures(
                    baseURL: self.settings.baseURL,
                    routeID: selection.routeID,
                    origin: selection.origin
                )
                try Task.checkCancellation()
                // A late response for a superseded selection must not overwrite state.
                guard self.selection == selection else { return }
                self.departures = response.departures.sorted { $0.departAt < $1.departAt }
                self.departuresError = nil
                self.pruneAndTick()
            } catch is CancellationError {
                return
            } catch {
                guard self.selection == selection else { return }
                self.departuresError = error.localizedDescription
            }
        }
    }

    /// Manual pull-to-refresh / CarPlay rescan.
    func refreshDepartures() async {
        loadDepartures()
        await departuresTask?.value
    }

    // MARK: - Timers

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.pruneAndTick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.loadDepartures()
            }
        }
    }

    /// Drop departures that have already sailed and recompute the countdown.
    private func pruneAndTick() {
        let now = Date()
        if let index = departures.firstIndex(where: { $0.departAt > now }) {
            if index > 0 { departures.removeFirst(index) }
        } else if !departures.isEmpty {
            departures.removeAll()
        }

        guard let next = departures.first else {
            secondsUntilNextDeparture = nil
            return
        }
        secondsUntilNextDeparture = max(0, Int(next.departAt.timeIntervalSince(now).rounded()))
    }

    // MARK: - Search

    func search(_ rawQuery: String) {
        searchTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            searchError = query.isEmpty
                ? nil
                : String(localized: "search.keepTyping", defaultValue: "Type at least 2 characters to search.")
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            guard let self else { return }
            // Debounce: a fast typist cancels this before any request goes out.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let response = try await self.api.searchRoutes(baseURL: self.settings.baseURL, query: query)
                try Task.checkCancellation()
                self.searchResults = response.results
                self.searchError = response.results.isEmpty
                    ? String(
                        format: String(localized: "search.noResults", defaultValue: "No matches for \"%@\"."),
                        query
                    )
                    : nil
                self.isSearching = false
            } catch is CancellationError {
                return
            } catch {
                self.searchResults = []
                self.searchError = error.localizedDescription
                self.isSearching = false
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = []
        searchError = nil
        isSearching = false
    }
}
