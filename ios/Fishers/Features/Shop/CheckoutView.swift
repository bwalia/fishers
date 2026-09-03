import SwiftUI

/// Cart review and pre-order. Orders are placed against the club shop and
/// settled at the ground, so there's no card step here.
struct CheckoutView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    let cart: CartModel

    @State private var note = ""
    @State private var isPlacing = false
    @State private var errorMessage: String?
    @State private var placedOrder: Order?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        ErrorBanner(message: errorMessage)
                            .listRowInsets(EdgeInsets())
                    }
                }

                if let placedOrder {
                    Section {
                        Label("Order placed", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                        LabeledContent("Total", value: placedOrder.totalAmount.money(placedOrder.currency))
                        Text("Collect at the ground — the club will confirm on the day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if cart.isEmpty {
                    ContentUnavailableView("Your cart is empty", systemImage: "cart")
                } else {
                    Section("Order") {
                        ForEach(cart.lines) { line in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.product.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(line.product.price.money(line.product.currency))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Stepper(
                                    "\(line.quantity)",
                                    onIncrement: { cart.add(line.product) },
                                    onDecrement: { cart.remove(line.product) }
                                )
                                .labelsHidden()
                                Text("\(line.quantity)")
                                    .monospacedDigit()
                                    .frame(minWidth: 20)
                                Text(line.lineTotal.money(line.product.currency))
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minWidth: 60, alignment: .trailing)
                            }
                        }
                    }

                    Section("Note for the club") {
                        TextField("e.g. no onions, collecting at tea", text: $note, axis: .vertical)
                            .lineLimit(1...3)
                    }

                    Section {
                        LabeledContent("Total") {
                            Text(cart.total.money(cart.lines.first?.product.currency ?? "GBP"))
                                .font(.headline)
                        }
                    }
                }
            }
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(placedOrder == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPlacing {
                        ProgressView()
                    } else if placedOrder == nil {
                        Button("Place order") { place() }
                            .disabled(cart.isEmpty)
                    }
                }
            }
        }
    }

    private func place() {
        errorMessage = nil
        isPlacing = true
        Task {
            defer { isPlacing = false }
            do {
                let request = CreateOrderRequest(eventId: nil, note: note.nonEmpty, items: cart.orderItems)
                placedOrder = try await app.api.createOrder(request)
                cart.clear()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    CheckoutView(cart: CartModel())
        .environment(AppState(demoMode: true))
}
