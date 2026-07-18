import CryptoKit
import Foundation
import Testing
@testable import Owed

struct FeedSigningTests {

    @Test func bundledSignatureMatchesBundledFeed() throws {
        let feed = try #require(Bundle.main.url(forResource: "SettlementFeed", withExtension: "json"))
        let sigURL = Bundle.main.url(forResource: "SettlementFeed.json", withExtension: "sig")
            ?? Bundle.main.url(forResource: "SettlementFeed", withExtension: "json.sig")
        let sig = try #require(sigURL)
        let payload = try Data(contentsOf: feed)
        let signature = try Data(contentsOf: sig)
        #expect(FeedSigning.verify(payload: payload, signature: signature))
    }

    @Test func tamperedFeedFailsVerification() throws {
        let feed = try #require(Bundle.main.url(forResource: "SettlementFeed", withExtension: "json"))
        let sigURL = Bundle.main.url(forResource: "SettlementFeed.json", withExtension: "sig")
            ?? Bundle.main.url(forResource: "SettlementFeed", withExtension: "json.sig")
        let sig = try #require(sigURL)
        var payload = try Data(contentsOf: feed)
        payload.append(contentsOf: [0x00]) // one extra byte — signature must fail
        let signature = try Data(contentsOf: sig)
        #expect(!FeedSigning.verify(payload: payload, signature: signature))
    }

    @Test func randomSignatureFails() throws {
        let feed = try #require(Bundle.main.url(forResource: "SettlementFeed", withExtension: "json"))
        let payload = try Data(contentsOf: feed)
        let junk = Data(repeating: 0xAB, count: 64)
        #expect(!FeedSigning.verify(payload: payload, signature: junk))
    }
}
