import Foundation
import UIKit

// Step A of club payments, "easy paying": sharing the bill to WhatsApp, the
// rewritten pay screen, All arrived, cash at the ground, screenshots, the
// usual prices and the setup wizard. See docs/CLUB_PAYMENTS_V2_PLAN.md §10;
// backend/api/src/routes/easy_paying.rs is the source of truth.

// MARK: - Sharing the bill

/// `POST /events/{id}/bill/link`: the bill's pay link and the two messages
/// the server writes for the group. The app sends them as they are, so the
/// wording matches the website's and every other phone's.
struct BillLink: Decodable, Equatable {
    let url: String
    let expiresAt: Date?
    /// "🏏 Friday nets, Fri 20 Nov: £15.00 each. Tap to pay: …"
    let billMessage: String
    /// "Still to pay for Friday nets: Aman and Tom. Tap to pay: …"
    let reminderMessage: String
    /// Who still owes, by full name.
    let stillToPay: [String]

    enum CodingKeys: String, CodingKey {
        case url
        case expiresAt = "expires_at"
        case billMessage = "bill_message"
        case reminderMessage = "reminder_message"
        case stillToPay = "still_to_pay"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        expiresAt = try? c.decodeIfPresent(Date.self, forKey: .expiresAt)
        billMessage = try c.decodeIfPresent(String.self, forKey: .billMessage) ?? url
        reminderMessage = try c.decodeIfPresent(String.self, forKey: .reminderMessage) ?? billMessage
        stillToPay = (try? c.decodeIfPresent([String].self, forKey: .stillToPay)) ?? []
    }
}

/// WhatsApp, straight to "choose a chat" with the message written. Only
/// offered when WhatsApp is on the phone; the share sheet otherwise.
enum WhatsApp {
    static func sendURL(_ text: String) -> URL? {
        // Everything but the unreserved characters is encoded: a "+" or "&"
        // left bare in a query reads as a space or a second parameter.
        let unreserved = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?/:;,#@!$'()*"))
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.percentEncodedQueryItems = [URLQueryItem(name: "text", value: encoded)]
        return components.url
    }

    /// Needs `whatsapp` in LSApplicationQueriesSchemes (project.yml).
    @MainActor
    static var isInstalled: Bool {
        sendURL("").map { UIApplication.shared.canOpenURL($0) } ?? false
    }
}

/// `POST /events/{id}/bill/cash`.
struct CashRecorded: Decodable, Equatable {
    let recorded: Int
    let totalCents: Int
    /// A money admin's tick counts as received; a captain's waits for the
    /// treasurer to have the cash in hand.
    let received: Bool

    enum CodingKeys: String, CodingKey {
        case recorded, received
        case totalCents = "total_cents"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recorded = (try? c.decodeIfPresent(Int.self, forKey: .recorded)) ?? 0
        totalCents = (try? c.decodeIfPresent(Int.self, forKey: .totalCents)) ?? 0
        received = (try? c.decodeIfPresent(Bool.self, forKey: .received)) ?? false
    }
}

/// `POST /clubs/{id}/payments/confirm`, for All arrived.
struct ConfirmedMany: Decodable, Equatable {
    let confirmed: Int
    /// Already checked by somebody else: not an error.
    let skipped: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        confirmed = (try? c.decodeIfPresent(Int.self, forKey: .confirmed)) ?? 0
        skipped = (try? c.decodeIfPresent(Int.self, forKey: .skipped)) ?? 0
    }

    enum CodingKeys: String, CodingKey { case confirmed, skipped }
}

// MARK: - The club's usual prices

/// What the club usually charges, offered on every new nets session and
/// match. Read from `settings`; written only through `UsualPricesBody`.
struct UsualPrices: Equatable {
    struct Price: Equatable {
        let mode: CostMode
        let amountCents: Int
    }

    var nets: Price?
    var matchFeeCents: Int?

    init(nets: Price? = nil, matchFeeCents: Int? = nil) {
        self.nets = nets
        self.matchFeeCents = matchFeeCents
    }

    var isEmpty: Bool { nets == nil && matchFeeCents == nil }

    /// What the schedule form starts from for this kind of session. Training
    /// has no usual price: plenty of clubs don't charge for it.
    func cost(for kind: ScheduleKind) -> ScheduleCost? {
        switch kind {
        case .nets: return nets.map { ScheduleCost(mode: $0.mode, amountCents: $0.amountCents) }
        case .match: return matchFeeCents.map { ScheduleCost(mode: .perPlayer, amountCents: $0) }
        case .training: return nil
        }
    }
}

/// `PUT /clubs/{id}/payments/settings` with both prices. A null clears one;
/// the switches are left out, so they are left as they are.
struct UsualPricesBody: Encodable {
    let prices: UsualPrices

    enum CodingKeys: String, CodingKey {
        case defaultNets = "default_nets"
        case defaultMatchFeeCents = "default_match_fee_cents"
    }

    private struct Nets: Encodable {
        let mode: String
        let amountCents: Int

        enum CodingKeys: String, CodingKey {
            case mode
            case amountCents = "amount_cents"
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let nets = prices.nets {
            try c.encode(Nets(mode: nets.mode.raw, amountCents: nets.amountCents), forKey: .defaultNets)
        } else {
            try c.encodeNil(forKey: .defaultNets)
        }
        if let fee = prices.matchFeeCents {
            try c.encode(fee, forKey: .defaultMatchFeeCents)
        } else {
            try c.encodeNil(forKey: .defaultMatchFeeCents)
        }
    }
}

/// The usual prices as the form holds them: switches and typed amounts.
struct UsualPricesDraft: Equatable {
    var netsOn: Bool
    var netsMode: CostMode
    var netsAmount: String
    var matchOn: Bool
    var matchAmount: String

