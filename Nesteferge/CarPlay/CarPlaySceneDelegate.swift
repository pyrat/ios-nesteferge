import CarPlay
import Foundation
import Observation

/// CarPlay entry point.
///
/// Deliberately reduced compared to the phone: a list of nearby ferries and a
/// countdown detail screen. No text search — that's not something to be doing
/// while driving, and CarPlay's list limits make it a poor fit anyway.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    /// Computed rather than stored: `FerryStore.shared` is main-actor isolated and
    /// this delegate is not.
    @MainActor
    private var store: FerryStore { FerryStore.shared }

    private var listTemplate: CPListTemplate?
    private var informationTemplate: CPInformationTemplate?

    /// Minimum permitted refresh cadence for a CarPlay driving task app.
    ///
    /// The CarPlay Developer Guide: "Do not periodically refresh data items in the
    /// CarPlay UI more than once every 10 seconds." Do not lower this — the phone
    /// UI is where the 1 Hz `mm:ss` countdown lives.
    private static let countdownRefreshInterval = 10

    /// Drives the periodic refresh of the detail screen.
    private var countdownTask: Task<Void, Never>?
    /// Rebuilds templates whenever the shared store changes.
    private var observationTask: Task<Void, Never>?

    // MARK: - Scene lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let list = makeListTemplate()
        listTemplate = list
        interfaceController.setRootTemplate(list, animated: false, completion: nil)

        Task { @MainActor in
            self.startObserving()
            self.store.start()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        countdownTask?.cancel(); countdownTask = nil
        observationTask?.cancel(); observationTask = nil
        self.interfaceController = nil
        listTemplate = nil
        informationTemplate = nil
    }

    // MARK: - Observation

    /// `@Observable` has no Combine publisher, so poll the tracked properties via
    /// `withObservationTracking` and rebuild whatever is on screen when they change.
    ///
    /// Renders first and registers afterwards, so a store that already holds
    /// candidates (e.g. the phone scanned before CarPlay connected) shows up
    /// immediately instead of waiting for the next change.
    @MainActor
    private func startObserving() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshList()
                self.refreshInformation()

                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.store.candidates
                        _ = self.store.phase
                        _ = self.store.selection
                        _ = self.store.departures
                    } onChange: {
                        continuation.resume()
                    }
                }
            }
        }
    }

    // MARK: - Root list

    private func makeListTemplate() -> CPListTemplate {
        let template = CPListTemplate(
            title: String(localized: "carplay.nearbyTitle", defaultValue: "Nearby ferries"),
            sections: []
        )
        template.trailingNavigationBarButtons = [
            CPBarButton(title: String(localized: "action.rescan", defaultValue: "Rescan")) { [weak self] _ in
                Task { @MainActor in self?.store.locateAndGuess() }
            }
        ]
        template.emptyViewTitleVariants = [
            String(localized: "carplay.emptyTitle", defaultValue: "No ferries nearby")
        ]
        template.emptyViewSubtitleVariants = [
            String(localized: "carplay.emptySubtitle", defaultValue: "Drive closer to a quay, then tap Rescan.")
        ]
        return template
    }

    @MainActor
    private func refreshList() {
        guard let listTemplate else { return }

        switch store.phase {
        case .idle, .locating:
            listTemplate.emptyViewTitleVariants = [
                String(localized: "carplay.locatingTitle", defaultValue: "Looking for ferries…")
            ]
            listTemplate.emptyViewSubtitleVariants = [""]
        case let .failed(message):
            listTemplate.emptyViewTitleVariants = [
                String(localized: "carplay.emptyTitle", defaultValue: "No ferries nearby")
            ]
            listTemplate.emptyViewSubtitleVariants = [message]
        case .loaded:
            break
        }

        // CarPlay caps how many rows a connected head unit will render.
        let limit = CPListTemplate.maximumItemCount
        let items: [CPListItem] = store.candidates.prefix(limit).map { candidate in
            let item = CPListItem(text: legText(for: candidate), detailText: detailText(for: candidate))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.store.select(candidate)
                    self?.presentInformation()
                    completion()
                }
            }
            return item
        }

        listTemplate.updateSections([CPListSection(items: items)])
    }

    private func legText(for candidate: GuessCandidate) -> String {
        guard let destination = candidate.destination, !destination.isEmpty else {
            return candidate.origin
        }
        return "\(candidate.origin) → \(destination)"
    }

    private func detailText(for candidate: GuessCandidate) -> String {
        var parts: [String] = []
        if candidate.distanceKm.isFinite {
            parts.append(DepartureFormatter.distance(km: candidate.distanceKm))
        }
        parts.append(candidate.routeName)
        return parts.joined(separator: " · ")
    }

    // MARK: - Countdown detail

    @MainActor
    private func presentInformation() {
        let template = CPInformationTemplate(
            title: store.selection?.legDescription ?? String(localized: "app.title", defaultValue: "Nesteferge"),
            layout: .leading,
            items: informationItems(),
            actions: [
                CPTextButton(
                    title: String(localized: "action.rescan", defaultValue: "Rescan"),
                    textStyle: .normal
                ) { [weak self] _ in
                    Task { @MainActor in self?.store.locateAndGuess() }
                }
            ]
        )
        informationTemplate = template
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
        startCountdownRefresh()
    }

    /// Mutating `items` in place keeps the template stable; pushing a new one every
    /// second would flicker and blow through CarPlay's template depth limit.
    @MainActor
    private func refreshInformation() {
        guard let informationTemplate else { return }
        informationTemplate.items = informationItems()
    }

    @MainActor
    private func informationItems() -> [CPInformationItem] {
        var items: [CPInformationItem] = []

        let countdown: String
        if let seconds = store.secondsUntilNextDeparture {
            countdown = DepartureFormatter.coarseCountdown(seconds: seconds)
        } else {
            countdown = store.isLoadingDepartures ? "…" : "—"
        }
        items.append(CPInformationItem(
            title: String(localized: "carplay.departsIn", defaultValue: "Departs in"),
            detail: countdown
        ))

        if let next = store.nextDeparture {
            items.append(CPInformationItem(
                title: DepartureFormatter.dayLabel(next.departAt),
                detail: DepartureFormatter.clock(next.departAt)
            ))
        } else if let error = store.departuresError {
            items.append(CPInformationItem(
                title: String(localized: "carplay.status", defaultValue: "Status"),
                detail: error
            ))
        } else if !store.isLoadingDepartures {
            items.append(CPInformationItem(
                title: String(localized: "carplay.status", defaultValue: "Status"),
                detail: String(localized: "departures.noneToday", defaultValue: "No more sailings today.")
            ))
        }

        for departure in store.followingDepartures.prefix(2) {
            items.append(CPInformationItem(
                title: String(
                    format: String(localized: "carplay.then", defaultValue: "Then · %@"),
                    DepartureFormatter.dayLabel(departure.departAt)
                ),
                detail: DepartureFormatter.clock(departure.departAt)
            ))
        }

        if let selection = store.selection {
            items.append(CPInformationItem(
                title: String(localized: "carplay.route", defaultValue: "Route"),
                detail: selection.routeName
            ))
        }

        return items
    }

    @MainActor
    private func startCountdownRefresh() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.countdownRefreshInterval))
                guard !Task.isCancelled else { return }
                // Task inherits main-actor isolation from this method.
                self?.refreshInformation()
            }
        }
    }
}
