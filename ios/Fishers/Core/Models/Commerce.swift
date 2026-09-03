import Foundation

enum PaymentStatus: String, Codable {
    case pending
    case succeeded
    case failed
    case refunded
}

struct Payment: Codable, Identifiable, Hashable {
    var id: UUID
    var userId: UUID
    var eventId: UUID?
    var amount: Int
    var currency: String
    var status: PaymentStatus
    var stripePaymentIntentId: String?
    var createdAt: Date?
}

struct PaymentIntent: Codable, Hashable {
    var paymentId: UUID
    var clientSecret: String
    var amount: Int
    var currency: String
}

enum ProductCategory: String, Codable, CaseIterable {
    case food
    case kitHire = "kit_hire"
    case equipment
    case merch

    var label: String {
        switch self {
        case .food: return "Food & Tea"
        case .kitHire: return "Kit Hire"
        case .equipment: return "Equipment"
        case .merch: return "Merch"
        }
    }

    var systemImage: String {
        switch self {
        case .food: return "cup.and.saucer.fill"
        case .kitHire: return "bag.fill"
        case .equipment: return "sportscourt.fill"
        case .merch: return "tshirt.fill"
        }
    }
}

struct Product: Codable, Identifiable, Hashable {
    var id: UUID
    var clubId: UUID
    var name: String
    var description: String?
    var price: Int
    var currency: String
    var category: ProductCategory
    var stock: Int?
}

enum OrderStatus: String, Codable {
    case pending
    case confirmed
    case fulfilled
    case cancelled
}

struct OrderItem: Codable, Hashable {
    var productId: UUID
    var quantity: Int
    var unitPrice: Int
    var product: Product?
}

struct Order: Codable, Identifiable, Hashable {
    var id: UUID
    var userId: UUID
    var eventId: UUID?
    var status: OrderStatus
    var totalAmount: Int
    var currency: String
    var note: String?
    var createdAt: Date?
    var items: [OrderItem]
}

struct CreateOrderItem: Codable, Hashable {
    var productId: UUID
    var quantity: Int
}

struct CreateOrderRequest: Codable, Hashable {
    var eventId: UUID?
    var note: String?
    var items: [CreateOrderItem]
}

extension Int {
    /// Formats integer pence as a currency string, e.g. 600 -> "£6.00".
    func money(_ currency: String = "GBP") -> String {
        (Decimal(self) / 100).formatted(.currency(code: currency))
    }
}