    init(_ prices: UsualPrices, currency: String) {
        netsOn = prices.nets != nil
        netsMode = prices.nets.map { $0.mode == .perPlayer ? .perPlayer : .splitTotal } ?? .splitTotal
        netsAmount = prices.nets.map { Money.plain($0.amountCents, currency) } ?? ""
        matchOn = prices.matchFeeCents != nil
        matchAmount = prices.matchFeeCents.map { Money.plain($0, currency) } ?? ""
    }

    /// What to save, or nil while a price that is switched on has no usable
    /// amount. A price switched off is cleared.
    func prices(currency: String) -> UsualPrices? {
        var out = UsualPrices()
        if netsOn {
            guard let cents = Money.parse(netsAmount, currency: currency), cents > 0 else { return nil }
            out.nets = UsualPrices.Price(mode: netsMode, amountCents: cents)
        }
        if matchOn {
            guard let cents = Money.parse(matchAmount, currency: currency), cents > 0 else { return nil }
            out.matchFeeCents = cents
        }
        return out
    }
}

extension MoneyOverview {
    /// A club that has set nothing up: no bank details and no usual prices.
    /// The money admin is offered the setup wizard.
    var needsSetup: Bool {
        account.canManage && account.isEmpty && settings.usualPrices.isEmpty
    }
}

// MARK: - Who the money goes to

/// The words for who a player pays, shared by the pay screen and the
/// wizard's preview of it.
enum Payee {
    /// "Aman", from "Aman Gill". A club account keeps its whole name.
    static func shortName(_ holder: String, isPersonal: Bool) -> String {
        guard isPersonal, let first = holder.split(separator: " ").first else { return holder }
        return String(first)
    }

    /// "Pay Aman Gill, the club secretary." — the person and their role, so
    /// a player knows who the money is going to.
    static func sentence(_ holder: String, role: String?) -> String {
        let vars = ["name": holder]
        switch role {
        case "secretary": return tr("Pay {name}, the club secretary.", vars: vars)
        case "treasurer": return tr("Pay {name}, the club treasurer.", vars: vars)
        case "owner": return tr("Pay {name}, who runs the club.", vars: vars)
        default: return tr("Pay {name}.", vars: vars)
        }
    }

    /// Said under the payee when the money goes into somebody's own account.
    static func ownAccountSentence(_ holder: String, isPersonal: Bool) -> String? {
        guard isPersonal else { return nil }
        return tr("This is {name}'s own bank account. The club uses it to collect money.",
                  vars: ["name": shortName(holder, isPersonal: true)])
    }
}

extension BankDetails {
    var payeeShortName: String { Payee.shortName(holderName, isPersonal: isPersonal) }
    var payeeSentence: String { Payee.sentence(holderName, role: payeeRole) }
    var ownAccountSentence: String? { Payee.ownAccountSentence(holderName, isPersonal: isPersonal) }
}

/// "First time? Here's how" until somebody has said they paid this club by
/// transfer on this phone; "Pay Aman as usual" after that.
enum PayGuide {
    private static func key(_ clubId: UUID) -> String { "fishers:paid-by-transfer:\(clubId.uuidString)" }

    static func hasPaidBefore(clubId: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key(clubId))
    }

    static func rememberPaid(clubId: UUID, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(clubId))
    }
}

// MARK: - A screenshot of the payment

/// What the server takes: JPEG, PNG or WebP, at most 1 MB. Photos come off
/// an iPhone as HEIC and several megabytes, so every picture is redrawn here
/// as a JPEG, no more than 1600 px on its longest side. Redrawing also drops
/// the photo's metadata, its location included.
enum PaymentScreenshot {
    static let maxPixels: CGFloat = 1600
    static let maxBytes = 1_000_000

    /// Nil when the bytes are not a picture.
    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image)
    }

    static func jpeg(from image: UIImage) -> Data? {
        var side = maxPixels
        // Quality first, as the plan asks (0.7); then less of it; then fewer
        // pixels. A screenshot of a banking app is nowhere near any of these.
        while side >= 400 {
            let drawn = redraw(image, longestSide: side)
            for quality in [0.7, 0.55, 0.4] {
                if let out = drawn.jpegData(compressionQuality: quality), out.count <= maxBytes {
                    return out
                }
            }
            side *= 0.75
        }
        return nil
    }

    /// Upright, opaque, at one pixel per point, and no bigger than `longestSide`.
    static func redraw(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixels.width, pixels.height, 1)
        let factor = min(1, longestSide / longest)
        let target = CGSize(
            width: max(1, (pixels.width * factor).rounded(.down)),
            height: max(1, (pixels.height * factor).rounded(.down))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

// MARK: - Signing in with WhatsApp

/// `GET /auth/whatsapp`. Off until the WhatsApp Business account is.
struct WhatsAppSignInConfig: Decodable {
    let enabled: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
    }

    enum CodingKeys: String, CodingKey { case enabled }
}

/// `POST /auth/whatsapp/start`: the same answer whether or not the number
/// has an account, so it never says which.
struct WhatsAppCodeSent: Decodable {
    let expiresIn: Int
    /// Seconds before another code can be asked for.
    let resendAfter: Int

    enum CodingKeys: String, CodingKey {
        case expiresIn = "expires_in"
        case resendAfter = "resend_after"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        expiresIn = (try? c.decodeIfPresent(Int.self, forKey: .expiresIn)) ?? 600
        resendAfter = (try? c.decodeIfPresent(Int.self, forKey: .resendAfter)) ?? 60
    }
}
