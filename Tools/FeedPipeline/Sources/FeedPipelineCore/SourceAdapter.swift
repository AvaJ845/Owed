import Foundation

/// Network I/O is injected, never hard-wired, so every adapter is
/// testable against a committed fixture and the pipeline core stays
/// pure. Live runs pass a real URLSession fetch; tests pass a closure
/// over fixture bytes.
public typealias Fetcher = @Sendable (URL) async throws -> Data

/// Default live fetcher: a plain GET, no cookies, no credentials — the
/// pipeline reads public data only (PIPELINE.md privacy posture).
public func liveFetcher(timeout: TimeInterval = 30) -> Fetcher {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.timeoutIntervalForRequest = timeout
    let session = URLSession(configuration: config)
    return { url in
        var request = URLRequest(url: url)
        request.setValue("owed-feedctl", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PipelineError.badResponse(url: url,
                status: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}

/// A discovery source (PIPELINE.md §1). Adapters only ever *discover* —
/// they emit `Lead`s at `.lead`/`.inReview`, never `.published`. Nothing
/// an adapter produces reaches the app without a human decision.
public protocol SourceAdapter: Sendable {
    /// Provenance label recorded on every field this adapter fills.
    var sourceName: String { get }
    func discover() async throws -> [Lead]
}

public enum PipelineError: Error, CustomStringConvertible {
    case badResponse(url: URL, status: Int)
    case decode(String)
    case validation(String)

    public var description: String {
        switch self {
        case let .badResponse(url, status): "HTTP \(status) from \(url)"
        case let .decode(m): "Decode failed: \(m)"
        case let .validation(m): "Feed validation failed: \(m)"
        }
    }
}
