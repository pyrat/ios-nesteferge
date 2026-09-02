import SwiftUI

/// One row in the nearby-ferries list.
struct CandidateRow: View {
    let candidate: GuessCandidate
    let isBestGuess: Bool
    let showsHeadingOffset: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(legText)
                    .font(.body)
                Text(candidate.routeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isBestGuess {
                    Text("candidate.bestGuess", comment: "Badge on the top-ranked nearby ferry")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.tint)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                if let distance = distanceText {
                    Text(distance)
                }
                if showsHeadingOffset, let offset = candidate.headingOffsetDeg {
                    Text(DepartureFormatter.headingOffset(degrees: offset))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel(Text("candidate.selected", comment: "Accessibility label for the chosen ferry"))
            }
        }
        .contentShape(.rect)
    }

    private var legText: String {
        guard let destination = candidate.destination, !destination.isEmpty else {
            return candidate.origin
        }
        return "\(candidate.origin) → \(destination)"
    }

    /// Search-sourced candidates carry no distance (NaN), so fall back to county.
    private var distanceText: String? {
        if candidate.distanceKm.isFinite {
            return DepartureFormatter.distance(km: candidate.distanceKm)
        }
        return candidate.county
    }
}
