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

    /// iPad を横にすると、iOS の回転のアニメーション（画面全体が回り四隅が黒く見える）は出さず、
    /// 中身（上のボタンとグリッド）だけが新しい向きへ動く。回転中の画面を連続で撮り、黒い部分が出ないことを確かめる。
    /// 回した後も上のボタンを押せる（当たり判定がずれていない）
    func testPadRotationShowsNoBlackCorners() throws {
        let app = launch()
        let (gear, worst) = try recordRotation(app, name: "06-rotation")
        XCTAssertLessThan(worst, 0.03, "回転中に黒い部分が見えない（一番多いコマで \(Int(worst * 100))%）")

        gear.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5), "回した後もボタンを押せる")
        app.navigationBars["設定"].buttons["完了"].tap()
    }

    /// 向きを固定できなかったとき（iPadOS 17/18 など）の動き: iOS がウィンドウを回すが、回転のアニメーションは止める
    func testPadRotationWithoutLockShowsNoBlackCorners() throws {
        let app = launch(["-GeodeNoOrientationLock"])
        let (_, worst) = try recordRotation(app, name: "08-rotation-nolock")
        XCTAssertLessThan(worst, 0.03, "回転中に黒い部分が見えない（一番多いコマで \(Int(worst * 100))%）")
    }

    /// 比較用: iOS の回転のアニメーションをそのまま出したときの画面を撮る（黒い部分を数えられているかの確認）。
    /// 結果は判定せず、撮った画面の名前に黒い部分の割合を付けて残す
    func testPadSystemRotationBaseline() throws {
        let app = launch(["-GeodeSystemRotation"])
        let (_, worst) = try recordRotation(app, name: "07-system-rotation")
        print("iOS の回転での黒い部分（一番多いコマ）: \(Int(worst * 100))%")
    }

    /// iPad を縦 → 横にし、回転中の画面を撮り続ける。上のボタンと、黒い部分が一番多いコマの割合を返す
    private func recordRotation(_ app: XCUIApplication, name: String) throws -> (XCUIElement, Double) {
        guard app.windows.firstMatch.waitForExistence(timeout: 10),
              UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("iPad でだけ確認する（iPhone は縦のみ）")
        }
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        let gear = app.buttons["設定"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        sleep(1)
        let before = gear.frame
        capture(app, "\(name)-portrait")

        // 回転中の画面を別のスレッドで撮り続ける
        let recorder = ScreenRecorder()
        recorder.start()
        XCUIDevice.shared.orientation = .landscapeLeft
        // ウィンドウの向きを固定できたときはボタンが画面の別の辺へ移り、できなかったときはウィンドウが横になる
        let window = app.windows.firstMatch
        let rotated = expectation(for: NSPredicate { _, _ in
            let now = gear.frame
            let moved = abs(now.midX - before.midX) > 100 || abs(now.midY - before.midY) > 100
            return moved || window.frame.width > window.frame.height
        }, evaluatedWith: nil)
        wait(for: [rotated], timeout: 5)
        sleep(1)
        let frames = recorder.stop()
        capture(app, "\(name)-landscape")
        print("\(name): ウィンドウ \(window.frame.size)、設定ボタン \(before) → \(gear.frame)")

        // 黒い部分の割合（背景は白いので、黒いのは回転で見えた外側）
        var worst = 0.0
        for (i, image) in frames.enumerated() {
            let black = Self.blackFraction(image)
            worst = max(worst, black)
            let attachment = XCTAttachment(image: image)
            attachment.name = String(format: "%@-%02d-black-%.0f%%", name, i, black * 100)
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertGreaterThan(frames.count, 2, "回転中の画面を撮れた")
        return (gear, worst)
    }

    /// 画像のうち、ほぼ黒い画素の割合（小さく縮めて数える）
    private static func blackFraction(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let w = 60, h = 80
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var black = 0
        for i in stride(from: 0, to: pixels.count, by: 4)
        where pixels[i] < 40 && pixels[i + 1] < 40 && pixels[i + 2] < 40 {
            black += 1
        }
        return Double(black) / Double(w * h)
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

/// 回転中の画面を、テストの操作と並行して撮り続ける
private final class ScreenRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [UIImage] = []
    private var running = false
    private let done = DispatchSemaphore(value: 0)

    func start() {
        lock.withLock { running = true }
        DispatchQueue.global(qos: .userInitiated).async {
            let started = Date()
            while self.lock.withLock({ self.running }) && Date().timeIntervalSince(started) < 8 {
                let image = XCUIScreen.main.screenshot().image
                self.lock.withLock { self.images.append(image) }
            }
            self.done.signal()
        }
    }

    func stop() -> [UIImage] {
        lock.withLock { running = false }
        done.wait()
        return lock.withLock { images }
    }
}
