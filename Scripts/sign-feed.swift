#!/usr/bin/env swift
// Publisher-side feed signing (PIPELINE.md §4 — publish step).
//
// Signs Owed/Resources/SettlementFeed.json with Ed25519 and writes the
// detached signature to Owed/Resources/SettlementFeed.json.sig. The app
// verifies both files fetched from the CDN against the public key
// embedded in FeedStore, so a compromised CDN can't inject a fake feed.
//
// The private key lives at ~/.config/owed/feed-signing.key (created on
// first run, chmod 600) and must NEVER be committed. If it's lost,
// generate a new pair, update FeedStore.feedPublicKeyBase64, and ship an
// app update before publishing feeds signed with the new key.
//
// Usage: ./Scripts/sign-feed.swift   (from the repo root; then commit
//        the .sig alongside the feed)

import CryptoKit
import Foundation

let fm = FileManager.default
let keyDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/owed")
let keyURL = keyDir.appendingPathComponent("feed-signing.key")

let feedURL = URL(fileURLWithPath: "Owed/Resources/SettlementFeed.json")
let sigURL = URL(fileURLWithPath: "Owed/Resources/SettlementFeed.json.sig")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// Load or create the private key.
let privateKey: Curve25519.Signing.PrivateKey
if let raw = try? Data(contentsOf: keyURL),
   let decoded = Data(base64Encoded: raw.trimmed()) {
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: decoded) else {
        fail("could not parse private key at \(keyURL.path)")
    }
    privateKey = key
    print("Using existing key: \(keyURL.path)")
} else {
    privateKey = Curve25519.Signing.PrivateKey()
    try? fm.createDirectory(at: keyDir, withIntermediateDirectories: true)
    do {
        try privateKey.rawRepresentation.base64EncodedData()
            .write(to: keyURL, options: .completeFileProtection)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
    } catch {
        fail("could not write private key: \(error)")
    }
    print("Generated NEW signing key: \(keyURL.path)")
    print("Embed this public key in FeedStore.feedPublicKeyBase64:")
    print("  \(privateKey.publicKey.rawRepresentation.base64EncodedString())")
}

// Sign the feed.
guard let feedData = try? Data(contentsOf: feedURL) else {
    fail("feed not found at \(feedURL.path) — run from the repo root")
}
guard let signature = try? privateKey.signature(for: feedData) else {
    fail("signing failed")
}
do {
    try signature.base64EncodedString().write(to: sigURL, atomically: true, encoding: .utf8)
} catch {
    fail("could not write signature: \(error)")
}

print("Signed \(feedURL.path) (\(feedData.count) bytes)")
print("  -> \(sigURL.path)")
print("Public key: \(privateKey.publicKey.rawRepresentation.base64EncodedString())")

extension Data {
    func trimmed() -> Data {
        Data(String(decoding: self, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }
}
