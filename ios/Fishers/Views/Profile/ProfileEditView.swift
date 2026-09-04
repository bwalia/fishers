import SwiftUI

/// Same fields as first-run setup, reachable any time from the Profile tab.
/// Each group is a sub-page so the sheet stays scannable.
struct ProfileEditView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var form: ProfileFormModel
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(user: PublicUser?) {
        _form = State(initialValue: ProfileFormModel(user: user))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        ProfileErrorBanner(message: errorMessage)
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    NavigationLink {
                        AboutForm(form: form)
                            .navigationTitle("About you")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("About you", value: form.name)
                    }
                    NavigationLink {
                        SportsPicker(form: form)
                            .navigationTitle("Sports")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Sports", value: form.selectedSports.map(\.label).joined(separator: ", "))
                    }
                }

                Section("Level, league & stats") {
                    ForEach(form.selectedSports) { sport in
                        NavigationLink {
                            SportDetailForm(sport: sport, form: form)
                                .navigationTitle(sport.label)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label {
                                LabeledContent(sport.label, value: form.detail(for: sport).tier?.label ?? "Not set")
                            } icon: {
                                Image(systemName: sport.systemImage)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        LogisticsForm(form: form)
                            .navigationTitle("Travel & logistics")
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent("Travel & logistics", value: form.area.nonEmpty ?? "Not set")
                    }
                }

                Section {
                    LabeledContent("API base URL", value: AppConfig.apiBaseURL.absoluteString)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Reliability is worked out by the server from your attendance and payments — it can't be edited here.")
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(!form.isComplete)
                    }
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await session.saveProfile(form.update)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

