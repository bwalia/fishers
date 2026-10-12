import XCTest
@testable import Fishers

/// The sign-up form offers one field for two different things, picked by a
/// segmented control. Switching the control used to leave the old value in
/// place — a mobile number under a label saying Email — and let it be sent.
final class AuthFormTests: XCTestCase {
    func testEmailMethodRejectsAMobileNumber() {
        // The exact shape of the bug: typed as a phone, then switched to Email.
        XCTAssertFalse(AuthView.Method.email.accepts("+447700900123"))
        XCTAssertFalse(AuthView.Method.email.accepts("07700900123"))
    }

    func testEmailMethodAcceptsOrdinaryAddresses() {
        for address in [
            "a@b.co", "harry@fishers.cloud", "first.last+tag@sub.example.org",
        ] {
            XCTAssertTrue(AuthView.Method.email.accepts(address), address)
        }
    }

    func testEmailMethodRejectsWhatIsNotAnAddress() {
        for value in ["", "nope", "@b.com", "a@b", "a@.com", "a@b.", "a b@c.com"] {
            XCTAssertFalse(AuthView.Method.email.accepts(value), value)
        }
    }

    func testPhoneMethodAcceptsTheWaysPeopleWriteNumbers() {
        for number in [
            "+447700900123", "07700900123", "+91 98765 43210", "(020) 7946-0018",
        ] {
            XCTAssertTrue(AuthView.Method.phone.accepts(number), number)
        }
    }

    func testPhoneMethodRejectsAnAddressAndTooFewDigits() {
        for value in ["", "harry@fishers.cloud", "12345", "+44 abc 123456"] {
            XCTAssertFalse(AuthView.Method.phone.accepts(value), value)
        }
    }
}
