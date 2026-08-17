//
//  CloudAdminKitVersion.swift
//  CloudAdminClient
//
//  The version adopters pin in Package.swift (`from: "1.0.0"`).
//

/// Semantic version advertised to SwiftPM adopters.
///
/// README, AGENTS.md, and DocC all pin `from: "1.0.0"`. That tag does not exist
/// until it is cut on `main`.
///
/// FIXME: Vince must tag 1.0.0 after merge so advertised SPM pins resolve.
public enum CloudAdminKitVersion: Sendable {
    /// The 1.0 release identifier. Keep in lockstep with the git tag name.
    public static let current = "1.0.0"
}
