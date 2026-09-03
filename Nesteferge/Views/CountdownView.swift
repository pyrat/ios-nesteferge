import SwiftUI

@MainActor
struct CountdownView: View {
    let store: FerryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selection = store.selection {
                Text(selection.routeName)
                    .font(.caption.weight(.medium))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(FerryTheme.muted)
                Text(selection.legDescription)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(FerryTheme.text)
            }

            VStack(spacing: 8) {
                Text(clockText)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())
                    .foregroundStyle(urgencyColor)
                    .accessibilityLabel(accessibilityCountdown)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FerryTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            if !store.followingDepartures.isEmpty {
                VStack(spacing: 0) {
                    ForEach(store.followingDepartures) { departure in
                        HStack {
                            Text(DepartureFormatter.dayLabel(departure.departAt))
                            Spacer()
                            Text(DepartureFormatter.clock(departure.departAt)).monospacedDigit().foregroundStyle(FerryTheme.text)
                        }
                        .font(.subheadline)
                        .foregroundStyle(FerryTheme.muted)
                        .padding(.vertical, 11)
                        Divider().overlay(FerryTheme.muted.opacity(0.15))
                    }
                }
            }
        }
        .padding(20)
        .background(FerryTheme.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)) }
    }

    private var clockText: String { store.secondsUntilNextDeparture.map(DepartureFormatter.countdown) ?? (store.isLoadingDepartures ? "…" : "—") }

    private var subtitle: String {
        if let error = store.departuresError { return error }
        if store.isLoadingDepartures && store.departures.isEmpty { return String(localized: "departures.loading", defaultValue: "Loading departures…") }
        guard let next = store.nextDeparture else { return String(localized: "departures.noneToday", defaultValue: "No more sailings today.") }
        return String(format: String(localized: "departures.departsAt", defaultValue: "Departs %@ · %@"), DepartureFormatter.clock(next.departAt), DepartureFormatter.dayLabel(next.departAt))
    }

    private var urgencyColor: Color {
        guard let seconds = store.secondsUntilNextDeparture else { return FerryTheme.accent }
        if seconds <= 120 { return .orange }
        if seconds <= 600 { return .green }
        return FerryTheme.accent
    }

    private var accessibilityCountdown: String {
        guard let seconds = store.secondsUntilNextDeparture else { return clockText }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
