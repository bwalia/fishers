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

    /// The local ones come from the build rather than the source: a hard-coded
    /// `192.168.1.177:7312` was one house move and one `API_PORT=` away from
    /// being a preset that cannot work, offered as if it could.
    ///
    /// Either may be absent — a Release build has no LAN address, and a
    /// project generated without `scripts/start.sh` has no usable one — and an
    /// absent preset is left out rather than shown broken.
    private var visiblePresets: [(String, String)] {
        var items: [(String, String)] = []
        if let lan = AppConfig.lanAPIBase {
            items.append(("This Mac (Wi‑Fi)", lan.absoluteString))
        }
        #if targetEnvironment(simulator)
        if let build = AppConfig.buildAPIBase, build.host == "127.0.0.1" {
            items.append(("Simulator loopback", build.absoluteString))
        }
        #endif
        // This brand's rings, not Fishers'. A preset naming another brand's
        // server is one tap from signing into the wrong database.
        for host in ["int.\(Brand.domain)", Brand.apiHost] {
            items.append((host, "https://\(host)"))
        }
        return items
    }

    var body: some View {
        Form {
            if AppConfig.environmentPinsAPI {
                Section {
                    Text(t("rest.launch_pinned_by_env"))
                        .font(.footnote)
                        .foregroundStyle(FishersTheme.maybe)
                }
            }

            Section {
                TextField(t("rest.url_placeholder"), text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
            } header: {
                Text(t("rest.api_base_url"))
            } footer: {
                Text("In use now: \(resolved). Open live screens again after changing — an open score stream keeps its old host until you leave it.")
            }

            Section(tr("Quick picks")) {
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
                Button(t("lc.save")) { save() }
                    .fontWeight(.semibold)
                Button(t("rest.reset_to_default")) { reset() }
                if AppConfig.storedAPIOverride != nil {
                    LabeledContent("Saved override", value: AppConfig.storedAPIOverride ?? "")
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(t("rest.api_server"))
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
