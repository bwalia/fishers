import Foundation

/// A believable "London Lords CC" dataset so the app demos fully offline.
/// Fixed UUIDs keep identity stable across launches; event dates are generated
/// around the current season so the calendar always has content.
enum MockData {
    // MARK: IDs

    static let currentUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let clubId = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let badmintonClubId = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let firstXIId = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let fridayBadmintonId = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let venueId = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let indoorVenueId = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!

    // MARK: People

    /// The state a brand-new sign-up lands in: an account, nothing else. Demo
    /// mode starts here so the first thing you see is profile setup.
    static let newUser = User(
        id: currentUserId,
        name: "Bal Walia",
        email: "bal@example.com"
    )

    /// The same player once setup is done — used as the "finished profile" seed.
    static let currentUser = User(
        id: currentUserId,
        name: "Bal Walia",
        email: "bal@example.com",
        phone: "+44 7700 900123",
        avatarUrl: nil,
        sports: ["cricket", "badminton"],
        position: "All-rounder",
        skillLevel: "Club standard",
        emergencyContact: "Sam Walia · +44 7700 900456",
        primarySport: Sport.cricket.rawValue,
        sportProfiles: [
            SportProfile(
                sport: Sport.cricket.rawValue,
                position: "All-rounder",
                skillLevel: SkillTier.club.label,
                currentDivision: Division.division3.rawValue,
                targetDivision: Division.division1.rawValue,
                ageGroup: AgeGroup.senior.rawValue,
                teamName: "Lords 1st XI",
                yearsPlaying: 12,
                stats: [
                    "batting_style": "Right-hand",
                    "bowling_style": "Right-arm medium",
                    "batting_number": "5",
                    "batting_average": "27.4",
                    "bowling_average": "21.8",
                    "high_score": "78",
                    "wickets": "46",
                    "catches": "31",
                    "matches": "84",
                ]
            ),
            SportProfile(
                sport: Sport.badminton.rawValue,
                position: "Doubles",
                skillLevel: SkillTier.intermediate.label,
                ageGroup: AgeGroup.senior.rawValue,
                teamName: "Friday Badminton",
                yearsPlaying: 4,
                stats: [
                    "discipline": "Doubles",
                    "racket_hand": "Right",
                    "club_grade": "Club league",
                    "ladder_position": "7",
                    "matches": "38",
                    "win_rate": "61",
                ]
            ),
        ],
        location: PlayerLocation(
            area: "Kentish Town",
            postcode: "NW5",
            travelRadiusMiles: 15,
            transport: .driverWithSeats,
            spareSeats: 3,
            preferredDays: [Weekday.wednesday.rawValue, Weekday.saturday.rawValue, Weekday.sunday.rawValue],
            notes: "Can do away games if we leave after 12 on Saturdays."
        ),
        reliability: ReliabilityScore.compute(
            invitesReceived: 18,
            responded: 17,
            saidGoing: 14,
            turnedUp: 13,
            lateCancellations: 1,
            feesDue: 12,
            feesPaid: 11
        )
    )

    static let squad: [User] = [
        currentUser,
        user("00000000-0000-0000-0000-000000000002", "Ravi Sharma", "Batter", .advanced, .division2, seed: 1),
        user("00000000-0000-0000-0000-000000000003", "James O'Neill", "Wicketkeeper", .club, .division3, seed: 2),
        user("00000000-0000-0000-0000-000000000004", "Adeel Khan", "Fast Bowler", .advanced, .division1, seed: 3),
        user("00000000-0000-0000-0000-000000000005", "Tom Bradley", "Batter", .improver, .division5, seed: 4),
        user("00000000-0000-0000-0000-000000000006", "Sanjay Patel", "Spinner", .intermediate, .division4, seed: 5),
        user("00000000-0000-0000-0000-000000000007", "Chris Field", "All-rounder", .intermediate, .division3, seed: 6),
        user("00000000-0000-0000-0000-000000000008", "Danny Osei", "Fast Bowler", .advanced, .division2, seed: 7),
        user("00000000-0000-0000-0000-000000000009", "Uzair Ahmed", "Batter", .intermediate, .division3, seed: 8),
        user("00000000-0000-0000-0000-00000000000a", "Rob Chambers", "Batter", .club, .division3, seed: 9),
        user("00000000-0000-0000-0000-00000000000b", "Nikhil Rao", "Spinner", .beginner, .social, seed: 10),
        user("00000000-0000-0000-0000-00000000000c", "Will Turner", "All-rounder", .intermediate, .division4, seed: 11),
        user("00000000-0000-0000-0000-00000000000d", "Kunal Mehta", "Wicketkeeper", .improver, .division5, seed: 12),
    ]

