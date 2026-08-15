//
//  FeatureFlag.swift
//  CloudAdminClient
//
//  Feature flag model for CloudKit-based feature flag system
//

import Foundation
import CloudKit

/// Supported platforms for feature flags
public struct FeatureFlagPlatform: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let iOS = FeatureFlagPlatform(rawValue: 1 << 0)
    public static let macOS = FeatureFlagPlatform(rawValue: 1 << 1)
    public static let tvOS = FeatureFlagPlatform(rawValue: 1 << 2)
    public static let watchOS = FeatureFlagPlatform(rawValue: 1 << 3)
    public static let visionOS = FeatureFlagPlatform(rawValue: 1 << 4)

    public static let all: FeatureFlagPlatform = [.iOS, .macOS, .tvOS, .watchOS, .visionOS]
    public static let apple: FeatureFlagPlatform = [.iOS, .macOS, .tvOS, .watchOS, .visionOS]
    public static let mobile: FeatureFlagPlatform = [.iOS, .watchOS]
    public static let desktop: FeatureFlagPlatform = [.macOS]

    /// Current platform
    public static var current: FeatureFlagPlatform {
        #if os(iOS)
        return .iOS
        #elseif os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(visionOS)
        return .visionOS
        #else
        return []
        #endif
    }

    /// Platform string identifiers for CloudKit storage
    public var platformStrings: [String] {
        var strings: [String] = []
        if contains(.iOS) { strings.append("iOS") }
        if contains(.macOS) { strings.append("macOS") }
        if contains(.tvOS) { strings.append("tvOS") }
        if contains(.watchOS) { strings.append("watchOS") }
        if contains(.visionOS) { strings.append("visionOS") }
        return strings
    }

    /// Initialize from CloudKit platform strings
    public init(platformStrings: [String]) {
        var platforms: FeatureFlagPlatform = []
        for string in platformStrings {
            switch string.lowercased() {
            case "ios": platforms.insert(.iOS)
            case "macos": platforms.insert(.macOS)
            case "tvos": platforms.insert(.tvOS)
            case "watchos": platforms.insert(.watchOS)
            case "visionos": platforms.insert(.visionOS)
            default: break
            }
        }
        self = platforms
    }
}

