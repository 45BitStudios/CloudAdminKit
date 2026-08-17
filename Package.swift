// swift-tools-version: 6.2
// CloudAdminKit — the public client SDK for apps managed by CloudAdmin.
//
// Advertised SwiftPM pin: 1.0.0 (README / AGENTS.md / Integration.md).
// FIXME: Vince must tag 1.0.0 after merge so `from: "1.0.0"` resolves on
// https://github.com/45BitStudios/CloudAdminKit.git. Do not tag from this branch.
//
// Two independent halves, no cross-target dependency between them:
//   CloudAdminClient/CloudAdminClientUI — feature flags, remote settings, analytics,
//     feature requests. Talks to CloudAdmin's CloudKit backend on behalf of any app.
//   CloudAdminPush/CloudAdminPushUI    — push/Live-Activity registration against
//     IkigaiServer (formerly the standalone IkigaiPush package).
//
// CloudAdminPushUI carries a small duplicated file (PushRegistrationController, see its
// ua-debt comment) instead of depending on Ikigai directly — Ikigai depends on
// CloudAdminKit for its converged Analytics/FeatureFlags/FeatureRequests/RemoteSettings,
// so a CloudAdminKit -> Ikigai dependency would be a package cycle SwiftPM rejects.
//
// This package has zero dependencies on any other 45BitStudios repo — that's what lets it
// be public while Ikigai/CloudAdmin/IkigaiServer stay private.
import PackageDescription

let sharedSwiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
]

let package = Package(
    name: "CloudAdminKit",
    defaultLocalization: "en",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .visionOS("26.0"),
        .tvOS("26.0"),
        .watchOS("26.0"),
    ],
    products: [
        .library(name: "CloudAdminClient", targets: ["CloudAdminClient"]),
        .library(name: "CloudAdminClientUI", targets: ["CloudAdminClientUI"]),
        .library(name: "CloudAdminPush", targets: ["CloudAdminPush"]),
        .library(name: "CloudAdminPushUI", targets: ["CloudAdminPushUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.3.0"),
    ],
    targets: [
        // Client SDK: feature flags, remote settings, analytics events, feature requests,
        // plus their CloudKit-backed services. No dependency on any other target here —
        // external apps depend on this directly. No SwiftUI (see CloudAdminClientUI).
        .target(
            name: "CloudAdminClient",
            swiftSettings: sharedSwiftSettings
        ),
        // SwiftUI surface for CloudAdminClient: @FeatureEnabled / @Remote*Setting property
        // wrappers, analytics view modifiers, and PushAppDelegate (forwards into
        // CloudAdminPushUI's PushRegistrationController).
        .target(
            name: "CloudAdminClientUI",
            dependencies: ["CloudAdminClient", "CloudAdminPushUI"],
            swiftSettings: sharedSwiftSettings
        ),
        // Zero-dep HTTP client for IkigaiServer (device + Live Activity token registration).
        .target(
            name: "CloudAdminPush",
            swiftSettings: sharedSwiftSettings
        ),
        // SwiftUI-observable push registration/authorization state. See its ua-debt comment.
        .target(
            name: "CloudAdminPushUI",
            swiftSettings: sharedSwiftSettings
        ),

        // MARK: - Tests (Swift Testing — @Suite/@Test, never XCTest)

        .testTarget(
            name: "CloudAdminClientTests",
            dependencies: ["CloudAdminClient"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "CloudAdminPushTests",
            dependencies: ["CloudAdminPush"],
            swiftSettings: sharedSwiftSettings
        ),
        .testTarget(
            name: "CloudAdminClientUITests",
            dependencies: ["CloudAdminClient", "CloudAdminClientUI"],
            swiftSettings: sharedSwiftSettings
        ),
    ]
)
