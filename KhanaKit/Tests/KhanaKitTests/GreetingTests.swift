import XCTest
@testable import KhanaKit

/// Port-parity tests for the greeting. Mirrors the webapp's
/// `components/today/Greeting.tsx`.
final class GreetingTests: XCTestCase {

    func testBeforeNoonIsMorning() {
        XCTAssertEqual(greeting(forHour: 0), "Good morning")
        XCTAssertEqual(greeting(forHour: 11), "Good morning")
    }

    func testNoonToFiveIsAfternoon() {
        XCTAssertEqual(greeting(forHour: 12), "Good afternoon")
        XCTAssertEqual(greeting(forHour: 16), "Good afternoon")
    }

    func testFiveOnwardsIsEvening() {
        XCTAssertEqual(greeting(forHour: 17), "Good evening")
        XCTAssertEqual(greeting(forHour: 23), "Good evening")
    }

    func testFirstWordOnlyAFullNameReadsAsAFormLetter() {
        XCTAssertEqual(firstName("Vishwanath Arondekar"), "Vishwanath")
        XCTAssertEqual(firstName("Asha"), "Asha")
    }

    func testNoUsableNameMeansNoName() {
        XCTAssertNil(firstName(nil))
        XCTAssertNil(firstName(""))
        XCTAssertNil(firstName("   "))
    }

    func testExtraWhitespaceDoesNotBecomeTheName() {
        XCTAssertEqual(firstName("  Asha   Patil "), "Asha")
    }
}
