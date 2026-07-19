import CryptoKit
import Foundation

/// Ed25519 verification of a feed file against its detached signature —
/// the same check the app performs, reimplemented here so `publish` can
/// confirm the base feed it carries forward is the genuine signed
/// artifact, not a locally tampered file (PIPELINE.md §4 supply-chain
/// gate). Publishing re-validates *structure* via the app decoder, but a
/// tampered-yet-well-formed `adminURL` swap would pass that; the
/// signature is what proves *intent*.
public enum FeedIntegrity {
    public enum Check: Equatable, CustomStringConvertible {
        case verified
        case unsigned      // .sig or public key missing/unreadable
        case invalid       // present but does not verify

        public var description: String {
            switch self {
            case .verified: "verified"
            case .unsigned: "unsigned (no .sig / public key)"
            case .invalid: "INVALID — signature does not match the file"
            }
        }
    }

    public static func verify(feed: Data, signatureB64: String, publicKeyB64: String) -> Check {
        let clean: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let pubRaw = Data(base64Encoded: clean(publicKeyB64)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: pubRaw)
        else { return .unsigned }
        guard let sig = Data(base64Encoded: clean(signatureB64)), sig.count == 64
        else { return .invalid }
        return key.isValidSignature(sig, for: feed) ? .verified : .invalid
    }

    /// File convenience: `<feed>` verified against `<feed>.sig` under the
    /// bundled `FeedPublicKey.b64`.
    public static func verifyFiles(feedURL: URL, signatureURL: URL, publicKeyURL: URL) -> Check {
        guard let feed = try? Data(contentsOf: feedURL) else { return .unsigned }
        guard let sig = try? String(contentsOf: signatureURL, encoding: .utf8),
              let pub = try? String(contentsOf: publicKeyURL, encoding: .utf8)
        else { return .unsigned }
        return verify(feed: feed, signatureB64: sig, publicKeyB64: pub)
    }
}
