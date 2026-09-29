import SwiftUI

/// One thing for sale, in full.
///
/// Two readers, one screen. A buyer needs to know what it is, what state it is
/// in, where to collect it and who to ask — each of those under its own
/// heading, because an unlabelled paragraph under a price is not obviously the
/// description, and somebody who has never bought anything second-hand should
/// not have to work it out.
///
/// The seller needs none of that. They wrote it. Offering them "Message the
/// seller" on their own advert is the app saying it does not know who they
/// are, and reserving it would take their own kit off the marketplace and then
/// notify them about themselves. So they get their own panel instead.
struct ListingDetailView: View {
    let productId: UUID

    @StateObject private var chat = ChatStore()
    @State private var listing: MarketListing?
    @State private var error: String?
    @State private var reserving = false
    @State private var reserved = false
    @State private var asking = false
    @State private var openThread: ConversationSummary?

    var body: some View {
        ScrollView {
            if let listing {
                VStack(alignment: .leading, spacing: 20) {
                    Gallery(photos: listing.product.photos ?? [], title: listing.product.name)
                    header(listing)
                    if listing.mine {
                        OwnerPanel(listing: listing)
                    } else {
                        buyerPanel(listing)
                    }
                    Divider()
                    sections(listing)
                }
                .padding(16)
            } else if error == nil {
                ProgressView().padding(40).frame(maxWidth: .infinity)
            }

            if let error {
                Text(error)
                    .foregroundStyle(FishersTheme.red600)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(FishersTheme.mist)
        .navigationTitle(listing?.product.name ?? "Listing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .navigationDestination(item: $openThread) { conversation in
            ChatThreadView(conversation: conversation, store: chat)
        }
    }

    // MARK: - The top of the page

    private func header(_ listing: MarketListing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Tag(listing.product.categoryLabel, tint: .secondary)
                if let condition = listing.product.conditionLabel {
                    Tag(condition, tint: listing.product.condition == "used"
                        ? FishersTheme.pitch : FishersTheme.accent600)
                }
                if listing.product.negotiable == true && !listing.product.isSold {
                    Tag("Open to offers", tint: .secondary)
                }
            }

            Text(listing.product.name)
                .font(.title2.bold())

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(listing.product.priceLabel)
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                if listing.product.negotiable == true {
                    Text("or near offer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Label(
                listing.product.isSold ? "Sold — no longer available" : listing.product.availability,
                systemImage: listing.product.isSold ? "clock" : "checkmark"
            )
            .font(.subheadline)
            .foregroundStyle(listing.product.isSold ? FishersTheme.red600 : FishersTheme.pitch)
        }
    }

    // MARK: - What a buyer can do

    @ViewBuilder
    private func buyerPanel(_ listing: MarketListing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if reserved {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Reserved for you.", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(FishersTheme.pitch)
                    Text(
                        "The seller has been told. Arrange collection with them and pay them "
                            + "directly — nothing has been taken online."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FishersTheme.pitch.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    Task { await reserve(listing) }
                } label: {
                    Text(listing.product.isSold ? "Already gone" : reserving ? "Reserving…" : "Reserve it")
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(reserving || listing.product.isSold)

                Button {
                    Task { await ask(listing) }
                } label: {
                    Label(
                        asking ? "Opening…"
                            : listing.product.negotiable == true ? "Make an offer" : "Ask a question",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(asking)

                Label(
                    "Nothing is paid online. Reserving tells the seller you want it; you settle up "
                        + "when you collect.",
                    systemImage: "lock"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 10) {
                Circle()
                    .fill(FishersTheme.pitch)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String((listing.sellerName ?? listing.clubName).prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sold by").font(.caption).foregroundStyle(.secondary)
                    Text(listing.sellerName ?? listing.clubName).font(.subheadline.bold())
                    if listing.sellerName != nil {
                        Text(listing.clubName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            // Shown only when the seller asked for it — the server leaves these
            // out otherwise, so there is nothing here to forget to hide.
            if listing.sellerPhone != nil || listing.sellerEmail != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Happy to be contacted directly")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let phone = listing.sellerPhone, let url = URL(string: "tel:\(phone)") {
                        Link(phone, destination: url).font(.subheadline)
                    }
                    if let email = listing.sellerEmail, let url = URL(string: "mailto:\(email)") {
                        Link(email, destination: url).font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Everything worth reading, each under its own heading

    @ViewBuilder
    private func sections(_ listing: MarketListing) -> some View {
        Block("Description") {
            if let description = listing.product.description, !description.isEmpty {
                Text(description)
            } else {
                Text(
                    listing.mine
                        ? "No description was written. Adding one helps it sell."
                        : "No description was written. Ask the seller if you need to know more."
                )
                .foregroundStyle(.secondary)
            }
        }

        Block("Details") {
            VStack(spacing: 8) {
                Spec("Category", listing.product.categoryLabel)
                if let condition = listing.product.conditionLabel { Spec("Condition", condition) }
                if let brand = listing.product.brand { Spec("Make", brand) }
                if let size = listing.product.size { Spec("Size", size) }
                Spec("How many", listing.product.availability)
                if let note = listing.product.conditionNote { Spec("Wear and damage", note) }
            }
        }

        Block("Where to collect it") {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(FishersTheme.pitch)
                VStack(alignment: .leading, spacing: 2) {
                    Text(listing.clubName).font(.subheadline.bold())
                    Text(
                        listing.product.collectionNote
                            ?? "The seller has not said where yet — ask them before you travel."
                    )
                    .font(.subheadline)
                }
            }
        }

        if !listing.mine {
            Block("How buying works") {
                VStack(alignment: .leading, spacing: 10) {
                    Step(1, "Ask anything you need to.",
                         "Messages go to the seller here in the app."
                             + (listing.product.negotiable == true
                                ? " The price is open to offers, so say what you would pay." : ""))
                    Step(2, "Reserve it.",
                         "That holds it for you and tells the seller — it does not charge you anything.")
                    Step(3, "Collect and pay in person.",
                         "Cash or transfer, directly to the seller. No money goes through this app.")
                }
            }
        }
    }

    // MARK: - Doing things

    private func load() async {
        do {
            listing = try await FishersAPI.marketItem(productId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reserve(_ listing: MarketListing) async {
        reserving = true
        defer { reserving = false }
        do {
            _ = try await FishersAPI.placeOrder(
                clubId: listing.product.clubId,
                eventId: nil,
                items: [(listing.product.id, 1)]
            )
            reserved = true
            error = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Straight into the thread rather than a box on this screen: the
    /// conversation carries on there, and both of them already know where
    /// their messages live.
    private func ask(_ listing: MarketListing) async {
        asking = true
        defer { asking = false }
        do {
            let started = try await FishersAPI.enquire(about: listing.product.id)
            await chat.loadConversations()
            openThread = chat.conversations.first { $0.id == started.conversationId }
            if openThread == nil {
                error = "The conversation was opened, but it has not arrived in Chats yet."
            } else {
                error = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The same listing, to the person selling it.
private struct OwnerPanel: View {
    let listing: MarketListing

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("This is your listing", systemImage: "checkmark.circle")
                .font(.subheadline.bold())
                .foregroundStyle(FishersTheme.pitch)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FishersTheme.pitch.opacity(0.12), in: Capsule())

            Text("This is exactly how buyers see it.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Stat("People asking", "\(listing.enquiries ?? 0)")
                Stat("Photographs", "\(listing.product.photos?.count ?? 0)")
                Stat("Visible to", listing.product.listedPublicly == true ? "Every club" : "Your club")
            }

            if let asked = listing.enquiries, asked > 0 {
                Label(
                    asked == 1 ? "One person has asked about it — the message is in Chats."
                        : "\(asked) people have asked about it. The conversations are in Chats.",
                    systemImage: "bubble.left.and.bubble.right"
                )
                .font(.footnote)
            } else {
                Label("Nobody has asked about it yet. Questions arrive in Chats.",
                      systemImage: "bubble.left.and.bubble.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Editing lives on the web for now, so this says so rather than
            // offering a button that would go nowhere.
            if (listing.product.photos?.count ?? 0) == 0 {
                Text(
                    "It has no photographs. A listing without one is usually scrolled past — "
                        + "adding a couple is the single thing most likely to sell it."
                )
                .font(.footnote)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FishersTheme.accent600.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func Stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Every photograph, one at a time — swipe, or tap a dot.
private struct Gallery: View {
    let photos: [String]
    let title: String

    var body: some View {
        if photos.isEmpty {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 220)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "camera").font(.largeTitle)
                        Text("No photograph").font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                )
        } else {
            TabView {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    AsyncImage(url: URL(string: photo)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.1)
                    }
                    .clipped()
                    .accessibilityLabel("\(title) — photograph \(index + 1) of \(photos.count)")
                }
            }
            .tabViewStyle(.page)
            // The dots are white-on-white over a pale photograph otherwise.
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Small pieces

private struct Tag: View {
    let text: String
    let tint: Color

    init(_ text: String, tint: Color) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct Block<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(FishersTheme.cream, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Spec: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value).fontWeight(.medium)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
    }
}

private struct Step: View {
    let number: Int
    let title: String
    let detail: String

    init(_ number: Int, _ title: String, _ detail: String) {
        self.number = number
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(FishersTheme.pitch.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
