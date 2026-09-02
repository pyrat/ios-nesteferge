import SwiftUI

/// Minimal settings: which API to talk to, plus a connection check.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared
    @State private var draftURL = AppSettings.shared.baseURLString
    @State private var healthResult: String?
    @State private var isCheckingHealth = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "settings.apiURL", defaultValue: "API base URL"),
                        text: $draftURL
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit(save)

                    Button {
                        draftURL = AppSettings.defaultBaseURLString
                        save()
                    } label: {
                        Text("settings.reset", comment: "Restores the built-in default API address")
                    }
                } header: {
                    Text("settings.serverSection", comment: "Settings section header for server configuration")
                } footer: {
                    if AppSettings.normalizedURL(from: draftURL) == nil {
                        Text("settings.invalidURL", comment: "Shown when the typed API address cannot be used")
                            .foregroundStyle(.red)
                    } else {
                        Text("settings.urlFooter", comment: "Explains what the API base URL is for")
                    }
                }

                Section {
                    Button {
                        checkHealth()
                    } label: {
                        HStack {
                            Text("settings.testConnection", comment: "Button that pings /api/health")
                            if isCheckingHealth {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isCheckingHealth || AppSettings.normalizedURL(from: draftURL) == nil)

                    if let healthResult {
                        Text(healthResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent(
                        String(localized: "settings.version", defaultValue: "Version"),
                        value: Self.versionString
                    )
                }
            }
            .navigationTitle(Text("action.settings", comment: "Opens the app's settings sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("action.done", comment: "Dismisses the settings sheet")
                    }
                }
            }
        }
    }

    private func save() {
        guard AppSettings.normalizedURL(from: draftURL) != nil else { return }
        settings.baseURLString = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func checkHealth() {
        save()
        guard let url = AppSettings.normalizedURL(from: draftURL) else { return }
        isCheckingHealth = true
        healthResult = nil
        Task {
            defer { isCheckingHealth = false }
            do {
                let health = try await APIClient.shared.health(baseURL: url)
                healthResult = String(
                    format: String(
                        localized: "settings.healthOK",
                        defaultValue: "%@ · %d terminals · %d routes"
                    ),
                    health.status,
                    health.terminals,
                    health.routes
                )
            } catch {
                healthResult = error.localizedDescription
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
