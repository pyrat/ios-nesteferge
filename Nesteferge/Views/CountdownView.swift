import SwiftUI

/// Big countdown block: time to the next departure, the leg it belongs to, and
/// the couple of sailings after it.
struct CountdownView: View {
    let store: FerryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let selection = store.selection {
                Text(selection.legDescription)
                    .font(.headline)
                Text(selection.routeName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(clockText)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(urgencyColor)
                .accessibilityLabel(accessibilityCountdown)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !store.followingDepartures.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(store.followingDepartures) { departure in
                    HStack {
                        Text(DepartureFormatter.dayLabel(departure.departAt))
                        Spacer()
                        Text(DepartureFormatter.clock(departure.departAt))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var clockText: String {
        if let seconds = store.secondsUntilNextDeparture {
            return DepartureFormatter.countdown(seconds: seconds)
        }
        return store.isLoadingDepartures ? "…" : "—"
    }

    private var subtitle: String {
        if let error = store.departuresError { return error }
        if store.isLoadingDepartures && store.departures.isEmpty {
            return String(localized: "departures.loading", defaultValue: "Loading departures…")
        }
        guard let next = store.nextDeparture else {
            return String(localized: "departures.noneToday", defaultValue: "No more sailings today.")
        }
        return String(
            format: String(localized: "departures.departsAt", defaultValue: "Departs %@ · %@"),
            DepartureFormatter.clock(next.departAt),
            DepartureFormatter.dayLabel(next.departAt)
        )
    }

    /// Amber under 10 minutes, red under 2 — the only colour in the app.
    private var urgencyColor: Color {
        guard let seconds = store.secondsUntilNextDeparture else { return .primary }
        if seconds <= 120 { return .red }
        if seconds <= 600 { return .orange }
        return .primary
    }

    private var accessibilityCountdown: String {
        guard let seconds = store.secondsUntilNextDeparture else { return clockText }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
