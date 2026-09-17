import SwiftUI

/// Change which API server this install talks to — LAN Mac, int, or prod —
/// without rebuilding. Stored in UserDefaults (`FishersAPIBaseURL`); the next
/// request picks it up. An Xcode / `start.sh` `FISHERS_API_URL` env var still
/// wins for that process.
struct APIServerSettingsView: View {
    @State private var draft: String = AppConfig.storedAPIOverride ?? AppConfig.apiBaseURL.absoluteString
    @State private var note: String?
    @State private var errorMessage: String?
    @State private var resolved: String = AppConfig.apiBaseURL.absoluteString

    private let presets: [(String, String)] = [
        ("This Mac (Wi‑Fi)", "http://192.168.1.177:7312"),
        ("Simulator loopback", "http://127.0.0.1:7312"),
        ("int.fishers.cloud", "https://int.fishers.cloud"),
        ("www.fishers.cloud", "https://www.fishers.cloud"),
    ]

    private var visiblePresets: [(String, String)] {
        #if targetEnvironment(simulator)
        presets
        #else
        presets.filter { !$0.1.contains("127.0.0.1") }
        #endif
    }

    var body: some View {
        Form {
            if AppConfig.environmentPinsAPI {
                Section {
                    Text("This launch is pinned by FISHERS_API_URL in the environment. Saving below stores a preference, but it will not apply until that env var is cleared.")
                        .font(.footnote)
                        .foregroundStyle(FishersTheme.maybe)
                }
            }

            Section {
                TextField("https://… or http://192.168.…", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
            } header: {
                Text("API base URL")
            } footer: {
                Text("In use now: \(resolved). Open live screens again after changing — an open score stream keeps its old host until you leave it.")
            }

            Section("Quick picks") {
                ForEach(visiblePresets, id: \.1) { label, url in
                    presetButton(label, url)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(FishersTheme.unavailable)
                }
            } else if let note {
                Section {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                Button("Reset to default") { reset() }
                if AppConfig.storedAPIOverride != nil {
                    LabeledContent("Saved override", value: AppConfig.storedAPIOverride ?? "")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("API server")
        .navigationBarTitleDisplayMode(.inline)
        .tint(FishersTheme.accent)
        .onAppear { refreshResolved() }
    }

    private func presetButton(_ label: String, _ url: String) -> some View {
        Button {
            draft = url
            save()
        } label: {
            HStack {
                Text(label)
                Spacer()
                Text(url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
    }

    private func save() {
        errorMessage = nil
        note = nil
        do {
            let url = try AppConfig.setAPIBaseURLOverride(draft)
            draft = url.absoluteString
            refreshResolved()
            note = AppConfig.environmentPinsAPI
                ? "Saved, but FISHERS_API_URL still wins for this launch."
                : "Saved. New requests use \(url.absoluteString)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reset() {
        errorMessage = nil
        AppConfig.clearAPIBaseURLOverride()
        draft = AppConfig.defaultAPIBaseURL.absoluteString
        refreshResolved()
        note = "Cleared. Using \(resolved)."
    }

    private func refreshResolved() {
        resolved = AppConfig.apiBaseURL.absoluteString
    }
}
