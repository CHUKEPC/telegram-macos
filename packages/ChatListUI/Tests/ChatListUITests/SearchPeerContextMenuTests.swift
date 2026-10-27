import XCTest
import TGUIKit
import Localization
@testable import ChatListUI

final class SearchPeerContextMenuTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        applyMacEnglishStrings()
    }

    private func actions(_ record: @escaping (String) -> Void = { _ in }) -> SearchPeerMenuActions {
        return SearchPeerMenuActions(openProfile: { record("profile") }, markRead: { record($0 ? "read" : "unread") }, mute: { record("mute:\($0)") }, muteUntil: { record("until") }, togglePin: { record("pin") })
    }

    private func state(recent: Bool = false, unread: Bool = false, muted: Bool = false, pinned: Bool = false, profile: Bool = true, manage: Bool = true, canMarkUnread: Bool = true) -> SearchPeerMenuState {
        return SearchPeerMenuState(canOpenProfile: profile, canManageChat: manage, canMarkUnread: canMarkUnread, canPin: recent, isUnread: unread, isMuted: muted, isPinned: pinned)
    }

    private func labels(_ items: [ContextMenuItem]) -> [String] {
        return items.map { $0 is ContextSeparatorItem ? "separator" : $0.title }
    }

    func testPopularKeepsOriginalRemovalAndDoesNotOfferPin() throws {
        var removed = 0
        let remove = ContextMenuItem(strings().searchPopularDelete, handler: { removed += 1 }, itemMode: .destruct)
        let folder = ContextMenuItem("Work")
        let items = searchPeerMenuItems(state: state(), profileTitle: strings().exportedInvitationContextOpenProfile, actions: actions(), folders: [folder], remove: remove)
        XCTAssertEqual(labels(items), [strings().exportedInvitationContextOpenProfile, strings().chatListContextMaskAsUnread, strings().chatListContextMute, "separator", strings().chatListFilterAddToFolder, "separator", strings().searchPopularDelete])
        XCTAssertTrue(items.last === remove)
        items.last?.handler?()
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(items[4].submenu?.items.first === folder)
    }

    func testRecentReadMutedPinnedStatesAndCallbacks() {
        var called: [String] = []
        let remove = ContextMenuItem(strings().searchRemoveFromRecent)
        let items = searchPeerMenuItems(state: state(recent: true, unread: true, muted: true, pinned: true), profileTitle: "Profile", actions: actions { called.append($0) }, folders: [ContextMenuItem("Work")], remove: remove)
        XCTAssertEqual(labels(items), ["Profile", strings().chatListContextMaskAsRead, strings().chatListContextUnmute, "separator", strings().chatListContextUnpin, strings().chatListFilterAddToFolder, "separator", strings().searchRemoveFromRecent])
        items[0].handler?()
        items[1].handler?()
        items[2].handler?()
        items[4].handler?()
        XCTAssertEqual(called, ["profile", "read", "mute:0", "pin"])
        XCTAssertNil(items[2].submenu)
    }

    func testSearchResultsHaveNoPinRemovalOrTrailingSeparator() {
        let items = searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: actions(), folders: [ContextMenuItem("Work")], remove: nil)
        XCTAssertEqual(labels(items), ["Profile", strings().chatListContextMaskAsUnread, strings().chatListContextMute, "separator", strings().chatListFilterAddToFolder])
        XCTAssertFalse(items.last is ContextSeparatorItem)
    }

    func testNotificationSubmenuDurationsAndUnreadAction() throws {
        var called: [String] = []
        let items = searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: actions { called.append($0) }, folders: [], remove: nil)
        items[1].handler?()
        let submenu = try XCTUnwrap(items[2].submenu)
        XCTAssertEqual(submenu.items.count, 6)
        for item in submenu.items where !(item is ContextSeparatorItem) {
            (item as? ContextMenuItem)?.handler?()
        }
        XCTAssertEqual(called, ["unread", "mute:3600", "mute:28800", "mute:259200", "until", "mute:2147483647"])
    }

    func testReadOnlyUnreadPolicyDoesNotHideMuteForSecretChatsOrForums() {
        let read = searchPeerMenuItems(state: state(canMarkUnread: false), profileTitle: "Profile", actions: actions(), folders: [], remove: nil)
        XCTAssertEqual(labels(read), ["Profile", strings().chatListContextMute])
        XCTAssertNotNil(read[1].submenu)
        var called: [String] = []
        let unread = searchPeerMenuItems(state: state(unread: true, canMarkUnread: false), profileTitle: "Profile", actions: actions { called.append($0) }, folders: [], remove: nil)
        XCTAssertEqual(labels(unread), ["Profile", strings().chatListContextMaskAsRead, strings().chatListContextMute])
        unread[1].handler?()
        XCTAssertEqual(called, ["read"])
    }

    func testMissingChatAndSavedMessagesOmitInapplicableActions() {
        let missing = searchPeerMenuItems(state: state(manage: false), profileTitle: "Profile", actions: actions(), folders: [], remove: nil)
        XCTAssertEqual(labels(missing), ["Profile"])
        let saved = searchPeerMenuItems(state: state(profile: false, manage: false), profileTitle: "Profile", actions: actions(), folders: [ContextMenuItem("Work")], remove: nil)
        XCTAssertEqual(labels(saved), [strings().chatListFilterAddToFolder])
        let remove = ContextMenuItem(strings().searchPopularDelete)
        let removalOnly = searchPeerMenuItems(state: state(profile: false, manage: false), profileTitle: "Profile", actions: actions(), folders: [], remove: remove)
        XCTAssertEqual(removalOnly.count, 1)
        XCTAssertTrue(removalOnly[0] === remove)
    }
}
