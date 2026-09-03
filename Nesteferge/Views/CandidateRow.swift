import SwiftUI

struct CandidateRow: View {
    let candidate: GuessCandidate
    let isBestGuess: Bool
    let showsHeadingOffset: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(legText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FerryTheme.text)
                Text(candidate.routeName)
                    .font(.footnote)
                    .foregroundStyle(FerryTheme.muted)
                if isBestGuess {
                    Text("candidate.bestGuess", comment: "Badge on the top-ranked nearby ferry")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(FerryTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FerryTheme.accent.opacity(0.15), in: Capsule())
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                if let distance = distanceText { Text(distance) }
                if showsHeadingOffset, let offset = candidate.headingOffsetDeg {
                    Text(DepartureFormatter.headingOffset(degrees: offset))
                }
            }
            .font(.caption)
            .foregroundStyle(FerryTheme.muted)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FerryTheme.accent)
        }
        .padding(14)
        .background(isSelected ? FerryTheme.cardHighlight : FerryTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(isSelected ? FerryTheme.accent : .clear, lineWidth: 1) }
        .contentShape(.rect)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var legText: String {
        guard let destination = candidate.destination, !destination.isEmpty else { return candidate.origin }
        return "\(candidate.origin) → \(destination)"
    }

    private var distanceText: String? {
        candidate.distanceKm.isFinite ? DepartureFormatter.distance(km: candidate.distanceKm) : candidate.county
    }
}