    /// Squad members get a cricket profile and a reliability record so the
    /// captain's squad picker and profile comparisons have real numbers.
    private static func user(
        _ id: String,
        _ name: String,
        _ position: String,
        _ tier: SkillTier,
        _ division: Division,
        seed: Int
    ) -> User {
        let invites = 10 + seed % 7
        let responded = max(0, invites - seed % 3)
        let saidGoing = max(1, responded - seed % 4)
        let turnedUp = max(0, saidGoing - (seed % 5 == 0 ? 2 : 0))
        let feesDue = max(1, saidGoing - 1)
        let feesPaid = max(0, feesDue - (seed % 4 == 0 ? 2 : 0))
        return User(
            id: UUID(uuidString: id)!,
            name: name,
            email: name.lowercased().replacingOccurrences(of: " ", with: ".").replacingOccurrences(of: "'", with: "") + "@example.com",
            phone: nil,
            avatarUrl: nil,
            sports: ["cricket"],
            position: position,
            skillLevel: tier.label,
            emergencyContact: nil,
            primarySport: Sport.cricket.rawValue,
            sportProfiles: [
                SportProfile(
                    sport: Sport.cricket.rawValue,
                    position: position,
                    skillLevel: tier.label,
                    currentDivision: division.rawValue,
                    targetDivision: division.next?.rawValue,
                    ageGroup: AgeGroup.senior.rawValue,
                    teamName: "Lords 1st XI",
                    yearsPlaying: 3 + seed,
                    stats: [
                        "batting_average": String(format: "%.1f", 14.0 + Double(seed) * 1.6),
                        "wickets": "\(seed * 4)",
                        "matches": "\(20 + seed * 3)",
                    ]
                )
            ],
            location: PlayerLocation(
                area: ["Camden", "Islington", "Hackney", "Clapham"][seed % 4],
                postcode: nil,
                travelRadiusMiles: 10 + (seed % 3) * 5,
                transport: seed % 3 == 0 ? .driverWithSeats : (seed % 3 == 1 ? .publicTransport : .needsLift),
                spareSeats: seed % 3 == 0 ? 3 : nil,
                preferredDays: [Weekday.wednesday.rawValue, Weekday.saturday.rawValue],
                notes: nil
            ),
            reliability: ReliabilityScore.compute(
                invitesReceived: invites,
                responded: responded,
                saidGoing: saidGoing,
                turnedUp: turnedUp,
                lateCancellations: seed % 5 == 0 ? 2 : 0,
                feesDue: feesDue,
                feesPaid: feesPaid
            )
        )
    }

    // MARK: Clubs, teams, venues

    static let londonLords = Club(
        id: clubId,
        name: "London Lords CC",
        sportTypes: ["Cricket"],
        visibility: .inviteOnly,
        ownerId: squad[1].id,
        createdAt: nil
    )

    static let shuttleClub = Club(
        id: badmintonClubId,
        name: "Southbank Shuttlers",
        sportTypes: ["Badminton"],
        visibility: .publicClub,
        ownerId: currentUserId,
        createdAt: nil
    )

    static let clubs: [Club] = [londonLords, shuttleClub]

    static let teams: [Team] = [
        Team(
            id: firstXIId,
            clubId: clubId,
            sport: "Cricket",
            name: "Lords 1st XI",
            division: Division.division3.rawValue,
            ageGroup: AgeGroup.senior.rawValue
        ),
        Team(
            id: fridayBadmintonId,
            clubId: badmintonClubId,
            sport: "Badminton",
            name: "Friday Badminton",
            division: Division.social.rawValue,
            ageGroup: AgeGroup.senior.rawValue
        ),
    ]

    static let venues: [Venue] = [
        Venue(id: venueId, clubId: clubId, name: "Regent's Park Nets", address: "Outer Cir, London NW1", lat: 51.5313, lng: -0.1570),
        Venue(id: indoorVenueId, clubId: clubId, name: "Lord's Indoor Centre", address: "St John's Wood Rd, London NW8", lat: 51.5299, lng: -0.1729),
    ]

    static var members: [ClubMember] {
        squad.enumerated().map { index, player in
            ClubMember(
                clubId: clubId,
                userId: player.id,
                role: index == 1 ? .admin : (player.id == currentUserId ? .captain : .member),
                status: "active",
                joinedAt: nil,
                user: player
            )
        }
    }

    // MARK: Events (generated around today's season)

    static var events: [Event] {
        var all: [Event] = []
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)

