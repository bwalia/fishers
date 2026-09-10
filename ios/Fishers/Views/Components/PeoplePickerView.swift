import SwiftUI

/// Pick one person, from tabbed lists.
///
/// Two full teams plus the officials is thirty names. As one flat list that is
/// a mess to read and worse to search, so each side gets its own tab and you
/// only ever look at one team at a time — which is how anybody at a ground
/// thinks about it anyway.
struct PeoplePickerView: View {
    struct Person: Identifiable, Equatable {
        let id: UUID
        let name: String
        var note: String?
    }

    struct Group: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let people: [Person]
    }

    let groups: [Group]
    @Binding var chosen: UUID?
    /// Below this many names in a tab, a search field is one more thing to
    /// read past.
    var searchFrom: Int = 8
    var empty: String = "Nobody to choose from yet."

    @State private var tab: String = ""
    @State private var filter = ""

    private var shown: [Group] { groups.filter { !$0.people.isEmpty } }

    private var active: Group? {
        shown.first { $0.label == tab } ?? shown.first
    }

    private var people: [Person] {
        guard let active else { return [] }
        let term = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return active.people }
        return active.people.filter { $0.name.lowercased().contains(term) }
    }

    var body: some View {
        if shown.isEmpty {
            Text(empty)
                .font(FishersTheme.footnote)
                .foregroundStyle(.secondary)
        } else {
            if shown.count > 1 {
                Picker("Team", selection: Binding(
                    get: { active?.label ?? "" },
                    set: { tab = $0; filter = "" }
                )) {
                    ForEach(shown) { group in
                        Text("\(group.label) (\(group.people.count))").tag(group.label)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if let active, active.people.count >= searchFrom {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(active.label)", text: $filter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            ForEach(people) { person in
                Button {
                    chosen = person.id
                } label: {
                    HStack(spacing: FishersTheme.space1) {
                        AvatarView(name: person.name, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name).foregroundStyle(.primary)
                            if let note = person.note {
                                Text(note)
                                    .font(FishersTheme.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if chosen == person.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(FishersTheme.pitch)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: FishersTheme.minTap)
                .accessibilityAddTraits(chosen == person.id ? [.isSelected] : [])
            }

            if people.isEmpty, let active {
                Text("Nobody by that name in \(active.label).")
                    .font(FishersTheme.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
