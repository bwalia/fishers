// Generated from web/src/lib/i18n/ by tools/i18n. Do not edit.
//
// 2652 keys per language. The words themselves are in the JSON tables
// beside this file; only the list of languages needs to be code, because it is
// what the picker iterates and what `Language(rawValue:)` validates.

import Foundation

/// A language the product speaks.
enum Language: String, CaseIterable, Identifiable, Sendable {
    case en
    case pa

    var id: String { rawValue }

    /// The name in its own script, never translated. A picker that offers
    /// "Punjabi" in English is no use to somebody who cannot read English,
    /// which is the whole point of the picker.
    var native: String {
        switch self {
        case .en: return "English"
        case .pa: return "ਪੰਜਾਬੀ"
        }
    }

    /// The language this build falls back to, per key.
    static let fallback: Language = .en
}
