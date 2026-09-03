import Foundation
import Observation

struct CartLine: Identifiable {
    let product: Product
    var quantity: Int

    var id: UUID { product.id }
    var lineTotal: Int { product.price * quantity }
}

@Observable
final class CartModel {
    private(set) var lines: [CartLine] = []

    var itemCount: Int { lines.reduce(0) { $0 + $1.quantity } }
    var total: Int { lines.reduce(0) { $0 + $1.lineTotal } }
    var isEmpty: Bool { lines.isEmpty }

    func quantity(of product: Product) -> Int {
        lines.first { $0.product.id == product.id }?.quantity ?? 0
    }

    func add(_ product: Product) {
        if let index = lines.firstIndex(where: { $0.product.id == product.id }) {
            lines[index].quantity += 1
        } else {
            lines.append(CartLine(product: product, quantity: 1))
        }
    }

    func remove(_ product: Product) {
        guard let index = lines.firstIndex(where: { $0.product.id == product.id }) else { return }
        if lines[index].quantity > 1 {
            lines[index].quantity -= 1
        } else {
            lines.remove(at: index)
        }
    }

    func clear() {
        lines = []
    }

    var orderItems: [CreateOrderItem] {
        lines.map { CreateOrderItem(productId: $0.product.id, quantity: $0.quantity) }
    }
}
