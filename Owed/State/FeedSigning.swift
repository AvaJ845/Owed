import CryptoKit
import Foundation
import os

/// Ed25519 verification of the published feed bytes.
///
/// The feed sends users to administrator URLs where they enter personal
/// information — a CDN compromise that injects a fake form is a real
/// harm model. The app embeds the publisher's public key; remote feeds
/// must carry a matching detached signature (`SettlementFeed.json.sig`)
/// or they never replace last-good. The bundled snapshot is trusted as
/// part of the signed app binary and is not re-verified at runtime.
///
/// Sign with `Scripts/sign-feed.sh` after editing the JSON. Private key
/// lives in `Scripts/keys/` (gitignored).
enum FeedSigning {
    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Owed", category: "feedsign"
    )

    /// Verifies `signature` (raw 64-byte Ed25519, or base64 text of same)
    /// over the exact `payload` bytes.
    static func verify(payload: Data, signature signatureData: Data) -> Bool {
        guard let publicKey = publicKey() else {
            log.fault("Feed public key missing from bundle")
            return false
        }
        let signature = decodeSignature(signatureData)
        guard signature.count == 64 else {
            log.error("Feed signature has unexpected length \(signature.count)")
            return false
        }
        return publicKey.isValidSignature(signature, for: payload)
    }

    private static func publicKey() -> Curve25519.Signing.PublicKey? {
        guard let url = Bundle.main.url(forResource: "FeedPublicKey", withExtension: "b64"),
              let b64 = try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let raw = Data(base64Encoded: b64)
        else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    private static func decodeSignature(_ data: Data) -> Data {
        if data.count == 64 { return data }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let decoded = Data(base64Encoded: text) {
            return decoded
        }
        return data
    }
}
