import SwiftUI

/// Kit for sale, across every club.
///
/// A club with a spare set of pads needs a bigger room than its own
/// membership, so this is the whole app's marketplace rather than one club's
/// shelf. Money is settled in person — a listing is an advert and a
/// reservation, not a checkout.
struct ShopView: View {
    @State private var listings: [Product] = []
    @State private var search = ""
    @State private var condition: String?
    @State private var loading = true
    @State private var error: String?
    /// The pending search. Held so the next keystroke can cancel it — without
    /// that, waiting 350ms per keystroke is still one request per letter, only
    /// later.
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                Picker("Condition", selection: $condition) {
                    Text("Everything").tag(String?.none)
                    Text("Second-hand").tag(String?.some("used"))
                    Text("Brand new").tag(String?.some("new"))
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }

            if let error {
                Text(error).foregroundStyle(FishersTheme.red600)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if listings.isEmpty {
                emptyState
            } else {
                ForEach(listings) { product in
                    NavigationLink {
                        ListingDetailView(productId: product.id)
                    } label: {
                        ListingRow(product: product)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fishersList()
        .searchable(text: $search, prompt: "Bats, pads, a club shirt")
        .navigationTitle("Kit for sale")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: condition) { _, _ in Task { await load() } }
        // Searching on every keystroke would be a request per letter. Waiting
        // until they stop typing is one request per search.
        .onChange(of: search) { _, _ in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bag")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(search.isEmpty ? "Nothing is for sale yet." : "Nothing matched that.")
                .font(.headline)
            Text(
                search.isEmpty
                    ? "When a club lists a bat or a spare set of pads, it turns up here."
                    : "Try a shorter search, or look through everything."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .listRowSeparator(.hidden)
    }

    private func load() async {
        let wanted = search
        loading = listings.isEmpty
        do {
            let found = try await FishersAPI.marketplace(condition: condition, search: search)
            // A slower earlier search must not overwrite a later one.
            guard wanted == search else { return }
            listings = found
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// One line in the list: the photograph if there is one, what it is, and what
/// it costs. Enough to decide whether to open it.
private struct ListingRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(product.priceLine)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(
                    [product.conditionLabel, product.brand, product.size]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if product.isSold {
                Text("Sold")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var thumbnail: some View {
        let side: CGFloat = 60
        if let first = product.photos?.first, let url = URL(string: first) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: side, height: side)
                .overlay(Image(systemName: "camera").foregroundStyle(.secondary))
        }
    }
}
