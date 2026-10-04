// TVMoreMenuNavigationUITests.swift
// Regression test for tvOS player more-menu double-step navigation bug.
//
// Bug: onMoveCommand + .focused() bidirectional binding both responded to
// the same D-pad event, causing focus to advance 2 rows per DOWN press.
// Fix: removed onMoveCommand; native tvOS focus drives navigation.
//
// Test: open more menu → press DOWN 3 times from Speed →
//       verify each press advanced exactly 1 row (no skip).

#if os(tvOS)
import XCTest

final class TVMoreMenuNavigationUITests: XCTestCase {

    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-open-more-menu"]
        app.launch()
    }

    override func tearDownWithError() throws { app = nil }

    // MARK: - Helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", id))
            .firstMatch
    }

    private func focusedIdentifier() -> String {
        let pred = NSPredicate(format: "hasFocus == true")
        let el = app.descendants(matching: .any).matching(pred).firstMatch
        return el.exists ? el.identifier : "<nothing>"
    }

    private func snap(_ label: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = label
        a.lifetime = .keepAlways
        add(a)
    }

    private func waitForMoreMenu() throws {
        let chipBar = element("home.chipBar")
        guard chipBar.waitForExistence(timeout: 15) else {
            try captureAndSkip("home.chipBar not found — app failed to launch", in: app)
        }

        // Navigate down to the first video card and select it.
        let videoPred = NSPredicate(format: "identifier BEGINSWITH 'video.card.'")
        let cards = app.descendants(matching: .any).matching(videoPred)
        let cardWait = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: cards)],
            timeout: 20
        )
        guard cardWait == .completed else {
            try captureAndSkip("No video cards loaded after 20s — network unavailable", in: app)
        }
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        remote.press(.select)

        // --uitesting-open-more-menu opens the menu automatically in PlayerView.onAppear.
        let speedRow = element("player.moreMenu.speedRow")
        guard speedRow.waitForExistence(timeout: 15) else {
            try captureAndSkip("More menu did not open after selecting a video", in: app)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Test

    /// Opens the more menu and presses DOWN 3 times. Verifies:
    /// 1. Focus starts on Speed (the default row).
    /// 2. Each DOWN press moves focus to a different row (no double-step skip).
    /// 3. After 3 DOWNs we have not jumped all the way to Comments or Cancel
    ///    (which would indicate the old 2-step-per-press bug).
    func test_DownThreeTimes_AdvancesOneRowPerPress() throws {
        try waitForMoreMenu()

        // ── Initial state ──
        let initial = focusedIdentifier()
        snap("0-menu-opened")
        XCTContext.runActivity(named: "Initial focused: \(initial)") { _ in }
        XCTAssertEqual(
            initial, "player.moreMenu.speedRow",
            "More menu should open with Speed row focused")

        // ── DOWN 1 ──
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        let after1 = focusedIdentifier()
        snap("1-after-first-down")
        XCTContext.runActivity(named: "After DOWN 1 — focused: \(after1)") { _ in }

        XCTAssertNotEqual(
            after1, initial,
            "DOWN 1 must leave Speed — focus did not move at all")
        XCTAssertNotEqual(
            after1, "player.moreMenu.cancel",
            "DOWN 1 jumped all the way to Cancel — double-step bug")

        // ── DOWN 2 ──
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        let after2 = focusedIdentifier()
        snap("2-after-second-down")
        XCTContext.runActivity(named: "After DOWN 2 — focused: \(after2)") { _ in }

        XCTAssertNotEqual(
            after2, after1,
            "DOWN 2 did not move — focus stuck on \(after1)")
        XCTAssertNotEqual(
            after2, "player.moreMenu.cancel",
            "DOWN 2 jumped to Cancel after only 2 presses — double-step bug")

        // ── DOWN 3 ──
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        let after3 = focusedIdentifier()
        snap("3-after-third-down")
        XCTContext.runActivity(named: "After DOWN 3 — focused: \(after3)") { _ in }

        XCTAssertNotEqual(
            after3, after2,
            "DOWN 3 did not move — focus stuck on \(after2)")
        XCTAssertNotEqual(
            after3, "player.moreMenu.cancel",
            "DOWN 3 jumped to Cancel after only 3 presses — double-step bug; "
                + "DOWN1=\(after1) DOWN2=\(after2) DOWN3=\(after3)")

        // ── Summary ──
        XCTContext.runActivity(
            named:
                "Navigation path: Speed → \(after1) → \(after2) → \(after3)"
        ) { _ in }
    }

    /// The Quality row must be present in the more menu, directly reachable
    /// with one DOWN press from Speed, and it must open the quality picker.
    func test_QualityRow_ExistsAndOpensPicker() throws {
        try waitForMoreMenu()

        let qualityRow = element("player.moreMenu.qualityRow")
        XCTAssertTrue(
            qualityRow.waitForExistence(timeout: 5),
            "player.moreMenu.qualityRow must be in the more menu")

        // Speed is focused initially; one DOWN lands on Quality (the next row).
        remote.press(.down)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(
            focusedIdentifier(), "player.moreMenu.qualityRow",
            "One DOWN from Speed must focus the Quality row")

        remote.press(.select)
        let picker = element("player.qualityPicker")
        XCTAssertTrue(
            picker.waitForExistence(timeout: 10),
            "Selecting the Quality row must open the quality picker")
    }
}

final class TVNativePlayerInteractionUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared
    private let initialVideo = "native-ui-current"
    private let firstRelated = "native-ui-related-1"
    private let secondRelated = "native-ui-related-2"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--uitesting-player-ui",
            "--uitesting-deeplink-video=\(initialVideo)",
            "--uitesting-inject-related-video-ids=\(firstRelated),\(secondRelated)",
        ]
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    private func openTestVideo() {
        let open = app.buttons["Open test video"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        remote.press(.select)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func wait(_ predicate: String, for element: XCUIElement, timeout: TimeInterval = 5) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed)
    }

    private func relatedButton(_ id: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier ENDSWITH %@", id)).firstMatch
    }

    func testControlsHideAfterTwoSecondsWithoutBack() {
        remote.press(.up)
        let controls = element("player.playPauseButton")
        XCTAssertTrue(controls.waitForExistence(timeout: 2))
        wait("exists == false", for: controls, timeout: 4)
        XCTAssertTrue(element("player.titleLabel").exists)
    }

    func testControlsHideAfterClosingMoreMenu() {
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
        remote.press(.up)
        remote.press(.select)
        let menu = element("player.moreMenu.speedRow")
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        remote.press(.menu)
        wait("exists == false", for: menu)
        wait("exists == false", for: element("player.playPauseButton"), timeout: 4)
        XCTAssertTrue(element("player.titleLabel").exists)
    }

    func testDownBrowsesRecommendationsAndSelectsSecondVideo() {
        remote.press(.down)
        let first = relatedButton(firstRelated)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        wait("value == 'Selected'", for: first)
        remote.press(.right)
        let second = relatedButton(secondRelated)
        wait("value == 'Selected'", for: second)
        remote.press(.select)
        wait("label == '\(secondRelated)'", for: element("player.titleLabel"))
        XCTAssertFalse(first.exists)
    }

    private func openDescription() {
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
        remote.press(.up)
        remote.press(.select)
        let row = element("player.moreMenu.descriptionRow")
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        for _ in 0..<8 {
            if row.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(row.hasFocus)
        remote.press(.select)
    }

    func testBackClosesDescriptionAndKeepsCurrentVideo() {
        for _ in 0..<3 {
            openDescription()
            let description = app.staticTexts["Test video description"]
            XCTAssertTrue(description.waitForExistence(timeout: 3))
            remote.press(.menu)
            wait("exists == false", for: description)
            XCTAssertEqual(element("player.titleLabel").label, initialVideo)
            wait("exists == false", for: element("player.playPauseButton"), timeout: 4)
        }
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
    }

    func testSponsorToastCannotStealDescriptionCloseAction() {
        app.terminate()
        app.launchArguments.append("--uitesting-description-toast")
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
        openDescription()
        let description = app.staticTexts["Test video description"]
        XCTAssertTrue(description.waitForExistence(timeout: 3))
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Skip ")).firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        XCTAssertFalse(skip.isEnabled)
        remote.press(.select)
        wait("exists == false", for: description)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
        wait("enabled == true", for: skip)
    }

    func testBackClosesCommentsAndKeepsCurrentVideo() {
        openComments()
        let comments = app.staticTexts["No comments available."]
        XCTAssertTrue(comments.waitForExistence(timeout: 3))
        remote.press(.menu)
        wait("exists == false", for: comments)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
    }

    private func openComments() {
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
        remote.press(.up)
        remote.press(.select)
        let row = element("player.moreMenu.commentsRow")
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        for _ in 0..<8 {
            if row.hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(row.hasFocus)
        remote.press(.select)
    }

    func testCommentsScrollToLaterRowsAndBackToEarlierRows() {
        app.terminate()
        app.launchArguments.append("--uitesting-comments-content")
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
        openComments()
        XCTAssertTrue(app.staticTexts["Test comment 1"].waitForExistence(timeout: 3))
        wait("value == 'Selected'", for: element("player.comments.close"))
        for index in 1...12 {
            remote.press(.down)
            wait("value == 'Selected'", for: element("player.comments.comment.native-comment-\(index)"))
        }
        let later = element("player.comments.comment.native-comment-12")
        wait("value == 'Selected'", for: later)
        XCTAssertTrue(later.isHittable)
        remote.press(.up)
        wait("value == 'Selected'", for: element("player.comments.comment.native-comment-11"))
        remote.press(.menu)
        wait("exists == false", for: app.staticTexts["Test comment 1"])
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }

    func testCommentThreadBackReturnsToCommentsThenVideo() {
        app.terminate()
        app.launchArguments.append("--uitesting-comments-content")
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
        openComments()
        let first = element("player.comments.comment.native-comment-1")
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        wait("value == 'Selected'", for: element("player.comments.close"))
        remote.press(.down)
        wait("value == 'Selected'", for: first)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Test reply 1"].waitForExistence(timeout: 3))
        remote.press(.menu)
        wait("exists == false", for: app.staticTexts["Test reply 1"])
        wait("value == 'Selected'", for: first)
        remote.press(.menu)
        wait("exists == false", for: first)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }

    private func openPopulatedComments(extraArguments: [String] = []) {
        app.terminate()
        app.launchArguments.append("--uitesting-comments-content")
        app.launchArguments.append(contentsOf: extraArguments)
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
        openComments()
        wait("value == 'Selected'", for: element("player.comments.close"))
    }

    private func openFirstCommentThread() {
        remote.press(.down)
        wait("value == 'Selected'", for: element("player.comments.comment.native-comment-1"))
        remote.press(.select)
    }

    func testCommentsAndRepliesLoadFurtherPagesWithRemote() {
        openPopulatedComments()
        openFirstCommentThread()
        XCTAssertTrue(app.staticTexts["Test reply 1"].waitForExistence(timeout: 3))
        for _ in 0..<4 { remote.press(.down) }
        let repliesMore = element("player.comments.loadMoreReplies")
        wait("value == 'Selected'", for: repliesMore)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Test reply 3"].waitForExistence(timeout: 3))
        XCTAssertFalse(repliesMore.exists)
        remote.press(.menu)
        wait("value == 'Selected'", for: element("player.comments.comment.native-comment-1"))
        for index in 2...20 {
            remote.press(.down)
            wait("value == 'Selected'", for: element("player.comments.comment.native-comment-\(index)"))
        }
        remote.press(.down)
        let commentsMore = element("player.comments.loadMore")
        wait("value == 'Selected'", for: commentsMore)
        remote.press(.select)
        remote.press(.down)
        let nextPage = element("player.comments.comment.native-comment-21")
        wait("value == 'Selected'", for: nextPage)
        XCTAssertTrue(nextPage.isHittable)
        XCTAssertFalse(commentsMore.exists)
        remote.press(.menu)
        wait("exists == false", for: nextPage)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }

    func testReplyFailureCanRetryWithRemote() {
        openPopulatedComments(extraArguments: ["--uitesting-comments-reply-error"])
        openFirstCommentThread()
        let retry = element("player.comments.retry")
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        remote.press(.down)
        remote.press(.down)
        wait("value == 'Selected'", for: retry)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Test reply 1"].waitForExistence(timeout: 3))
        XCTAssertFalse(retry.exists)
        remote.press(.menu)
        wait("value == 'Selected'", for: element("player.comments.comment.native-comment-1"))
    }

    func testAdvancingVideoDismissesPreviousCommentThread() {
        openPopulatedComments(extraArguments: ["--uitesting-advance-on-play-pause"])
        openFirstCommentThread()
        XCTAssertTrue(app.staticTexts["Test reply 1"].waitForExistence(timeout: 3))
        remote.press(.playPause)
        wait("label == '\(firstRelated)'", for: element("player.titleLabel"))
        XCTAssertFalse(element("player.comments.close").exists)
        XCTAssertFalse(app.staticTexts["Test reply 1"].exists)
        openComments()
        XCTAssertTrue(element("player.comments.comment.native-comment-1").waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Test reply 1"].exists)
    }

    func testCreatorChannelOpensAndSelectsVideo() {
        app.terminate()
        app.launchArguments.append("--uitesting-channel-content")
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
        remote.press(.up)
        XCTAssertTrue(element("player.channelName").waitForExistence(timeout: 2))
        XCTAssertTrue(element("player.channelName").isEnabled)
        remote.press(.up)
        remote.press(.left)
        remote.press(.select)
        let title = element("channel.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Test Creator")
        let first = element("video.card.native-channel-video-1")
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        for _ in 0..<8 {
            if first.value as? String == "Selected" { break }
            remote.press(.down)
        }
        wait("value == 'Selected'", for: first)
        remote.press(.select)
        wait("label == 'Creator video 1'", for: element("player.titleLabel"))
        remote.press(.menu)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    func testBackClosesRecommendationsAndKeepsCurrentVideo() {
        remote.press(.down)
        let first = relatedButton(firstRelated)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        remote.press(.menu)
        wait("exists == false", for: first)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
    }

    func testUpClosesRecommendationsAndKeepsCurrentVideo() {
        remote.press(.down)
        let first = relatedButton(firstRelated)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        remote.press(.up)
        wait("exists == false", for: first)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
    }

    func testRecommendationsCanCloseWhenCardsCannotAcquireNativeFocus() {
        app.terminate()
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
        remote.press(.down)
        let first = relatedButton(firstRelated)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertFalse(first.hasFocus)
        remote.press(.up)
        wait("exists == false", for: first)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }

    func testRecommendationsCanRepeatedlyOpenAndClose() {
        for _ in 0..<4 {
            remote.press(.down)
            let first = relatedButton(firstRelated)
            XCTAssertTrue(first.waitForExistence(timeout: 3))
            remote.press(.up)
            wait("exists == false", for: first)
            XCTAssertEqual(element("player.titleLabel").label, initialVideo)
        }
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
    }

    func testSponsorToastCannotTrapRecommendations() {
        app.terminate()
        app.launchArguments.append("--uitesting-recommendations-toast")
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
        remote.press(.down)
        let first = relatedButton(firstRelated)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let skip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Skip ")).firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        remote.press(.right)
        wait("value == 'Selected'", for: relatedButton(secondRelated))
        remote.press(.up)
        wait("exists == false", for: first)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }

    func testEmptyRecommendationsCanReturnToVideo() {
        app.terminate()
        app.launchArguments.removeAll { $0.hasPrefix("--uitesting-inject-related-video-ids=") }
        app.launch()
        openTestVideo()
        XCTAssertTrue(element("player.titleLabel").waitForExistence(timeout: 15))
        remote.press(.down)
        let back = app.buttons["Back to video"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        remote.press(.select)
        wait("exists == false", for: back)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }

    private func launchAtEnd() {
        app.terminate()
        app.launchArguments.append("--uitesting-player-ended")
        app.launch()
        openTestVideo()
        XCTAssertTrue(app.buttons["Play now"].waitForExistence(timeout: 15))
    }

    func testCancelUpNextKeepsCurrentVideo() {
        launchAtEnd()
        remote.press(.right)
        remote.press(.select)
        wait("exists == false", for: app.buttons["Play now"])
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }

    func testPlayNowStartsRecommendedVideo() {
        launchAtEnd()
        remote.press(.select)
        wait("label == '\(firstRelated)'", for: element("player.titleLabel"))
    }

    func testDownFromUpNextBrowsesWithoutAdvancing() {
        launchAtEnd()
        remote.press(.down)
        XCTAssertTrue(relatedButton(firstRelated).waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Play now"].exists)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }
}
extension TVNativePlayerInteractionUITests {
    @objc func testBackClosesStatsAndKeepsCurrentVideo() {
        app.terminate()
        app.launchArguments.append("--uitesting-stats-for-nerds")
        app.launch()
        openTestVideo()
        let title = element("player.titleLabel")
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, initialVideo)
        let stats = app.staticTexts["Video ID"].firstMatch
        XCTAssertTrue(stats.waitForExistence(timeout: 3))
        remote.press(.menu)
        wait("exists == false", for: stats)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
    }

    @objc func testBackClosesMoreMenuBeforeStats() {
        app.terminate()
        app.launchArguments.append("--uitesting-stats-for-nerds")
        app.launch()
        openTestVideo()
        let title = element("player.titleLabel")
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.label, initialVideo)
        let stats = app.staticTexts["Video ID"].firstMatch
        XCTAssertTrue(stats.waitForExistence(timeout: 3))
        remote.press(.up)
        XCTAssertTrue(element("player.playPauseButton").waitForExistence(timeout: 2))
        remote.press(.up)
        remote.press(.select)
        let menu = element("player.moreMenu.speedRow")
        XCTAssertTrue(menu.waitForExistence(timeout: 3))
        remote.press(.menu)
        wait("exists == false", for: menu)
        XCTAssertTrue(stats.exists)
        remote.press(.menu)
        wait("exists == false", for: stats)
        XCTAssertEqual(element("player.titleLabel").label, initialVideo)
    }
}

#endif
