#!/bin/zsh
# Sign Owed/Resources/SettlementFeed.json with the Ed25519 private key.
# Creates Scripts/keys/ on first run if missing.
set -euo pipefail
# Private key material: create it unreadable by group/other from the
# start (umask) and belt-and-suspenders chmod below. A world-readable
# signing key on a shared machine is a feed-forgery risk.
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYS="$ROOT/Scripts/keys"
PRIV="$KEYS/feed_ed25519_private.b64"
PUB_BUNDLE="$ROOT/Owed/Resources/FeedPublicKey.b64"
FEED="$ROOT/Owed/Resources/SettlementFeed.json"
SIG="$ROOT/Owed/Resources/SettlementFeed.json.sig"

mkdir -p "$KEYS"
chmod 700 "$KEYS"

xcrun swift -e "
import CryptoKit
import Foundation

let privPath = \"$PRIV\"
let pubPath = \"$PUB_BUNDLE\"
let feedPath = \"$FEED\"
let sigPath = \"$SIG\"

let priv: Curve25519.Signing.PrivateKey
if let b64 = try? String(contentsOfFile: privPath, encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines),
   let raw = Data(base64Encoded: b64),
   let existing = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
    priv = existing
} else {
    priv = Curve25519.Signing.PrivateKey()
    try! priv.rawRepresentation.base64EncodedString()
        .write(toFile: privPath, atomically: true, encoding: .utf8)
    fputs(\"Generated new private key at \(privPath) — back it up; it is gitignored.\\n\", stderr)
}

let pubB64 = priv.publicKey.rawRepresentation.base64EncodedString()
try! pubB64.write(toFile: pubPath, atomically: true, encoding: .utf8)

let feed = try! Data(contentsOf: URL(fileURLWithPath: feedPath))
let sig = try! priv.signature(for: feed)
try! sig.base64EncodedString().write(toFile: sigPath, atomically: true, encoding: .utf8)
print(\"Signed \(feedPath)\")
print(\"Public key → \(pubPath)\")
print(\"Signature  → \(sigPath)\")
"

# Belt-and-suspenders: enforce 0600 even if the key predates the umask line.
[ -f "$PRIV" ] && chmod 600 "$PRIV"
