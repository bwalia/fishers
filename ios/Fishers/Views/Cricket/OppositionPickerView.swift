import SwiftUI

/// Who you are playing. Scan their code at the ground, search for them, or —
/// for a scratch side that has never heard of Fishers — just type a name.
struct OppositionPickerView: View {
    var onPick: (String, ClubIdentity?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = false
    @State private var query = ""
    @State private var results: [ClubIdentity] = []
    @State private var typedName = ""
    @State private var message: String?
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isScanning = true
                    } label: {
                        Label(t("sc.scan_their_qr_code"), systemImage: "qrcode.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(FishersTheme.accent)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    Text(t("sc.qr_under_clubs"))
                }

                Section(tr("Search by name")) {
                    HStack {
                        TextField(t("rest.club_or_team"), text: $query)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await search() } }
                        if isSearching { ProgressView() }
                    }
                    ForEach(results) { identity in
                        Button {
                            onPick(identity.displayName, identity)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(identity.displayName)
                                    if identity.isTeam, let sport = identity.sport {
                                        Text(sport.capitalized)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if !query.isEmpty && results.isEmpty && !isSearching {
                        Text(t("sc.nothing_found_type_name"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        TextField(t("sc.opposition_name"), text: $typedName)
                            .textInputAutocapitalization(.words)
                        Button(t("sc.use")) {
                            let name = typedName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            onPick(name, nil)
                            dismiss()
                        }
                        .disabled(typedName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text(t("sc.or_just_type_it"))
                } footer: {
                    Text("A scratch side that isn't on \(Brand.name) is only a name — that is fine.")
                }

                if let message {
                    Section { Text(message).font(.footnote).foregroundStyle(FishersTheme.unavailable) }
                }
            }
            .fishersList()
            .navigationTitle(t("sc.opposition"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
            }
            .onChange(of: query) { _, _ in Task { await search() } }
            .sheet(isPresented: $isScanning) {
                NavigationStack {
                    QRScannerView(
                        onFound: { value in
                            isScanning = false
                            Task { await resolve(value) }
                        },
                        onFailure: { reason in
                            isScanning = false
                            message = reason
                        }
                    )
                    .ignoresSafeArea()
                    .navigationTitle(t("sc.point_at_their_code"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(t("sc.cancel")) { isScanning = false }
                        }
                    }
                }
            }
        }
    }

    /// Debounced so a fast typist does not fire a request per keystroke.
    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(250))
        guard term == query.trimmingCharacters(in: .whitespaces) else { return }
        results = (try? await FishersAPI.searchOpponents(query: term)) ?? []
        isSearching = false
    }

    private func resolve(_ scanned: String) async {
        do {
            let identity = try await FishersAPI.lookupOpponent(token: scanned)
            onPick(identity.displayName, identity)
            dismiss()
        } catch {
            message = "That code isn't one of ours. Try searching by name."
        }
    }
}
