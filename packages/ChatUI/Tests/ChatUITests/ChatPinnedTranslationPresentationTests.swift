import XCTest
import Postbox
import TelegramCore
import ChatHistoryModel
@testable import ChatUI

final class ChatPinnedTranslationPresentationTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let chatId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))

    private func message(incoming: Bool = false, version: UInt32 = 0) -> Message {
        return Message(stableId: 1, stableVersion: version, id: MessageId(peerId: chatId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "Pinned text", attributes: [], media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func state(for message: Message) -> ChatLiveTranslateContext.State {
        var state = ChatLiveTranslateContext.State.default
        state.canTranslate = true
        state.translate = true
        state.to = "en"
        state.result[.init(id: message.id, toLang: "en")] = .loading(toLang: "en")
        return state
    }

    func testPreparedEligibilitySurvivesPresentationMappingAndChangesEquality() {
        let pinned = message()
        var source = state(for: pinned)
        let before = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertNil(before.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
        source.translationEligibility[.init(id: pinned.id, toLang: "en")] = pinned.stableVersion
        let after = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after.translationEligibility, source.translationEligibility)
        XCTAssertEqual(after.pinnedTranslationResult(for: pinned, accountPeerId: accountId), .loading(toLang: "en"))
        source.result[.init(id: pinned.id, toLang: "en")] = .complete(toLang: "en")
        XCTAssertEqual(ChatPresentationInterfaceState.TranslateState(source).pinnedTranslationResult(for: pinned, accountPeerId: accountId), .complete(toLang: "en"))
    }

    func testProjectionRejectsStaleVersionsTargetsAndDisabledState() {
        let pinned = message()
        var source = state(for: pinned)
        source.translationEligibility[.init(id: pinned.id, toLang: "en")] = 0
        var projected = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertNil(projected.pinnedTranslationResult(for: message(version: 1), accountPeerId: accountId))
        projected.to = "ru"
        projected.result[.init(id: pinned.id, toLang: "ru")] = .complete(toLang: "ru")
        XCTAssertNil(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
        projected.to = "en"
        projected.translate = false
        XCTAssertNil(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
        projected.translate = true
        projected.canTranslate = false
        XCTAssertNil(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
    }

    func testIncomingPinsRetainLookupWithoutOutgoingEligibility() {
        let pinned = message(incoming: true)
        let source = state(for: pinned)
        let projected = ChatPresentationInterfaceState.TranslateState(source)
        XCTAssertTrue(projected.translationEligibility.isEmpty)
        XCTAssertEqual(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId), .loading(toLang: "en"))
        XCTAssertEqual(projected.pinnedTranslationResult(for: pinned, accountPeerId: accountId), source.pinnedTranslationResult(for: pinned, accountPeerId: accountId))
    }
}
