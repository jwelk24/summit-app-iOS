import XCTest

/// First-run onboarding: the welcome cover's skip and complete paths, and
/// that the choice sticks across a relaunch.
///
/// `--uitest-reset-onboarding` (handled in RootView.onAppear) clears the
/// onboarding flags and bypasses the existing-user skip, so the welcome
/// flow appears deterministically no matter what data the simulator holds.
final class OnboardingUITests: XCTestCase {

    /// The very first launch on a cold simulator can take 30s+ (install,
    /// debugserver attach, store seeding) before the UI settles.
    private let launchTimeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchWithFreshOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset-onboarding"]
        app.launch()
        return app
    }

    /// `waitForExistence` is true for off-screen pages of a paged TabView;
    /// hittability is what distinguishes the currently visible page.
    @MainActor
    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let hittable = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func testSkipDismissesWelcomeAndStaysDismissed() throws {
        let app = launchWithFreshOnboarding()

        let skip = app.buttons["onboardingSkipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: launchTimeout), "Welcome flow should appear on a fresh install")
        skip.tap()

        // The cover is gone and the Budget tab's checklist is showing.
        let checklist = app.descendants(matching: .any)["gettingStartedHeader"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 10), "Getting Started checklist should show after skipping")
        XCTAssertFalse(app.buttons["onboardingContinueButton"].exists)

        // Relaunch without the reset flag: the welcome must not come back.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(checklist.waitForExistence(timeout: launchTimeout), "Checklist should persist across relaunch")
        XCTAssertFalse(app.buttons["onboardingSkipButton"].exists, "Welcome flow should not reappear once skipped")
    }

    @MainActor
    func testCompletingWelcomeLandsOnBudgetWithChecklist() throws {
        let app = launchWithFreshOnboarding()

        let continueButton = app.buttons["onboardingContinueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: launchTimeout), "Welcome flow should appear on a fresh install")

        continueButton.tap() // → starter budget page

        // Paged TabViews drop selection writes that land mid-animation, so
        // wait for each page to settle before tapping Continue again.
        XCTAssertTrue(waitForHittable(app.staticTexts["Your Starter Budget"], timeout: 10),
                      "Starter budget page should follow the first Continue")
        Thread.sleep(forTimeInterval: 0.5)
        continueButton.tap() // → bring-in-money page

        // Last page: the bank shortcut appears and the primary button finishes.
        XCTAssertTrue(app.buttons["onboardingConnectBankButton"].waitForExistence(timeout: 10),
                      "Connect a Bank should be offered on the last page")
        // Its insertion shifts the bottom buttons; let layout settle before the final tap.
        Thread.sleep(forTimeInterval: 0.5)
        continueButton.tap() // "Start Budgeting"

        let checklist = app.descendants(matching: .any)["gettingStartedHeader"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 10), "Getting Started checklist should show after finishing")
        XCTAssertFalse(continueButton.exists)
    }
}
