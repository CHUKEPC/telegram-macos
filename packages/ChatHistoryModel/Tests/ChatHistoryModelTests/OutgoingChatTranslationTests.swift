import Foundation
import XCTest
import Postbox
import TelegramCore
@testable import ChatHistoryModel

final class OutgoingChatTranslationTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let chatId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))
    private let english = "This message is already written in English."
    private let russian = "Привет, как твои дела?"

    private func message(_ text: String, incoming: Bool = false, attributes: [MessageAttribute] = [], media: [Media] = []) -> Message {
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: chatId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: text, attributes: attributes, media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func state(_ message: Message, to: String = "en") -> ChatLiveTranslateContext.State {
        var state = ChatLiveTranslateContext.State.default
        state.canTranslate = true
        state.translate = true
        state.to = to
        state.result[.init(id: message.id, toLang: to)] = .loading(toLang: to)
        state.transcriptionResult[.init(id: message.id, toLang: to)] = .loading(toLang: to)
        return state
    }

    func testTargetLanguageSkipsQueueEligibilityAndLoadingState() {
        for text in [english, "Hi", "OK", "No", "12345", "😀"] {
            let message = message(text)
            XCTAssertFalse(canTranslateChatMessage(message, accountPeerId: accountId, toLang: "en"), text)
            XCTAssertNil(state(message).translationResult(for: message, accountPeerId: accountId), text)
        }
    }

    func testCachedTranslationCannotOverrideTargetLanguageOriginal() {
        let translation = TranslationMessageAttribute(text: "Old translation", entities: [], toLang: "en")
        let message = message(english, attributes: [translation])
        XCTAssertNil(state(message).translationResult(for: message, accountPeerId: accountId))
        let foreignMessage = self.message(russian, attributes: [translation])
        XCTAssertEqual(state(foreignMessage).translationResult(for: foreignMessage, accountPeerId: accountId), .complete(toLang: "en"))
    }

    func testForeignOutgoingAndIncomingKeepTranslation() {
        let foreignMessage = message(russian)
        XCTAssertTrue(canTranslateChatMessage(foreignMessage, accountPeerId: accountId, toLang: "en"))
        XCTAssertEqual(state(foreignMessage).translationResult(for: foreignMessage, accountPeerId: accountId), .loading(toLang: "en"))
        let incoming = message(english, incoming: true)
        XCTAssertTrue(canTranslateChatMessage(incoming, accountPeerId: accountId, toLang: "en"))
        XCTAssertEqual(state(incoming).translationResult(for: incoming, accountPeerId: accountId), .loading(toLang: "en"))
    }

    func testTargetLanguageChangeAndDisabledTranslation() {
        let message = message(english)
        XCTAssertTrue(canTranslateChatMessage(message, accountPeerId: accountId, toLang: "ru"))
        XCTAssertEqual(state(message, to: "ru").translationResult(for: message, accountPeerId: accountId), .loading(toLang: "ru"))
        var disabled = state(message, to: "ru")
        disabled.translate = false
        XCTAssertNil(disabled.translationResult(for: message, accountPeerId: accountId))
    }

    func testCaptionUsesSameEligibilityAndPresentationGate() {
        let image = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let caption = message(english, media: [image])
        XCTAssertFalse(canTranslateChatMessage(caption, accountPeerId: accountId, toLang: "en"))
        XCTAssertNil(state(caption).translationResult(for: caption, accountPeerId: accountId))
        XCTAssertTrue(canTranslateChatMessage(message(russian, media: [image]), accountPeerId: accountId, toLang: "en"))
    }

    func testTranscriptionUsesItsOwnTextAndSuppressesCachedResult() {
        func transcription(_ text: String, pending: Bool = false) -> Message {
            return message("", attributes: [AudioTranscriptionMessageAttribute(id: 1, text: text, isPending: pending, didRate: false, error: nil)])
        }
        let target = transcription(english)
        XCTAssertFalse(canTranslateChatMessage(target, accountPeerId: accountId, toLang: "en", transcription: true))
        var translated = state(target)
        translated.transcriptionResult[.init(id: target.id, toLang: "en")] = .complete(toLang: "en", text: "Old translation")
        XCTAssertNil(translated.transcriptionTranslationResult(for: target, accountPeerId: accountId))
        let foreign = transcription(russian)
        XCTAssertTrue(canTranslateChatMessage(foreign, accountPeerId: accountId, toLang: "en", transcription: true))
        XCTAssertEqual(state(foreign).transcriptionTranslationResult(for: foreign, accountPeerId: accountId), .loading(toLang: "en"))
        XCTAssertFalse(canTranslateChatMessage(transcription(russian, pending: true), accountPeerId: accountId, toLang: "en", transcription: true))
    }

    func testChecksTextBeyondFirstSampleAndNestedRichContent() {
        XCTAssertTrue(canTranslateChatMessage(message(String(repeating: english + " ", count: 10) + russian), accountPeerId: accountId, toLang: "en"))
        func rich(_ body: String) -> Message {
            let page = InstantPage(blocks: [.details(title: .plain(english), blocks: [.paragraph(.plain(body))], expanded: false)], media: [:], isComplete: true, rtl: false, url: "", views: nil)
            return message("", attributes: [RichTextMessageAttribute(instantPage: page, fullInstantPage: nil)])
        }
        XCTAssertFalse(canTranslateChatMessage(rich(english), accountPeerId: accountId, toLang: "en"))
        XCTAssertTrue(canTranslateChatMessage(rich(russian), accountPeerId: accountId, toLang: "en"))
    }

    func testChineseScriptAliasesAndRegionalEnglish() {
        XCTAssertFalse(canTranslateChatMessage(message(english), accountPeerId: accountId, toLang: "en-US"))
        XCTAssertFalse(canTranslateChatMessage(message("明天我们一起去公园散步。"), accountPeerId: accountId, toLang: "zh-CN"))
        XCTAssertFalse(canTranslateChatMessage(message("明天我們一起去公園散步。"), accountPeerId: accountId, toLang: "zh-TW"))
        XCTAssertTrue(canTranslateChatMessage(message("明天我們一起去公園散步。"), accountPeerId: accountId, toLang: "zh-CN"))
    }
}
