import SwiftUI

// The four field groups a profile is made of. First-run setup shows them one
// step at a time; the edit sheet reuses the same forms as sub-pages.

struct AboutForm: View {
    @Bindable var form: ProfileFormModel

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ZStack {
                        Circle().fill(FishersTheme.accent.opacity(0.2))
                        Text(initials)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(FishersTheme.accent)
                    }
                    .frame(width: 84, height: 84)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("You") {
                TextField(t("rest.full_name"), text: $form.name)
                    .textContentType(.name)
                TextField(t("cl.mobile"), text: $form.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }
            Section {
                TextField(t("rest.name_dot_number"), text: $form.emergencyContact)
                    .textContentType(.name)
            } header: {
                Text(t("rest.emergency_contact"))
            } footer: {
                Text(t("rest.only_club_admins_see_this"))
            }
        }
    }

    private var initials: String {
        let parts = form.name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let last = parts.count > 1 ? parts.last?.first.map(String.init) ?? "" : ""
        return first + last
    }
}

struct SportsPicker: View {
    @Bindable var form: ProfileFormModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SportSelectGrid(form: form)

                if form.selectedSports.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("cl.main_sport"))
                            .font(.headline)
                        Text(t("rest.shown_first_on_profile"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("Main sport", selection: $form.primarySport) {
                            ForEach(form.selectedSports) { sport in
                                Text(sport.label).tag(Sport?.some(sport))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .padding()
        }
    }
}

struct SportDetailForm: View {
    let sport: Sport
    @Bindable var form: ProfileFormModel

    var body: some View {
        Form {
            Section {
                TierSelector(tier: form.tierBinding(sport))
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } header: {
                Text(t("rest.your_standard"))
            } footer: {
                if let tier = form.detail(for: sport).tier, let next = tier.next {
                    Text("Next rung up: \(next.label). Log games and stats to make the case for it.")
                } else {
                    Text(t("rest.be_honest_captains_balance"))
                }
            }

            Section("Position") {
                PositionChips(sport: sport, position: form.binding(sport, \.position))
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }

            Section("Team & league") {
                TextField(t("rest.team_you_play_for"), text: teamNameBinding)
                OptionMenu(title: "Age group", selection: form.ageGroupBinding(sport))
                if sport.usesDivisions {
                    OptionMenu(title: "Division you play in", selection: form.divisionBinding(sport, target: false))
                    OptionMenu(title: "Division you're aiming for", selection: form.divisionBinding(sport, target: true))
                    DivisionLadder(
                        current: form.detail(for: sport).division,
                        target: form.detail(for: sport).target
                    )
                    .padding(.vertical, 6)
                }
                Stepper(
                    "Years playing: \(form.detail(for: sport).yearsPlaying ?? 0)",
                    value: yearsBinding,
                    in: 0...60
                )
            }

            Section {
                SportStatsSection(sport: sport, form: form)
            } header: {
                Text("Your \(sport.label.lowercased()) stats")
            } footer: {
                Text(t("rest.all_optional_player_card"))
            }
        }
    }

    private var teamNameBinding: Binding<String> {
        Binding(
            get: { form.detail(for: sport).teamName ?? "" },
            set: { newValue in form.mutate(sport) { $0.teamName = newValue.nonEmpty } }
        )
    }

    private var yearsBinding: Binding<Int> {
        Binding(
            get: { form.detail(for: sport).yearsPlaying ?? 0 },
            set: { newValue in form.mutate(sport) { $0.yearsPlaying = newValue == 0 ? nil : newValue } }
        )
    }
}

struct LogisticsForm: View {
    @Bindable var form: ProfileFormModel

    var body: some View {
        Form {
            Section("Based") {
                TextField(t("rest.area_or_town"), text: $form.area)
                TextField(t("rest.postcode_first_part"), text: $form.postcode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            Section {
                Picker("Will travel", selection: $form.travelRadiusMiles) {
                    ForEach([5, 10, 15, 20, 30, 50], id: \.self) { miles in
                        Text("\(miles) miles").tag(miles)
                    }
                }
                OptionMenu(title: "Transport", selection: $form.transport)
                if form.transport?.offersLifts == true {
                    Stepper("Spare seats: \(form.spareSeats)", value: $form.spareSeats, in: 0...6)
                }
            } header: {
                Text(t("rest.travel"))
            } footer: {
                Text(t("rest.away_fixtures_lifts"))
            }

            Section {
                WeekdayPicker(selected: $form.preferredDays)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } header: {
                Text(t("rest.usual_days"))
            } footer: {
                Text(t("rest.availability_starting_point"))
            }

            Section("Anything else") {
                TextField(t("rest.no_saturdays_example"), text: $form.logisticsNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
}
