import Foundation
import os

/// The settlement feed envelope (PIPELINE.md §3). Today it decodes the
/// reviewed snapshot bundled with the app; step 2 points the same decode
/// path at the CDN feed with this snapshot as the offline floor.
///
/// Decoding policy — strict structure, tolerant vocabulary:
/// - An envelope with the wrong `schemaVersion` fails whole. The shape
///   is the contract; guessing at an unknown shape risks showing a wrong
///   deadline, which is worse than showing nothing.
/// - A malformed settlement record is dropped, not fatal. One bad record
///   in a published feed must never blank the app.
/// - Records this build can't fully use (unknown match keys) still decode;
///   unknown keys are ignored so older builds survive newer feeds.
struct SettlementFeed: Decodable {
    /// Bump only with an incompatible JSON contract change, in lockstep
    /// with the publisher.
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let settlements: [Settlement]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, settlements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: "Unsupported feed schema \(schemaVersion); this build reads \(Self.supportedSchemaVersion)"
            )
        }

        generatedAt = try container.decode(Date.self, forKey: .generatedAt)

        // Lossy decode: skip records that fail, keep the rest. Duplicate
        // ids keep the first occurrence — ids key all local persistence
        // (tracked/received/calendared), so one id must mean one record.
        var records = try container.nestedUnkeyedContainer(forKey: .settlements)
        var decoded: [Settlement] = []
        var seenIDs = Set<String>()
        var dropped = 0
        while !records.isAtEnd {
            do {
                let s = try records.decode(Settlement.self)
                if seenIDs.insert(s.id).inserted {
                    decoded.append(s)
                } else {
                    dropped += 1
                }
            } catch {
                // A failed decode does not advance the container; consume
                // the malformed record so the loop can continue.
                _ = try? records.decode(SkippedRecord.self)
                dropped += 1
                Self.log.error("Dropped malformed settlement record: \(String(describing: error))")
            }
        }
        if dropped > 0 {
            Self.log.error("Feed decoded with \(dropped) dropped record(s) of \(decoded.count + dropped)")
        }
        settlements = decoded
    }

    fileprivate static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Owed", category: "feed"
    )
}

/// Placeholder that decodes any value, used to advance past a malformed
/// record in an unkeyed container.
private struct SkippedRecord: Decodable {}

// MARK: - Loading

extension SettlementFeed {
    /// The snapshot shipped in the app bundle. A missing or undecodable
    /// bundled feed is a build defect: assert in Debug, return nil (empty
    /// feed) in Release rather than crash.
    static func bundled(from bundle: Bundle = .main) -> SettlementFeed? {
        guard let url = bundle.url(forResource: "SettlementFeed", withExtension: "json") else {
            assertionFailure("SettlementFeed.json missing from bundle")
            log.fault("SettlementFeed.json missing from bundle")
            return nil
        }
        do {
            let decoder = JSONDecoder()
            // Applies to `generatedAt` only; settlement day-precision
            // fields decode through FeedDay.
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SettlementFeed.self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Bundled feed failed to decode: \(error)")
            log.fault("Bundled feed failed to decode: \(String(describing: error))")
            return nil
        }
    }
}

// MARK: - Day-precision dates

/// Feed contract for calendar-day fields (`deadline`, `verifiedAt`):
/// "yyyy-MM-dd", interpreted as local midnight. Filing deadlines are
/// days, not instants; local interpretation means the deadline day
/// counts as open in the user's own calendar, matching `daysLeft` and
/// `closed`, which compare against `Calendar.current.startOfDay`.
enum FeedDay {
    /// Fixed-format parser: POSIX locale so user 12/24-hour and calendar
    /// settings can't alter parsing; current time zone on purpose.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a "yyyy-MM-dd" feed day, throwing a descriptive error on
    /// any other format so the bad record is dropped and logged upstream.
    func decodeFeedDay(forKey key: Key) throws -> Date {
        let raw = try decode(String.self, forKey: key)
        guard let date = FeedDay.date(from: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self,
                debugDescription: "Expected yyyy-MM-dd, got \"\(raw)\""
            )
        }
        return date
    }
}
