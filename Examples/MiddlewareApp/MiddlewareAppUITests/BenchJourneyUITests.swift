//
//  BenchJourneyUITests.swift
//  MiddlewareAppUITests
//
//  Scripted Coffee Cart user journey used by rum-benchmarks (runners/apps/ios.mjs)
//  to benchmark the real app with the SDK in different modes. Configuration is
//  passed by the harness via TEST_RUNNER_-prefixed environment variables:
//    MW_BENCH_MODE  ""(default: v3 recording on) | "recording_off" | "no_sdk"
//    MW_TARGET      collector URL, e.g. http://localhost:43180
//    MW_TOKEN       access token (any value for the mock collector)
//    MW_BENCH_LOOPS journey repetitions (default 3)
//    MW_BENCH_IDLE_S trailing idle seconds so recorder batches flush (default 12)
//

import XCTest

final class BenchJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testCoffeeCartJourney() throws {
        let env = ProcessInfo.processInfo.environment
        let loops = Int(env["MW_BENCH_LOOPS"] ?? "") ?? 3
        let idleSeconds = Int(env["MW_BENCH_IDLE_S"] ?? "") ?? 12

        let app = XCUIApplication()
        for key in ["MW_BENCH_MODE", "MW_TARGET", "MW_TOKEN"] {
            if let value = env[key] {
                app.launchEnvironment[key] = value
            }
        }

        let launchStart = Date()
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)
        let launchMs = Date().timeIntervalSince(launchStart) * 1000
        // Parsed by the harness from the xcodebuild log.
        print(String(format: "MW_BENCH launch_ms=%.0f pid=%d", launchMs, app.processID))

        login(app)

        for _ in 0..<loops {
            browseMenu(app)
            openProductAndAddToCart(app)
            checkout(app)
            backToMenu(app)
        }

        // Trailing idle so the session recorder captures a stable screen and
        // pending exporter batches flush to the collector.
        Thread.sleep(forTimeInterval: TimeInterval(idleSeconds))
        print("MW_BENCH journey_done loops=\(loops)")
    }

    // MARK: - Steps (all best-effort: a missed element must not abort the bench)

    private func login(_ app: XCUIApplication) {
        let username = app.textFields["Enter your username"]
        guard username.waitForExistence(timeout: 10) else { return }
        username.tap()
        username.typeText("bench-user")
        let cont = app.buttons["Continue"]
        if cont.waitForExistence(timeout: 5) { cont.tap() }
        _ = app.tabBars.buttons["Menu"].waitForExistence(timeout: 10)
    }

    private func browseMenu(_ app: XCUIApplication) {
        tapIfPresent(app.tabBars.buttons["Menu"])
        // Scroll load: exercises frame capture + scroll jank measurement.
        app.swipeUp()
        app.swipeUp()
        app.swipeDown()
        app.swipeDown()
    }

    private func openProductAndAddToCart(_ app: XCUIApplication) {
        let cell = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] '$'")
        ).firstMatch
        let target = cell.exists ? cell : app.cells.firstMatch
        guard target.waitForExistence(timeout: 5) else { return }
        target.tap()

        let addToCart = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Add to Cart'")
        ).firstMatch
        if addToCart.waitForExistence(timeout: 5) { addToCart.tap() }
    }

    private func checkout(_ app: XCUIApplication) {
        tapIfPresent(app.tabBars.buttons["Cart"])
        let proceed = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Proceed to Checkout'")
        ).firstMatch
        let proceedAny = proceed.exists
            ? proceed
            : app.staticTexts["Proceed to Checkout"]
        guard proceedAny.waitForExistence(timeout: 5) else { return }
        proceedAny.tap()

        // Fill whatever text fields the checkout form exposes; payment fields
        // are .sensitive() so this also exercises v3 masking.
        let values = ["Bench User", "1 Espresso Way", "4111111111111111", "12/29", "123"]
        let fields = app.textFields.allElementsBoundByIndex
        for (i, field) in fields.prefix(values.count).enumerated() {
            guard field.exists && field.isHittable else { continue }
            field.tap()
            field.typeText(values[i])
        }
        dismissKeyboard(app)

        let place = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Place Order'")
        ).firstMatch
        if place.waitForExistence(timeout: 5) && place.isEnabled {
            place.tap()
            _ = app.staticTexts["Order Confirmed!"].waitForExistence(timeout: 10)
        }
    }

    private func backToMenu(_ app: XCUIApplication) {
        tapIfPresent(app.tabBars.buttons["Menu"])
    }

    private func tapIfPresent(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 5) && element.isHittable {
            element.tap()
        }
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.toolbars.buttons["Done"]
        if done.exists {
            done.tap()
        } else if app.keyboards.count > 0 {
            app.swipeDown()
        }
    }
}
