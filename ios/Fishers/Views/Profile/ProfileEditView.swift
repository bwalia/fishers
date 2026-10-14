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
                            .navigationTitle(t(tr("rest.about_you")))
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent(tr("About you"), value: form.name)
                    }
                    NavigationLink {
                        SportsPicker(form: form)
                            .navigationTitle(t("rest.sports"))
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent(tr("Sports"), value: form.selectedSports.map(\.label).joined(separator: ", "))
                    }
                }

                Section(tr("Level, league & stats")) {
                    ForEach(form.selectedSports) { sport in
                        NavigationLink {
                            SportDetailForm(sport: sport, form: form)
                                .navigationTitle(sport.label)
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label {
                                LabeledContent(sport.label, value: form.detail(for: sport).tier?.label ?? tr("Not set"))
                            } icon: {
                                Image(systemName: sport.systemImage)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        LogisticsForm(form: form)
                            .navigationTitle(t(tr("rest.travel_and_logistics")))
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent(tr("Travel & logistics"), value: form.area.nonEmpty ?? tr("Not set"))
                    }
                }

                Section {
                    NavigationLink {
                        APIServerSettingsView()
                    } label: {
                        LabeledContent(tr("API server"), value: AppConfig.displayHost)
                    }
                } footer: {
                    Text(t(tr("rest.reliability_is_server_worked")))
                }
            }
            .navigationTitle(t(tr("cl.edit_profile")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("sc.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        // Whatever is filled in saves — a profile is finished
                        // a bit at a time, not all at once.
                        Button(t("lc.save")) { save() }
                            .disabled(!form.isNameValid)
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

