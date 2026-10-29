import XCTest
import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import ChatModeTypes
@testable import ChatUI

final class ChatAvatarMenuBindingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let account = NSObject()
    private let interaction = NSObject()

    private func peer(_ id: Int64 = 2) -> Peer {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Author", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func channel(canBan: Bool) -> Peer {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(3)), accessHash: nil, title: "Group", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: canBan ? TelegramChatAdminRights(flags: [.canBanUsers]) : nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func context(author: Int64 = 2, row: Int = 1, message: Int32 = 1, account: NSObject? = nil, interaction: NSObject? = nil, chat: Peer? = nil, mode: ChatMode = .history, thread: Int64? = nil, stories: Bool = false) -> ChatAvatarView.MenuContext {
        let peer = self.peer(author)
        let chat = chat ?? channel(canBan: true)
        return .init(account: ObjectIdentifier(account ?? self.account), interaction: ObjectIdentifier(interaction ?? self.interaction), chatPeerId: chat.id, threadId: thread, mode: mode, rowId: AnyHashable(row), messageId: MessageId(peerId: chat.id, namespace: Namespaces.Message.Cloud, id: message), peer: peer, chatPeer: chat, hasStories: stories)
    }

    private func factory(_ action: @escaping (String) -> Void) -> () -> ContextMenu? {
        return {
            let menu = ContextMenu()
            menu.items = ["Open Profile", "Send Message", "Mention", "Restrict", "Ban"].map { name in
                ContextMenuItem(name, handler: { action(name) })
            }
            let submenu = ContextMenu()
            submenu.items = [ContextMenuItem("Nested Ban", handler: { action("Nested Ban") })]
            let parent = ContextMenuItem("Actions")
            parent.submenu = submenu
            menu.items += [parent]
            return menu
        }
    }

    private func invoke(_ menu: NSMenu) {
        for case let item as ContextMenuItem in menu.items {
            item.handler?()
            if let submenu = item.submenu { invoke(submenu) }
        }
    }

    func testSameContextRefreshPreservesOpenMenuAndNestedActions() throws {
        let avatar = ChatAvatarView(frame: .zero)
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: context())
        let previousFactory = try XCTUnwrap(avatar.contextMenu)
        let open = try XCTUnwrap(previousFactory())
        avatar.updateContextMenu(factory { calls.append("new " + $0) }, context: context())
        XCTAssertNotNil(previousFactory())
        invoke(open)
        XCTAssertEqual(calls, ["Open Profile", "Send Message", "Mention", "Restrict", "Ban", "Nested Ban"])
        let current = try XCTUnwrap(avatar.contextMenu?())
        invoke(current)
        XCTAssertEqual(calls.count, 12)
        XCTAssertEqual(calls.last, "new Nested Ban")
    }

    func testSemanticContextChangesInvalidateAllOpenActions() throws {
        let otherAccount = NSObject()
        let otherInteraction = NSObject()
        let replacements = [context(author: 4), context(row: 2), context(message: 2), context(account: otherAccount), context(interaction: otherInteraction), context(chat: channel(canBan: false)), context(mode: .pinned), context(thread: 7), context(stories: true)]
        for replacement in replacements {
            let avatar = ChatAvatarView(frame: .zero)
            var calls: [String] = []
            avatar.updateContextMenu(factory { calls.append($0) }, context: context())
            let previousFactory = try XCTUnwrap(avatar.contextMenu)
            let open = try XCTUnwrap(previousFactory())
            avatar.updateContextMenu(factory { calls.append($0) }, context: replacement)
            XCTAssertNil(previousFactory())
            invoke(open)
            XCTAssertTrue(calls.isEmpty)
            invoke(try XCTUnwrap(avatar.contextMenu?()))
            XCTAssertEqual(calls.count, 6)
        }
    }

    func testLivePermissionChangeInvalidatesActionsWithoutRebinding() throws {
        let avatar = ChatAvatarView(frame: .zero)
        let captured = context()
        var current = captured
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: captured, isCurrent: { current == captured })
        let previousFactory = try XCTUnwrap(avatar.contextMenu)
        let open = try XCTUnwrap(previousFactory())
        current = context(chat: channel(canBan: false))
        XCTAssertNil(previousFactory())
        invoke(open)
        XCTAssertTrue(calls.isEmpty)
    }

    func testRefreshUsesLatestRowLivenessCheck() throws {
        let avatar = ChatAvatarView(frame: .zero)
        var previousAlive = true
        var currentAlive = true
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: context(), isCurrent: { previousAlive })
        let open = try XCTUnwrap(avatar.contextMenu?())
        previousAlive = false
        avatar.updateContextMenu(factory { calls.append($0) }, context: context(), isCurrent: { currentAlive })
        invoke(open)
        XCTAssertEqual(calls.count, 6)
        currentAlive = false
        invoke(open)
        XCTAssertEqual(calls.count, 6)
    }

    func testRemovalInvalidatesSameContextMenu() throws {
        let avatar = ChatAvatarView(frame: .zero)
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: context())
        let open = try XCTUnwrap(avatar.contextMenu?())
        avatar.updateContextMenu(nil)
        XCTAssertNil(avatar.contextMenu)
        invoke(open)
        XCTAssertTrue(calls.isEmpty)
    }

    func testReuseInvalidatesOldActionsAndUsesNewAuthor() throws {
        let avatar = ChatAvatarView(frame: .zero)
        var calls: [String] = []
        func factory(_ author: String) -> () -> ContextMenu? {
            return {
                let menu = ContextMenu()
                let submenu = ContextMenu()
                submenu.items = [ContextMenuItem("Ban", handler: { calls.append(author) })]
                let parent = ContextMenuItem("Actions")
                parent.submenu = submenu
                menu.items = [ContextMenuItem("Open", handler: { calls.append(author) }), parent]
                return menu
            }
        }
        avatar.updateContextMenu(factory("A"))
        let oldFactory = try XCTUnwrap(avatar.contextMenu)
        let old = try XCTUnwrap(oldFactory())
        avatar.updateContextMenu(factory("B"))
        XCTAssertNil(oldFactory())
        (old.items[0] as? ContextMenuItem)?.handler?()
        (old.items[1].submenu?.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertTrue(calls.isEmpty)
        let current = try XCTUnwrap(avatar.contextMenu?())
        (current.items[0] as? ContextMenuItem)?.handler?()
        (current.items[1].submenu?.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(calls, ["B", "B"])
        avatar.updateContextMenu(factory("B-new-item"))
        (current.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(calls, ["B", "B"])
        let replacement = try XCTUnwrap(avatar.contextMenu?())
        (replacement.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(calls.last, "B-new-item")
        avatar.updateContextMenu(nil)
        XCTAssertNil(avatar.contextMenu)
        (replacement.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(calls.count, 3)
    }
}
