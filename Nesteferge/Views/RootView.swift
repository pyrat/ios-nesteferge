import SwiftUI

enum FerryTheme {
    static let background = Color(red: 11 / 255, green: 31 / 255, blue: 51 / 255)
    static let backgroundHighlight = Color(red: 14 / 255, green: 42 / 255, blue: 69 / 255)
    static let card = Color(red: 18 / 255, green: 50 / 255, blue: 79 / 255)
    static let cardHighlight = Color(red: 23 / 255, green: 67 / 255, blue: 107 / 255)
    static let accent = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)
    static let accentSecondary = Color(red: 34 / 255, green: 211 / 255, blue: 238 / 255)
    static let text = Color(red: 234 / 255, green: 242 / 255, blue: 251 / 255)
    static let muted = Color(red: 143 / 255, green: 176 / 255, blue: 204 / 255)
}

@MainActor
struct RootView: View {
    @Environment(FerryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var searchText = ""
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [FerryTheme.backgroundHighlight, FerryTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
        }
        .tint(FerryTheme.accent)
        .preferredColorScheme(.dark)
        .task { store.start() }
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? store.resumeTimers() : store.suspendTimers()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            searchList
        } else {
            switch store.phase {
            case .idle, .locating:
                locatingView
            case let .failed(message):
                failureView(message)
            case .loaded:
                mainList
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("app.title", comment: "App name shown at the top of the screen")
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundStyle(FerryTheme.accent)

            Spacer()

            Button { isShowingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(Text("action.settings", comment: "Opens the app's settings sheet"))

            Button { store.locateAndGuess() } label: {
                Image(systemName: "location.fill")
            }
            .accessibilityLabel(Text("action.rescan", comment: "Search again for nearby ferries"))
            .disabled(store.phase == .locating)
        }
        .font(.body.weight(.medium))
        .foregroundStyle(FerryTheme.muted)
    }

    private var locatingView: some View {
        VStack(spacing: 24) {
            header

            Spacer()

            ZStack {
                Circle()
                    .fill(FerryTheme.accent.opacity(0.14))
                    .frame(width: 132, height: 132)
                Circle()
                    .fill(FerryTheme.accent)
                    .frame(width: 84, height: 84)
                Image(systemName: "ferry.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(FerryTheme.background)
            }

            VStack(spacing: 10) {
                Text("locating.status", comment: "Shown while acquiring GPS and querying nearby ferries")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FerryTheme.text)
                ProgressView()
                    .tint(FerryTheme.accent)
            }

            Text("locating.hint", comment: "Explains how the app finds a ferry")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(FerryTheme.muted)

            routeSearchField
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 24) {
            header
            Spacer()
            Image(systemName: "ferry.fill")
                .font(.system(size: 46))
                .foregroundStyle(FerryTheme.accent)
            Text("guess.emptyTitle", comment: "Title when no ferry could be determined")
                .font(.title2.weight(.bold))
                .foregroundStyle(FerryTheme.text)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(FerryTheme.muted)

            if store.isLocationDenied {
                Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
                    Text("action.openSettings", comment: "Opens the system Settings app")
                }
                .buttonStyle(FerryPrimaryButtonStyle())
            } else {
                Button { store.locateAndGuess() } label: {
                    Text("action.rescan", comment: "Search again for nearby ferries")
                }
                .buttonStyle(FerryPrimaryButtonStyle())
            }

            routeSearchField
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var mainList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                CountdownView(store: store)

                Divider().overlay(FerryTheme.muted.opacity(0.2))

                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("section.nearby")
                    ForEach(store.candidates, id: \.self) { candidate in
                        Button { store.select(candidate) } label: {
                            CandidateRow(
                                candidate: candidate,
                                isBestGuess: candidate == store.bestGuess,
                                showsHeadingOffset: store.hasHeading,
                                isSelected: store.isSelected(candidate)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Text(listHint)
                        .font(.footnote)
                        .foregroundStyle(FerryTheme.muted)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .refreshable { await store.refreshDepartures() }
    }

    private var searchList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                routeSearchField
                sectionLabel("search.prompt")

                if store.isSearching {
                    ProgressView().tint(FerryTheme.accent)
                } else if let error = store.searchError {
                    Text(error).foregroundStyle(FerryTheme.muted)
                } else {
                    ForEach(store.searchResults, id: \.self) { result in
                        Button {
                            store.select(result)
                            searchText = ""
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private var routeSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FerryTheme.muted)
            TextField("search.prompt", text: $searchText, prompt: Text("search.prompt", comment: "Route search field placeholder"))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(FerryTheme.text)
                .onChange(of: searchText) { _, newValue in
                    if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                        store.clearSearch()
                    } else {
                        store.search(newValue)
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FerryTheme.card.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14)) }
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption.weight(.medium))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(FerryTheme.muted)
    }

    private var listHint: LocalizedStringKey {
        store.candidatesAreFromSearch ? "hint.search" : (store.hasHeading ? "hint.heading" : "hint.noHeading")
    }
}

private struct SearchResultRow: View {
    let result: RouteSearchResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(result.origin) → \(result.destination)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FerryTheme.text)
                Text(result.county.map { "\(result.routeName) · \($0)" } ?? result.routeName)
                    .font(.footnote)
                    .foregroundStyle(FerryTheme.muted)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .foregroundStyle(FerryTheme.accent)
        }
        .padding(14)
        .background(FerryTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FerryPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.bold)
            .foregroundStyle(FerryTheme.background)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [FerryTheme.accent, FerryTheme.accentSecondary], startPoint: .leading, endPoint: .trailing), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
