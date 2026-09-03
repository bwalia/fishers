import SwiftUI

struct EventDetailView: View {
    @Environment(AppState.self) private var app
    let event: Event

    @State private var attendees: [Attendee] = []
    @State private var products: [Product] = []
    @State private var preOrderQuantities: [UUID: Int] = [:]
    @State private var isPaying = false
    @State private var isOrdering = false
    @State private var orderPlaced: Order?
    @State private var errorMessage: String?

    private var me: Attendee? {
        attendees.first { $0.user.id == app.currentUser?.id }
    }

    private var goingCount: Int { attendees.filter { $0.status == .going }.count }
    private var maybeCount: Int { attendees.filter { $0.status == .maybe }.count }

    var body: some View {
        List {
            headerSection
            if event.eventSubtype == .nets {
                netsSection
            }
            if event.eventSubtype.isGame {
                matchSection
            }
            rsvpSection
            if event.hasFee {
                paymentSection
            }
            if !products.isEmpty {
                preOrderSection
            }
            attendeesSection
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SubtypeBadge(subtype: event.eventSubtype)
                    Spacer()
                    if event.status == .cancelled {
                        Text("Cancelled")
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                }
                Label {
                    Text(event.startAt, format: .dateTime.weekday(.wide).day().month().year())
                } icon: {
                    Image(systemName: "calendar")
                }
                Label {
                    Text("\(event.startAt.formatted(date: .omitted, time: .shortened)) – \(event.endAt.formatted(date: .omitted, time: .shortened))")
                } icon: {
                    Image(systemName: "clock")
                }
                if let venue = event.venue {
                    Label {
                        VStack(alignment: .leading) {
                            Text(venue.name)
                            if let address = venue.address {
                                Text(address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                }
                if let capacity = event.capacity {
                    Label("\(goingCount)/\(capacity) confirmed", systemImage: "person.2")
                }
                if event.hasFee {
                    Label {
                        Text("\((event.feeAmount ?? 0).money(event.currency ?? "GBP")) per player")
                    } icon: {
                        Image(systemName: "sterlingsign.circle")
                    }
                }
                if let error = errorMessage {
                    ErrorBanner(message: error)
                }
            }
            .font(.subheadline)
        }
    }

    private var netsSection: some View {
        Section("Nets") {
            if let lanes = event.laneCount {
                Label("\(lanes) lanes", systemImage: "square.split.2x1")
            }
            if let maxPerLane = event.maxPerLane {
                Label("Max \(maxPerLane) per lane", systemImage: "person.3")
            }
            if event.bowlingMachine == true {
                Label("Bowling machine available", systemImage: "gearshape.2")
            }
            ForEach(laneGroups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title).font(.subheadline.weight(.semibold))
                    Text(group.names)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
    }

    private var matchSection: some View {
        Section("Match") {
            if let format = event.format {
                Label(format, systemImage: "timer")
            }
            if let opposition = event.opposition {
                Label("vs \(opposition)", systemImage: "shield.lefthalf.filled")
            }
            if let homeOrAway = event.homeOrAway {
                Label(homeOrAway.capitalized, systemImage: homeOrAway == "home" ? "house" : "arrow.right.circle")
            }
            if app.isCaptainOrAdmin {
                NavigationLink {
                    SquadPickerView(event: event)
                } label: {
                    Label("Pick squad", systemImage: "person.crop.rectangle.stack")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .font(.subheadline)
    }

    private var rsvpSection: some View {
        Section("Your RSVP") {
            HStack(spacing: 8) {
                ForEach(RSVPStatus.allCases, id: \.self) { status in
                    Button {
                        Task { await rsvp(status) }
                    } label: {
                        Label(status.label, systemImage: status.systemImage)
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(me?.status == status ? status.color : .gray)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    private var paymentSection: some View {
        Section("Payment") {
            if me?.hasPaid == true {
                Label("Paid \((event.feeAmount ?? 0).money(event.currency ?? "GBP"))", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if me?.status == .going {
                Button {
                    Task { await pay() }
                } label: {
                    HStack {
                        if isPaying {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "applelogo")
                            Text("Pay \((event.feeAmount ?? 0).money(event.currency ?? "GBP"))")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.black, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isPaying)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } else {
                Text("RSVP as Going to pay the fee.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preOrderSection: some View {
        Section {
            ForEach(products) { product in
                HStack {
                    Image(systemName: product.category.systemImage)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name).font(.subheadline.weight(.medium))
                        Text(product.price.money(product.currency))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Stepper(
                        value: binding(for: product.id),
                        in: 0...9
                    ) {
                        Text("\(preOrderQuantities[product.id] ?? 0)")
                            .font(.subheadline.monospacedDigit())
                            .frame(minWidth: 20)
                    }
                    .fixedSize()
                }
            }
            if preOrderTotal > 0 {
                Button {
                    Task { await placePreOrder() }
                } label: {
                    if isOrdering {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Place order · \(preOrderTotal.money("GBP"))")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isOrdering)
            }
            if let orderPlaced {
                Label("Order confirmed · \(orderPlaced.totalAmount.money(orderPlaced.currency))", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("Pre-order tea & kit")
        } footer: {
            Text("Order by the night before the session.")
        }
    }

    private var attendeesSection: some View {
        Section("Attendees · \(goingCount) going, \(maybeCount) maybe") {
            if attendees.isEmpty {
                Text("No responses yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(attendees.sorted { $0.status.rawValue < $1.status.rawValue }) { attendee in
                HStack(spacing: 10) {
                    AvatarView(user: attendee.user, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attendee.user.name).font(.subheadline)
                        if let position = attendee.user.position {
                            Text(position).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if event.hasFee && attendee.status == .going {
                        Image(systemName: attendee.hasPaid ? "sterlingsign.circle.fill" : "sterlingsign.circle")
                            .foregroundStyle(attendee.hasPaid ? .green : .secondary)
                    }
                    Image(systemName: attendee.status.systemImage)
                        .foregroundStyle(attendee.status.color)
                }
            }
        }
    }

    // MARK: Derived

    private struct LaneGroup {
        let title: String
        let names: String
    }

    /// Auto-split confirmed players into lane groups with rotating time slots.
    private var laneGroups: [LaneGroup] {
        guard let lanes = event.laneCount, lanes > 0 else { return [] }
        let going = attendees.filter { $0.status == .going }
        guard !going.isEmpty else { return [] }
        let perLane = event.maxPerLane ?? 6
        let groupCount = min(lanes, max(1, Int(ceil(Double(going.count) / Double(perLane)))))
        let slotLength = event.endAt.timeIntervalSince(event.startAt) / Double(groupCount)
        var groups: [LaneGroup] = []
        for index in 0..<groupCount {
            let members = going.enumerated()
                .filter { $0.offset % groupCount == index }
                .map { $0.element.user.name }
            let slotStart = event.startAt.addingTimeInterval(slotLength * Double(index))
            let slotEnd = slotStart.addingTimeInterval(slotLength)
            let window = "\(slotStart.formatted(date: .omitted, time: .shortened))–\(slotEnd.formatted(date: .omitted, time: .shortened))"
            groups.append(LaneGroup(
                title: "Lane \(index + 1) · \(window)",
                names: members.joined(separator: ", ")
            ))
        }
        return groups
    }

    private var preOrderTotal: Int {
        products.reduce(0) { total, product in
            total + product.price * (preOrderQuantities[product.id] ?? 0)
        }
    }

    private func binding(for productId: UUID) -> Binding<Int> {
        Binding(
            get: { preOrderQuantities[productId] ?? 0 },
            set: { preOrderQuantities[productId] = $0 }
        )
    }

    // MARK: Actions

    private func load() async {
        do {
            async let attendeesTask = app.api.attendees(eventId: event.id)
            async let productsTask = app.api.products(clubId: event.clubId)
            let (loadedAttendees, loadedProducts) = try await (attendeesTask, productsTask)
            attendees = loadedAttendees
            products = loadedProducts.filter { $0.category == .food || $0.category == .kitHire }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rsvp(_ status: RSVPStatus) async {
        do {
            try await app.api.rsvp(eventId: event.id, status: status)
            attendees = try await app.api.attendees(eventId: event.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pay() async {
        isPaying = true
        defer { isPaying = false }
        do {
            _ = try await app.api.createPaymentIntent(eventId: event.id)
            attendees = try await app.api.attendees(eventId: event.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func placePreOrder() async {
        isOrdering = true
        defer { isOrdering = false }
        let items = preOrderQuantities
            .filter { $0.value > 0 }
            .map { CreateOrderItem(productId: $0.key, quantity: $0.value) }
        guard !items.isEmpty else { return }
        do {
            let order = try await app.api.createOrder(
                CreateOrderRequest(eventId: event.id, note: nil, items: items)
            )
            orderPlaced = order
            preOrderQuantities = [:]
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        EventDetailView(event: MockData.events.first(where: { $0.eventSubtype == .nets })!)
    }
    .environment(AppState(demoMode: true))
}
