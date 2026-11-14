import XCTest
@testable import Geode

final class HSBColorTests: XCTestCase {
    func testParsesCommaSeparatedCode() {
        let color = HSBColor(rawValue: "210, 80, 95")
        XCTAssertEqual(color, HSBColor(h: 210, s: 80, b: 95))
    }

    func testRejectsIncompleteCode() {
        XCTAssertNil(HSBColor(rawValue: "210, 80"))
        XCTAssertNil(HSBColor(rawValue: ""))
    }

    func testClampsOutOfRangeValues() {
        let color = HSBColor(h: 400, s: -5, b: 120)
        XCTAssertEqual(color.h, 360)
        XCTAssertEqual(color.s, 0)
        XCTAssertEqual(color.b, 100)
    }
}

final class DirectActionTests: XCTestCase {
    private func action(_ id: String) -> DirectAction {
        (DirectAction.switches + DirectAction.others).first { $0.id == id }!
    }

    func testPhoneNumberKeepsOnlyDialableCharacters() {
        XCTAssertEqual(action("call").makeURL("090-1234 5678"), "tel:09012345678")
        XCTAssertNil(action("call").makeURL("abc"))
    }

    func testWebAddressGetsHTTPSWhenSchemeMissing() {
        XCTAssertEqual(action("web").makeURL("example.com"), "https://example.com")
        XCTAssertEqual(action("web").makeURL("http://example.com"), "http://example.com")
    }

    func testCopyTextRoundTripsThroughTheURL() throws {
        let raw = try XCTUnwrap(action("copy").makeURL("こんにちは & さようなら"))
        let url = try XCTUnwrap(URL(string: raw))
        XCTAssertEqual(SystemActions.directKind(url), .copy)
        let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value
        XCTAssertEqual(text, "こんにちは & さようなら")
    }

    func testEmptyInputGivesNoURL() {
        XCTAssertNil(action("copy").makeURL("   "))
        XCTAssertNil(action("route").makeURL(""))
    }

    func testSwitchActionsAreRecognisedFromTheirURL() {
        XCTAssertEqual(SystemActions.directKind("geode://torch"), .torch)
        XCTAssertTrue(DirectKind.torch.isSwitch)
        XCTAssertFalse(DirectKind.musicNext.isSwitch)
    }

    func testWidgetAndShortcutCallbacksAreNotActions() throws {
        XCTAssertFalse(SystemActions.isGeodeActionURL(try XCTUnwrap(URL(string: "geode://run?id=1"))))
        XCTAssertFalse(SystemActions.isGeodeActionURL(try XCTUnwrap(URL(string: "geode://"))))
        XCTAssertFalse(SystemActions.isGeodeActionURL(try XCTUnwrap(URL(string: "geode://shortcut-error"))))
    }

    func testShortcutURLEncodesTheNameAndReturnsToGeode() throws {
        let raw = SystemActions.shortcutURL("Geode Wi-Fi")
        let items = try XCTUnwrap(URLComponents(string: raw)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "Geode Wi-Fi")
        XCTAssertEqual(items.first { $0.name == "x-success" }?.value, "geode://")
    }
}

final class StorageTests: XCTestCase {
    /// UI テストの起動引数が無いときは、本来の保存先を使う（実データの場所を変えていないこと）
    func testUsesTheRealContainerWithoutTheUITestFlag() {
        XCTAssertFalse(SharedStorage.isUITesting)
        XCTAssertEqual(SharedStorage.container, SharedStorage.appContainer)
    }
}
