import XCTest

/// 主要な操作の確認と、画面の撮影（結果の .xcresult に添付される）。
/// 実機の設定を書き換えないよう、シミュレータでだけ実行する。盤面は一時フォルダを使う（-GeodeUITesting）
final class GeodeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("UI テストはシミュレータでのみ実行します（実機の設定を書き換えないため）")
        #endif
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-GeodeUITesting"]
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHomeShowsTopButtons() {
        let app = launch()
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["編集"].exists)
        capture(app, "01-home")
    }

    func testOpenAndCloseSettings() {
        let app = launch()
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        capture(app, "02-settings")
        app.navigationBars["設定"].buttons["完了"].tap()
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 5))
    }

    func testEnterAndLeaveEditMode() {
        let app = launch()
        app.buttons["編集"].tap()
        XCTAssertTrue(app.buttons["編集を完了"].waitForExistence(timeout: 5))
        capture(app, "03-edit")
        app.buttons["編集を完了"].tap()
        XCTAssertTrue(app.buttons["編集"].waitForExistence(timeout: 5))
    }

    /// 起動時間の計測。時間がかかるので、環境変数 GEODE_PERF=1 のときだけ実行する
    /// （xcodebuild では TEST_RUNNER_GEODE_PERF=1 を付ける）
    func testLaunchPerformance() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GEODE_PERF"] == "1", "GEODE_PERF=1 のときだけ計測")
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["-GeodeUITesting"]
            app.launch()
        }
    }
}