        // Wednesday Nets, 6-8pm, June-August.
        var day = date(year: year, month: 6, day: 1)
        while calendar.component(.weekday, from: day) != 4 { // 4 = Wednesday
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        var netsIndex = 0
        while calendar.component(.month, from: day) <= 8 {
            netsIndex += 1
            all.append(Event(
                id: derivedId("40000000", netsIndex),
                clubId: clubId,
                teamId: nil,
                sport: "Cricket",
                eventSubtype: .nets,
                title: "Wednesday Nets",
                venueId: venueId,
                venue: venues[0],
                startAt: at(day, hour: 18),
                endAt: at(day, hour: 20),
                recurrenceRule: "FREQ=WEEKLY;BYDAY=WE;UNTIL=\(year)0831",
                capacity: 18,
                feeAmount: 600,
                currency: "GBP",
                status: .scheduled,
                laneCount: 3,
                maxPerLane: 6,
                bowlingMachine: true
            ))
            day = calendar.date(byAdding: .day, value: 7, to: day)!
        }

        // A Sunday friendly next weekend and a league fixture after that.
        let nextSunday = next(weekday: 1, after: now)
        all.append(Event(
            id: derivedId("41000000", 1),
            clubId: clubId,
            teamId: firstXIId,
            sport: "Cricket",
            eventSubtype: .friendly,
            title: "Friendly vs Camden Casuals",
            venueId: venueId,
            venue: venues[0],
            startAt: at(nextSunday, hour: 13),
            endAt: at(nextSunday, hour: 19),
            recurrenceRule: nil,
            capacity: 13,
            feeAmount: 800,
            currency: "GBP",
            status: .scheduled,
            laneCount: nil, maxPerLane: nil, bowlingMachine: nil,
            format: "T20",
            opposition: "Camden Casuals",
            homeOrAway: "home"
        ))
        let leagueDay = Calendar.current.date(byAdding: .day, value: 7, to: nextSunday)!
        all.append(Event(
            id: derivedId("41000000", 2),
            clubId: clubId,
            teamId: firstXIId,
            sport: "Cricket",
            eventSubtype: .leagueMatch,
            title: "League: vs Hackney Hawks",
            venueId: nil,
            venue: nil,
            startAt: at(leagueDay, hour: 12),
            endAt: at(leagueDay, hour: 19),
            recurrenceRule: nil,
            capacity: 13,
            feeAmount: 1000,
            currency: "GBP",
            status: .scheduled,
            laneCount: nil, maxPerLane: nil, bowlingMachine: nil,
            format: "40 overs",
            opposition: "Hackney Hawks",
            homeOrAway: "away"
        ))

        // Friday badminton this week + a club social.
        let friday = next(weekday: 6, after: now)
        all.append(Event(
            id: derivedId("42000000", 1),
            clubId: badmintonClubId,
            teamId: fridayBadmintonId,
            sport: "Badminton",
            eventSubtype: .generic,
            title: "Friday Badminton",
            venueId: indoorVenueId,
            venue: venues[1],
            startAt: at(friday, hour: 19),
            endAt: at(friday, hour: 21),
            recurrenceRule: "FREQ=WEEKLY;BYDAY=FR",
            capacity: 12,
            feeAmount: 500,
            currency: "GBP",
            status: .scheduled,
            laneCount: nil, maxPerLane: nil, bowlingMachine: nil
        ))
        let socialDay = Calendar.current.date(byAdding: .day, value: 10, to: now)!
        all.append(Event(
            id: derivedId("43000000", 1),
            clubId: clubId,
            teamId: nil,
            sport: "Cricket",
            eventSubtype: .social,
            title: "End of Season BBQ",
            venueId: venueId,
            venue: venues[0],
            startAt: at(socialDay, hour: 17),
            endAt: at(socialDay, hour: 22),
            recurrenceRule: nil,
            capacity: nil,
            feeAmount: nil,
            currency: "GBP",
            status: .scheduled,
            laneCount: nil, maxPerLane: nil, bowlingMachine: nil
        ))

        return all.sorted { $0.startAt < $1.startAt }
    }

    // MARK: Products

    static let products: [Product] = [
        Product(id: pid(1), clubId: clubId, name: "Match Tea", description: "Sandwiches, samosas and chai after the session. Order by Tuesday 8pm.", price: 200, currency: "GBP", category: .food, stock: nil),
        Product(id: pid(2), clubId: clubId, name: "Cake & Coffee", description: "Homemade cake slice with filter coffee.", price: 250, currency: "GBP", category: .food, stock: 20),
        Product(id: pid(3), clubId: clubId, name: "Bat Hire", description: "Grade 2 English willow, per session.", price: 300, currency: "GBP", category: .kitHire, stock: 6),
        Product(id: pid(4), clubId: clubId, name: "Helmet Hire", description: "BSI-certified helmet, per session.", price: 150, currency: "GBP", category: .kitHire, stock: 8),
        Product(id: pid(5), clubId: clubId, name: "Match Ball (Dukes)", description: "Dukes Special County A, 5.5oz.", price: 1800, currency: "GBP", category: .equipment, stock: 12),
        Product(id: pid(6), clubId: clubId, name: "Training Balls x6", description: "Practice balls for nets.", price: 2400, currency: "GBP", category: .equipment, stock: 5),
        Product(id: pid(7), clubId: clubId, name: "Lords Club Cap", description: "Navy cap with club crest.", price: 1200, currency: "GBP", category: .merch, stock: 30),
        Product(id: pid(8), clubId: clubId, name: "Playing Shirt", description: "Club playing shirt, all sizes.", price: 2800, currency: "GBP", category: .merch, stock: 15),
    ]

    // MARK: Helpers

    private static func pid(_ n: Int) -> UUID {
        derivedId("50000000", n)
    }

    static func derivedId(_ prefix: String, _ n: Int) -> UUID {
        UUID(uuidString: "\(prefix)-0000-0000-0000-\(String(format: "%012d", n))")!
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func at(_ day: Date, hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private static func next(weekday: Int, after date: Date) -> Date {
        var day = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        while Calendar.current.component(.weekday, from: day) != weekday {
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        return day
    }
}
