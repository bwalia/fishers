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
                        Circle().fill(Color.accentColor.opacity(0.2))
                        Text(initials)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 84, height: 84)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("You") {
                TextField("Full name", text: $form.name)
                    .textContentType(.name)
                TextField("Mobile", text: $form.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }
            Section {
                TextField("Name · number", text: $form.emergencyContact)
                    .textContentType(.name)
            } header: {
                Text("Emergency contact")
            } footer: {
                Text("Only club admins can see this. Optional, but useful on away trips.")
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
                        Text("Main sport")
                            .font(.headline)
                        Text("Shown first on your profile and used for club suggestions.")
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
                Text("Your standard")
            } footer: {
                if let tier = form.detail(for: sport).tier, let next = tier.next {
                    Text("Next rung up: \(next.label). Log games and stats to make the case for it.")
                } else {
                    Text("Be honest — captains use this to balance sides, not to judge you.")
                }
            }

            Section("Position") {
                PositionChips(sport: sport, position: form.binding(sport, \.position))
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }

            Section("Team & league") {
                TextField("Team you play for", text: teamNameBinding)
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
                Text("All optional. They show on your player card and help captains pick balanced sides.")
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
                TextField("Area or town", text: $form.area)
                TextField("Postcode (first part is fine)", text: $form.postcode)
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
                Text("Travel")
            } footer: {
                Text("Away fixtures use this to sort lifts before the meet time is sent out.")
            }

            Section {
                WeekdayPicker(selected: $form.preferredDays)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            } header: {
                Text("Usual days")
            } footer: {
                Text("A starting point for your availability calendar — you can still change any single date.")
            }

            Section("Anything else") {
                TextField("e.g. no Saturdays before 2pm", text: $form.logisticsNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
    }
}
