import XCTest
import AppKit
import TGUIKit
import TelegramCore
import Postbox
import TelegramTheme
@testable import ChatUI

final class ChatMusicFetchPresentationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        ChatMediaUIHooks.install(.placeholder)
    }

    func testCoverVisibilityFollowsDownloadAndCancellation() throws {
        let view = ChatMusicContentView(frame: NSMakeRect(0, 0, 200, 40))
        let cover = try XCTUnwrap(view.subviews.compactMap { $0 as? TransformImageView }.first)
        view.fetchStatus = .Remote(progress: 0)
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
        view.fetchStatus = .Fetching(isActive: true, progress: 0.25)
        XCTAssertTrue(cover.isHidden)
        XCTAssertFalse(view.progressView.isHidden)
        guard case let .Fetching(progress, _) = view.progressView.state else {
            return XCTFail("Expected download progress")
        }
        XCTAssertEqual(progress, 0.25)
        XCTAssertEqual(view.progressView.theme.backgroundColor, ChatMediaPresentation.Empty.activityBackground)
        XCTAssertEqual(view.progressView.theme.foregroundColor, ChatMediaPresentation.Empty.activityForeground)
        view.fetchStatus = .Paused(progress: 0.25)
        XCTAssertTrue(cover.isHidden)
        XCTAssertFalse(view.progressView.isHidden)
        view.fetchStatus = .Remote(progress: 0)
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
    }

    func testCompletionAndReuseRestoreCover() throws {
        let view = ChatMusicContentView(frame: NSMakeRect(0, 0, 200, 40))
        let cover = try XCTUnwrap(view.subviews.compactMap { $0 as? TransformImageView }.first)
        view.fetchStatus = .Fetching(isActive: true, progress: 0.9)
        view.fetchStatus = .Local
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
        view.fetchStatus = .Fetching(isActive: true, progress: 0.1)
        view.fetchStatus = nil
        XCTAssertFalse(cover.isHidden)
        XCTAssertTrue(view.progressView.isHidden)
    }

    func testBodyClickStillStartsPlaybackBeforeDownloadCompletes() {
        let view = PlaybackProbe(frame: NSMakeRect(0, 0, 200, 40))
        for status: MediaResourceStatus in [.Remote(progress: 0), .Fetching(isActive: true, progress: 0.25), .Paused(progress: 0.25), .Local] {
            view.fetchStatus = status
            view.executeInteraction(false)
        }
        XCTAssertEqual(view.openCount, 4)
        view.userInteractionEnabled = false
        view.executeInteraction(false)
        XCTAssertEqual(view.openCount, 4)
    }

    func testProgressControlDoesNotStartPlayback() {
        let view = PlaybackProbe(frame: NSMakeRect(0, 0, 200, 40))
        view.fetchStatus = .Fetching(isActive: true, progress: 0.25)
        view.executeInteraction(true)
        XCTAssertEqual(view.openCount, 0)
    }

    private final class PlaybackProbe: ChatMusicContentView {
        var openCount = 0
        override func open() {
            openCount += 1
        }
    }
}
