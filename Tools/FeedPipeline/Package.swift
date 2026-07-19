// swift-tools-version: 6.0
import PackageDescription

// Owed feed ingestion pipeline (PIPELINE.md §1–4). A build/ops tool, not
// shipped in the app. It reuses the app's Settlement schema by symlinking
// the canonical model sources into FeedPipelineCore/Vendored, so an
// ingested record is validated by the exact strict decoder the client
// uses — the pipeline can never emit a feed the app would reject.
let package = Package(
    name: "FeedPipeline",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FeedPipelineCore"),
        .executableTarget(
            name: "feedctl",
            dependencies: ["FeedPipelineCore"]
        ),
        .testTarget(
            name: "FeedPipelineCoreTests",
            dependencies: ["FeedPipelineCore"]
        ),
    ]
)
