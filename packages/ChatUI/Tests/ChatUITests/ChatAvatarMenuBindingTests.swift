import XCTest
import TGUIKit
@testable import ChatUI

final class ChatAvatarMenuBindingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
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
