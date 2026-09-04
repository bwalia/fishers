import Foundation
import SwiftUI

/// Editable copy of everything on a player's profile. Shared by the first-run
/// setup flow and the later edit sheet so both collect exactly the same fields.
@Observable
final class ProfileFormModel {
    var name: String
    var phone: String
    var emergencyContact: String

    /// Ordered — the first pick is offered as the primary sport.
    var selectedSports: [Sport]
    var primarySport: Sport?
    private var sportDetails: [String: SportProfile]

    var area: String
    var postcode: String
    var travelRadiusMiles: Int
    var transport: TransportMode?
    var spareSeats: Int
    var preferredDays: Set<Int>
    var logisticsNotes: String

    init(user: PublicUser?) {
        name = user?.name ?? ""
        phone = user?.phone ?? ""
        emergencyContact = user?.emergencyContact ?? ""

        let profiles = user?.profiles ?? []
        selectedSports = profiles.compactMap(\.sportKind)
        primarySport = Sport(rawValue: user?.primarySport ?? "") ?? profiles.first?.sportKind
        sportDetails = Dictionary(uniqueKeysWithValues: profiles.map { ($0.sport, $0) })

        let location = user?.location
        area = location?.area ?? ""
        postcode = location?.postcode ?? ""
        travelRadiusMiles = location?.travelRadiusMiles ?? 10
        transport = location?.transport
        spareSeats = location?.spareSeats ?? 0
        preferredDays = Set(location?.preferredDays ?? [])
        logisticsNotes = location?.notes ?? ""
    }

    // MARK: Sports

    func isSelected(_ sport: Sport) -> Bool { selectedSports.contains(sport) }

    func toggle(_ sport: Sport) {
        if let index = selectedSports.firstIndex(of: sport) {
            selectedSports.remove(at: index)
            sportDetails[sport.rawValue] = nil
            if primarySport == sport { primarySport = selectedSports.first }
        } else {
            selectedSports.append(sport)
            if primarySport == nil { primarySport = sport }
        }
    }

    func detail(for sport: Sport) -> SportProfile {
        sportDetails[sport.rawValue] ?? SportProfile(sport: sport.rawValue)
    }

    func mutate(_ sport: Sport, _ change: (inout SportProfile) -> Void) {
        var detail = detail(for: sport)
        change(&detail)
        sportDetails[sport.rawValue] = detail
    }

    func binding<Value>(_ sport: Sport, _ keyPath: WritableKeyPath<SportProfile, Value>) -> Binding<Value> {
        Binding(
            get: { self.detail(for: sport)[keyPath: keyPath] },
            set: { newValue in self.mutate(sport) { $0[keyPath: keyPath] = newValue } }
        )
    }

    /// Stats are stored as strings, so the form binds straight to them.
    func statBinding(_ sport: Sport, _ key: String) -> Binding<String> {
        Binding(
            get: { self.detail(for: sport).stats[key] ?? "" },
            set: { newValue in
                self.mutate(sport) { profile in
                    if newValue.isEmpty {
                        profile.stats[key] = nil
                    } else {
                        profile.stats[key] = newValue
                    }
                }
            }
        )
    }

    func tierBinding(_ sport: Sport) -> Binding<SkillTier?> {
        Binding(
            get: { SkillTier(stored: self.detail(for: sport).skillLevel) },
            set: { tier in self.mutate(sport) { $0.skillLevel = tier?.label } }
        )
    }

    func divisionBinding(_ sport: Sport, target: Bool) -> Binding<Division?> {
        Binding(
            get: {
                let detail = self.detail(for: sport)
                return Division(stored: target ? detail.targetDivision : detail.currentDivision)
            },
            set: { division in
                self.mutate(sport) {
                    if target { $0.targetDivision = division?.rawValue } else { $0.currentDivision = division?.rawValue }
                }
            }
        )
    }

    func ageGroupBinding(_ sport: Sport) -> Binding<AgeGroup?> {
        Binding(
            get: { AgeGroup(stored: self.detail(for: sport).ageGroup) },
            set: { group in self.mutate(sport) { $0.ageGroup = group?.rawValue } }
        )
    }

    // MARK: Validation

    var isNameValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasSports: Bool { !selectedSports.isEmpty }

    /// A sport is done once the player has said what standard they play at.
    func isDetailComplete(_ sport: Sport) -> Bool {
        detail(for: sport).tier != nil
    }

    var isComplete: Bool {
        isNameValid && hasSports && selectedSports.allSatisfy(isDetailComplete)
    }

    // MARK: Output

    var update: ProfileUpdate {
        var payload = ProfileUpdate(
            name: name.trimmingCharacters(in: .whitespaces),
            sportProfiles: selectedSports.map(detail(for:)),
            primarySport: (primarySport ?? selectedSports.first)?.rawValue
        )
        payload.phone = phone.nonEmpty
        payload.emergencyContact = emergencyContact.nonEmpty
        payload.location = PlayerLocation(
            area: area.nonEmpty,
            postcode: postcode.nonEmpty,
            travelRadiusMiles: travelRadiusMiles,
            transport: transport,
            spareSeats: transport?.offersLifts == true ? spareSeats : nil,
            preferredDays: preferredDays.isEmpty ? nil : preferredDays.sorted(),
            notes: logisticsNotes.nonEmpty
        )
        return payload
    }
}

extension String {
    /// Trimmed, or nil when there is nothing left — keeps blank fields out of the payload.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
