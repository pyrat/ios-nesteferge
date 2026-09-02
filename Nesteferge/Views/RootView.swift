import SwiftUI

/// The whole phone UI: countdown on top, nearby ferries below, search in the
/// navigation bar. Plain `List` + system controls throughout.
struct RootView: View {
    @Environment(FerryStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var searchText = ""
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("app.title", comment: "App name shown in the navigation bar"))
                .toolbar { toolbarItems }
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("search.prompt", comment: "Route search field placeholder")
                )
                .onChange(of: searchText) { _, newValue in
                    if newValue.trimmingCharacters(in: .whitespaces).isEmpty {
                        store.clearSearch()
                    } else {
                        store.search(newValue)
                    }
                }
                .refreshable { await store.refreshDepartures() }
                .sheet(isPresented: $isShowingSettings) { SettingsView() }
        }
        .task { store.start() }
        .onChange(of: scenePhase) { _, phase in
            // Countdown timers are pointless off-screen and cost battery.
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

    // MARK: - States

    private var locatingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("locating.status", comment: "Shown while acquiring GPS and querying nearby ferries")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        ContentUnavailableView {
            Label {
                Text("guess.emptyTitle", comment: "Title when no ferry could be determined")
            } icon: {
                Image(systemName: "ferry")
            }
        } description: {
            Text(message)
        } actions: {
            if store.isLocationDenied {
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Text("action.openSettings", comment: "Opens the system Settings app")
                }
            } else {
                Button {
                    store.locateAndGuess()
                } label: {
                    Text("action.rescan", comment: "Search again for nearby ferries")
                }
            }
        }
    }

    private var mainList: some View {
        List {
            Section {
                CountdownView(store: store)
            }

            Section {
                ForEach(store.candidates, id: \.self) { candidate in
                    Button {
                        store.select(candidate)
                    } label: {
                        CandidateRow(
                            candidate: candidate,
                            isBestGuess: candidate == store.bestGuess,
                            showsHeadingOffset: store.hasHeading,
                            isSelected: store.isSelected(candidate)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("section.nearby", comment: "Header above the list of nearby ferries")
            } footer: {
                Text(listHint)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var searchList: some View {
        List {
            if store.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("search.searching", comment: "Shown while a route search is in flight")
                        .foregroundStyle(.secondary)
                }
            }
            if let error = store.searchError {
                Text(error).foregroundStyle(.secondary)
            }
            ForEach(store.searchResults, id: \.self) { result in
                Button {
                    store.select(result)
                    searchText = ""
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(result.origin) → \(result.destination)")
                        Text(result.county.map { "\(result.routeName) · \($0)" } ?? result.routeName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var listHint: LocalizedStringKey {
        if store.candidatesAreFromSearch {
            return "hint.search"
        }
        return store.hasHeading ? "hint.heading" : "hint.noHeading"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingSettings = true
            } label: {
                Label {
                    Text("action.settings", comment: "Opens the app's settings sheet")
                } icon: {
                    Image(systemName: "gearshape")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                store.locateAndGuess()
            } label: {
                Label {
                    Text("action.rescan", comment: "Search again for nearby ferries")
                } icon: {
                    Image(systemName: "location")
                }
            }
            .disabled(store.phase == .locating)
        }
    }
}
