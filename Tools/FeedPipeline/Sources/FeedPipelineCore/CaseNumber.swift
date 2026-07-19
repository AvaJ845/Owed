import Foundation

/// Normalizes a court case number into a stable dedup key. The same
/// settlement surfaces from multiple sources with cosmetic differences
/// ("No. 4:19-cv-04286" vs "4:19‑cv‑04286-JST"); collapsing them lets
/// the reviewer confirm each real settlement exactly once (PIPELINE.md
/// §2 dedupe).
public enum CaseNumber {
    /// Lowercased, punctuation-stripped core of the docket number.
    /// Drops a leading "no.", normalizes unicode dashes to '-', removes a
    /// trailing judge-initials segment, and collapses whitespace.
    public static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        // Unify dash variants (en/em/non-breaking hyphen) to ASCII '-'.
        for dash in ["\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}"] {
            s = s.replacingOccurrences(of: dash, with: "-")
        }
        s = s.replacingOccurrences(of: "no.", with: "")
        // Keep alphanumerics, ':', '-', and spaces; drop other punctuation.
        s = String(s.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || ":- ".unicodeScalars.contains($0)
        })
        // Trailing "-abc" judge initials on federal numbers (…-cv-01234-jst).
        if let range = s.range(of: #"(-cv-\d+)-[a-z]{2,4}$"#, options: .regularExpression) {
            let core = String(s[range]).replacingOccurrences(
                of: #"-[a-z]{2,4}$"#, with: "", options: .regularExpression)
            s.replaceSubrange(range, with: core)
        }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