/// A feature flag retrieved from CloudKit
///
/// Feature flags allow remote configuration of app features without app updates.
/// Flags are stored in CloudKit's public database and can be filtered by platform
/// and minimum app version.
///
/// ## CloudKit Record Structure
/// - `key`: String - unique flag identifier
/// - `enabled`: Int64 - 0/1 for boolean state
/// - `platform`: [String] - iOS, macOS, tvOS, watchOS, visionOS
/// - `minVersion`: String (optional) - minimum app version required
/// - `payload`: String (optional) - JSON config for complex flags
///
/// ## Usage
/// ```swift
/// let flag = FeatureFlag(
///     key: "newOnboarding",
///     isEnabled: true,
///     platforms: [.iOS, .macOS],
///     minVersion: "2.0.0"
/// )
/// ```
public struct FeatureFlag: Identifiable, Sendable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier for the feature flag
    public let id: String

    /// The unique key used to reference this flag
    public let key: String

    /// Whether the feature is enabled
    public var isEnabled: Bool

    /// Platforms where this flag applies
    public var platforms: FeatureFlagPlatform

    /// Minimum app version required (semantic versioning)
    public var minVersion: String?

    /// Optional JSON payload for complex configuration
    public var payload: String?

    /// CloudKit record ID for syncing
    public var recordID: String?

    /// Last modified date
    public var modifiedDate: Date

    /// Creation date
    public var createdDate: Date

    // MARK: - CloudKit Record Type

    /// CloudKit record type name
    public static let recordType = "FeatureFlag"

    /// CloudKit field keys
    public enum FieldKey: String {
        case key
        case enabled
        case platform
        case minVersion
        case payload
    }

    // MARK: - Initialization

    /// Creates a new feature flag
    ///
    /// - Parameters:
    ///   - key: Unique identifier for the flag
    ///   - isEnabled: Whether the feature is enabled
    ///   - platforms: Platforms where this flag applies (defaults to all)
    ///   - minVersion: Minimum app version required (optional)
    ///   - payload: JSON configuration payload (optional)
    public init(
        key: String,
        isEnabled: Bool = false,
        platforms: FeatureFlagPlatform = .all,
        minVersion: String? = nil,
        payload: String? = nil
    ) {
        self.id = key
        self.key = key
        self.isEnabled = isEnabled
        self.platforms = platforms
        self.minVersion = minVersion
        self.payload = payload
        self.recordID = nil
        self.modifiedDate = Date()
        self.createdDate = Date()
    }

    /// Creates a feature flag from a CloudKit record
    ///
    /// - Parameter record: CloudKit record containing flag data
    /// - Returns: FeatureFlag if record is valid, nil otherwise
    public init?(from record: CKRecord) {
        guard record.recordType == Self.recordType,
              let key = record[FieldKey.key.rawValue] as? String else {
            return nil
        }

        self.id = key
        self.key = key
        self.isEnabled = (record[FieldKey.enabled.rawValue] as? Int64 ?? 0) != 0

        if let platformStrings = record[FieldKey.platform.rawValue] as? [String] {
            self.platforms = FeatureFlagPlatform(platformStrings: platformStrings)
        } else {
            self.platforms = .all
        }

        self.minVersion = record[FieldKey.minVersion.rawValue] as? String
        self.payload = record[FieldKey.payload.rawValue] as? String
        self.recordID = record.recordID.recordName
        self.modifiedDate = record.modificationDate ?? Date()
        self.createdDate = record.creationDate ?? Date()
    }

    // MARK: - CloudKit Conversion

    /// Converts the feature flag to a CloudKit record
    ///
    /// - Parameter zoneID: Optional record zone ID
    /// - Returns: CKRecord representing this flag
    public func toRecord(in zoneID: CKRecordZone.ID? = nil) -> CKRecord {
        let recordID: CKRecord.ID
        if let zoneID = zoneID {
            recordID = CKRecord.ID(recordName: key, zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: key)
        }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[FieldKey.key.rawValue] = key
        record[FieldKey.enabled.rawValue] = isEnabled ? 1 : 0
        record[FieldKey.platform.rawValue] = platforms.platformStrings
        record[FieldKey.minVersion.rawValue] = minVersion
        record[FieldKey.payload.rawValue] = payload

        return record
    }

    // MARK: - Evaluation

    /// Checks if this flag is applicable to the current platform
    public var isApplicableToCurrentPlatform: Bool {
        platforms.contains(.current)
    }

    /// Checks if this flag is applicable to the given app version
    ///
    /// - Parameter appVersion: Current app version string
    /// - Returns: true if no minimum version required or app version meets requirement
    public func isApplicable(toVersion appVersion: String) -> Bool {
        guard let minVersion = minVersion else { return true }
        return compareVersions(appVersion, minVersion) >= 0
    }

    /// Evaluates the flag for the current context
    ///
    /// - Parameter appVersion: Current app version
    /// - Returns: true if flag is enabled and applicable
    public func evaluate(appVersion: String? = nil) -> Bool {
        guard isEnabled else { return false }
        guard isApplicableToCurrentPlatform else { return false }

        if let version = appVersion {
            guard isApplicable(toVersion: version) else { return false }
        }

        return true
    }

    // MARK: - Payload Helpers

    /// Decodes the payload as a specific type
    ///
    /// - Parameter type: The type to decode to
    /// - Returns: Decoded value or nil if decoding fails
    public func decodePayload<T: Decodable>(as type: T.Type) -> T? {
        guard let payload = payload,
              let data = payload.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(type, from: data)
    }

    /// Gets a value from the payload JSON
    ///
    /// - Parameter key: The key to look up
    /// - Returns: The value as the specified type, or nil
    public func payloadValue<T>(forKey key: String) -> T? {
        guard let payload = payload,
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json[key] as? T
    }

    // MARK: - Private Helpers

    /// Compares two semantic version strings
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(parts1.count, parts2.count)

        for i in 0..<maxLength {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0

            if p1 < p2 { return -1 }
            if p1 > p2 { return 1 }
        }

        return 0
    }
}

// MARK: - Default Flags

extension FeatureFlag {

    /// Creates a default flag value for when CloudKit is unavailable
    ///
    /// - Parameters:
    ///   - key: Flag key
    ///   - defaultValue: Default enabled state
    /// - Returns: A feature flag with default values
    public static func defaultFlag(key: String, defaultValue: Bool = false) -> FeatureFlag {
        FeatureFlag(key: key, isEnabled: defaultValue)
    }
}

// MARK: - CustomStringConvertible

extension FeatureFlag: CustomStringConvertible {
    public var description: String {
        let platformStr = platforms.platformStrings.joined(separator: ", ")
        let versionStr = minVersion.map { " (v\($0)+)" } ?? ""
        return "FeatureFlag(\(key): \(isEnabled ? "enabled" : "disabled") on [\(platformStr)]\(versionStr))"
    }
}
