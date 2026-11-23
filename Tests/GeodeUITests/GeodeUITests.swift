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

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-GeodeUITesting"] + extra
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

    // MARK: iPad の回転
    // グリッドと背景は端末に対して動かさず、アイコンだけが持った向きに回る。上のボタンは持った向きの上の角へ移る。
    // iPad のシミュレータでは tools/test.sh が画面を録画する（build/ui-ipad.mp4）。回す直前に時刻を出力するので、録画と照らし合わせる

    private func padOnly(_ app: XCUIApplication) throws {
        guard app.windows.firstMatch.waitForExistence(timeout: 10),
              UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad でだけ確認する（iPhone は縦のみ）")
        }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
    }

    /// 回転を始める時刻を出力する（録画と照らし合わせるため）
    private func rotate(to orientation: UIDeviceOrientation, _ label: String) {
        print("GEODE-ROTATE \(label) \(ISO8601DateFormatter().string(from: Date())) \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = orientation
    }

    /// ウィンドウが横長になるまで待つ
    private func waitForLandscapeWindow(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        let landscape = expectation(for: NSPredicate { _, _ in window.frame.width > window.frame.height },
                                    evaluatedWith: nil)
        wait(for: [landscape], timeout: 5)
        sleep(1)
    }

    /// 端末を横（ホームボタン側を右）にしても、キャンバスの左上の角は画面上の同じ場所（横持ちで見て左下）に残る。
    /// 上の「設定」ボタンは持った向きの左上へ移り、押せる
    func testPadGridStaysFixedWhenRotated() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(["-GeodeSampleBoard"])
        try padOnly(app)
        let origin = app.otherElements["geode-canvas-origin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertLessThan(origin.frame.midX, 20)
        XCTAssertLessThan(origin.frame.midY, 20)
        let alphaBefore = app.staticTexts["Alpha"].frame
        print("縦: Alpha \(alphaBefore)")
        capture(app, "06-pad-portrait")

        sleep(2)
        rotate(to: .landscapeLeft, "fixed")
        waitForLandscapeWindow(app)
        capture(app, "07-pad-landscape")

        let window = app.windows.firstMatch.frame
        print("横: ウィンドウ \(window.size)、キャンバスの角 \(origin.frame)、設定ボタン \(app.buttons["設定"].frame)")
        XCTAssertLessThan(origin.frame.midX, 20, "キャンバスの角は横持ちで見て左下に残る")
        XCTAssertGreaterThan(origin.frame.midY, window.height - 20, "キャンバスの角は横持ちで見て左下に残る")

        // 見本の盤面: 縦は 0〜2 番のマス、横は 15〜17 番のマスにアイコンがある（横は縦と別の並び）
        let alpha = app.staticTexts["Alpha"]
        XCTAssertTrue(alpha.exists)
        print("横: Alpha \(alpha.frame)")

        let gear = app.buttons["設定"]
        XCTAssertLessThan(gear.frame.midX, 120, "設定ボタンは持った向きの左上")
        XCTAssertLessThan(gear.frame.midY, 120, "設定ボタンは持った向きの左上")
        gear.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5), "回した後もボタンを押せる")
        app.navigationBars["設定"].buttons["完了"].tap()
    }

    /// 横に持ったまま起動しても、縦から回したときと同じ置き方になる（起動時の向きの読み違いがない）
    func testPadLaunchInLandscapeMatchesRotation() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch()
        try padOnly(app)
        let origin = app.otherElements["geode-canvas-origin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 10))
        waitForLandscapeWindow(app)
        capture(app, "08-pad-launch-landscape")
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(origin.frame.midX, 20)
        XCTAssertGreaterThan(origin.frame.midY, window.height - 20)
    }

    /// 試験中の方式（-GeodeNoRotationAnimation: iOS の回転のアニメーションも止める）。録画で見比べる。キャンバスの角の位置だけ確かめる
    func testPadRotationWithoutSystemAnimation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(["-GeodeSampleBoard", "-GeodeNoRotationAnimation"])
        try padOnly(app)
        let origin = app.otherElements["geode-canvas-origin"]
        XCTAssertTrue(origin.waitForExistence(timeout: 10))
        sleep(2)
        rotate(to: .landscapeLeft, "noanimation")
        waitForLandscapeWindow(app)
        XCTAssertGreaterThan(origin.frame.midY, app.windows.firstMatch.frame.height - 20)
    }

    /// 比較用: 以前と同じ iOS の回転のまま（-GeodeSystemRotation）。録画で四隅が黒く見えるかを見比べる。判定はしない
    func testPadSystemRotationBaseline() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(["-GeodeSampleBoard", "-GeodeSystemRotation"])
        try padOnly(app)
        sleep(2)
        rotate(to: .landscapeLeft, "system")
        waitForLandscapeWindow(app)
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
