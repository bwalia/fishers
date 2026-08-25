import Foundation
import SwiftUI

@MainActor
final class CartStore: ObservableObject {
    struct Line: Identifiable, Hashable {
        let id = UUID()
        let product: Product
        var quantity: Int
    }

    @Published var lines: [Line] = []
    @Published var clubId: UUID?

    var totalCents: Int {
        lines.reduce(0) { $0 + $1.product.priceCents * $1.quantity }
    }

    func add(_ product: Product, clubId: UUID) {
        self.clubId = clubId
        if let idx = lines.firstIndex(where: { $0.product.id == product.id }) {
            lines[idx].quantity += 1
        } else {
            lines.append(Line(product: product, quantity: 1))
        }
    }

    func clear() {
        lines = []
        clubId = nil
    }
}
