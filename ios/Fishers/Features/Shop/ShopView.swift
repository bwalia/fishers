import SwiftUI

struct ShopView: View {
    @Environment(AppState.self) private var app
    @State private var products: [Product] = []
    @State private var cart = CartModel()
    @State private var selectedCategory: ProductCategory?
    @State private var showCheckout = false
    @State private var showOrders = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var filtered: [Product] {
        guard let selectedCategory else { return products }
        return products.filter { $0.category == selectedCategory }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    categoryChips

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }

                    if filtered.isEmpty && !isLoading {
                        ContentUnavailableView(
                            "Nothing in the shop",
                            systemImage: "cart",
                            description: Text("Club products will appear here.")
                        )
                        .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filtered) { product in
                                ProductCard(
                                    product: product,
                                    quantityInCart: cart.quantity(of: product),
                                    onAdd: { cart.add(product) },
                                    onRemove: { cart.remove(product) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("Shop")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showOrders = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCheckout = true
                    } label: {
                        Label("Cart", systemImage: "cart")
                            .overlay(alignment: .topTrailing) {
                                if cart.itemCount > 0 {
                                    Text("\(cart.itemCount)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(.red, in: Circle())
                                        .offset(x: 10, y: -10)
                                }
                            }
                    }
                    .disabled(cart.isEmpty)
                }
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutView(cart: cart)
                    .environment(app)
            }
            .sheet(isPresented: $showOrders) {
                OrderHistoryView()
                    .environment(app)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", isOn: selectedCategory == nil) { selectedCategory = nil }
                ForEach(ProductCategory.allCases, id: \.self) { category in
                    chip(label: category.label, isOn: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    private func chip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isOn ? Color.accentColor : Color(.systemGray5), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            products = try await app.api.products(clubId: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProductCard: View {
    let product: Product
    let quantityInCart: Int
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: product.category.systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if let stock = product.stock, stock <= 5 {
                    Text("\(stock) left")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text(product.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            if let description = product.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            Spacer(minLength: 0)
            HStack {
                Text(product.price.money(product.currency))
                    .font(.subheadline.bold())
                Spacer()
                if quantityInCart == 0 {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                } else {
                    HStack(spacing: 8) {
                        Button(action: onRemove) {
                            Image(systemName: "minus.circle.fill")
                        }
                        Text("\(quantityInCart)")
                            .font(.subheadline.monospacedDigit().bold())
                        Button(action: onAdd) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    ShopView()
        .environment(AppState(demoMode: true))
}
