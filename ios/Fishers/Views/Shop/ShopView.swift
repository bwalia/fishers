import SwiftUI

struct ShopView: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var clubContext: ClubContextStore
    @State private var products: [Product] = []
    @State private var showCheckout = false

    var body: some View {
        List {
            if clubContext.clubs.isEmpty {
                Text("Join a club to see its shop.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Club", selection: Binding(
                    get: { clubContext.activeClubId },
                    set: { if let id = $0 { clubContext.select(id) } }
                )) {
                    ForEach(clubContext.clubs) { club in
                        Text(club.name).tag(Optional(club.id))
                    }
                }
                .onChange(of: clubContext.activeClubId) { _, _ in
                    Task { await loadProducts() }
                }

                ForEach(products) { product in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(product.name).font(.headline)
                            Text(product.category.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.priceLabel)
                        Button {
                            if let clubId = clubContext.activeClubId {
                                cart.add(product, clubId: clubId)
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.tint)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Shop")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCheckout = true
                } label: {
                    Label("Cart (\(cart.lines.count))", systemImage: "cart")
                }
                .disabled(cart.lines.isEmpty)
            }
        }
        .sheet(isPresented: $showCheckout) {
            CheckoutView()
        }
        .task {
            if clubContext.clubs.isEmpty {
                await clubContext.bootstrap()
            }
            await loadProducts()
        }
    }

    private func loadProducts() async {
        guard let clubId = clubContext.activeClubId else { products = []; return }
        products = (try? await FishersAPI.products(clubId: clubId)) ?? []
    }
}

struct CheckoutView: View {
    @EnvironmentObject private var cart: CartStore
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(cart.lines) { line in
                    HStack {
                        Text(line.product.name)
                        Spacer()
                        Text("×\(line.quantity)")
                        Text(line.product.priceLabel)
                    }
                }
                Section {
                    HStack {
                        Text("Total")
                        Spacer()
                        Text(String(format: "£%.2f", Double(cart.totalCents) / 100))
                            .bold()
                    }
                }
                if let message {
                    Text(message).font(.footnote)
                }
            }
            .navigationTitle("Checkout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Place order") {
                        Task { await place() }
                    }
                }
            }
        }
    }

    private func place() async {
        guard let clubId = cart.clubId else { return }
        do {
            let order = try await FishersAPI.placeOrder(
                clubId: clubId,
                eventId: nil,
                items: cart.lines.map { ($0.product.id, $0.quantity) }
            )
            message = "Order \(order.id.uuidString.prefix(8)) placed"
            cart.clear()
        } catch {
            message = error.localizedDescription
        }
    }
}
