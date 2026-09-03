import SwiftUI

/// Past and pending shop orders for the signed-in player.
struct OrderHistoryView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var orders: [Order] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        ErrorBanner(message: errorMessage)
                            .listRowInsets(EdgeInsets())
                    }
                }
                if orders.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No orders yet",
                        systemImage: "bag",
                        description: Text("Pre-orders from the club shop show up here.")
                    )
                }
                ForEach(orders) { order in
                    Section {
                        ForEach(order.items, id: \.productId) { item in
                            HStack {
                                Text(item.product?.name ?? "Item")
                                Spacer()
                                Text("×\(item.quantity)")
                                    .foregroundStyle(.secondary)
                                Text((item.unitPrice * item.quantity).money(order.currency))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .font(.subheadline)
                        }
                        if let note = order.note {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        HStack {
                            if let createdAt = order.createdAt {
                                Text(createdAt, format: .dateTime.day().month(.abbreviated))
                            }
                            Text(order.status.rawValue.capitalized)
                            Spacer()
                            Text(order.totalAmount.money(order.currency))
                        }
                    }
                }
            }
            .navigationTitle("My orders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            orders = try await app.api.ordersMine()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    OrderHistoryView()
        .environment(AppState(demoMode: true))
}
