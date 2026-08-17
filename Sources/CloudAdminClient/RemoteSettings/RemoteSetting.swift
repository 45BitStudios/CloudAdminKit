//
//  RemoteSetting.swift
//  CloudAdminClient
//
//  Remote setting model for CloudKit-based configuration system
//

import Foundation
import CloudKit

// MARK: - Setting Value Type

/// Represents the type of a remote setting value
public enum SettingValueType: String, Sendable, Codable, CaseIterable {
    case string = "string"
    case bool = "bool"
    case int = "int"
    case double = "double"
    case url = "url"

    /// Display name for the type
    public var displayName: String {
        switch self {
        case .string: return "String"
        case .bool: return "Boolean"
        case .int: return "Integer"
        case .double: return "Double"
        case .url: return "URL"
        }
    }
}

// MARK: - Setting Value

/// A strongly-typed setting value with associated data
///
/// `SettingValue` provides type-safe access to remote configuration values.
/// Each case holds the appropriate Swift type for the setting.
///
/// ## Usage
/// ```swift
/// let value = SettingValue.string("hello@example.com")
/// if case .string(let email) = value {
///     print(email)
/// }
/// ```
public enum SettingValue: Sendable, Codable, Hashable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case url(URL)

    /// The type of this value
    public var type: SettingValueType {
        switch self {
        case .string: return .string
        case .bool: return .bool
        case .int: return .int
        case .double: return .double
        case .url: return .url
        }
    }

    /// String representation of the value
    public var stringRepresentation: String {
        switch self {
        case .string(let value): return value
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .url(let value): return value.absoluteString
        }
    }

    // MARK: - Type-Safe Accessors

    /// Gets the value as a String, or nil if not a string type
    public var asString: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Gets the value as a Bool, or nil if not a bool type
    public var asBool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// Gets the value as an Int, or nil if not an int type
    public var asInt: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    /// Gets the value as a Double, or nil if not a double type
    public var asDouble: Double? {
        if case .double(let value) = self { return value }
        return nil
    }

    /// Gets the value as a URL, or nil if not a url type
    public var asURL: URL? {
        if case .url(let value) = self { return value }
        return nil
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SettingValueType.self, forKey: .type)

        switch type {
        case .string:
            let value = try container.decode(String.self, forKey: .value)
            self = .string(value)
        case .bool:
            let value = try container.decode(Bool.self, forKey: .value)
            self = .bool(value)
        case .int:
            let value = try container.decode(Int.self, forKey: .value)
            self = .int(value)
        case .double:
            let value = try container.decode(Double.self, forKey: .value)
            self = .double(value)
        case .url:
            let urlString = try container.decode(String.self, forKey: .value)
            guard let url = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Invalid URL string")
            }
            self = .url(url)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)

        switch self {
        case .string(let value):
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(value, forKey: .value)
        case .url(let value):
            try container.encode(value.absoluteString, forKey: .value)
        }
    }
}

// MARK: - Remote Setting

/// A remote setting retrieved from CloudKit
///
/// Remote settings allow dynamic app configuration without app updates.
/// Settings are stored in CloudKit's public database with type-safe values.
///
/// ## CloudKit Record Structure
/// - `key`: String - unique setting identifier (queryable/sortable)
/// - `valueType`: String - "string", "bool", "int", "double", "url"
/// - `stringValue`: String (optional) - value for string/url types
/// - `intValue`: Int64 (optional) - value for int/bool types
/// - `doubleValue`: Double (optional) - value for double types
/// - `description`: String (optional) - dashboard documentation
///
/// ## Usage
/// ```swift
/// let setting = RemoteSetting(
///     key: "supportEmail",
///     value: .string("help@example.com"),
///     description: "Customer support email address"
/// )
/// ```
public struct RemoteSetting: Identifiable, Sendable, Codable, Hashable {

    // MARK: - Properties

    /// Unique identifier (same as key)
    public let id: String

    /// The unique key for this setting
    public let key: String

    /// The strongly-typed value
    public var value: SettingValue

    /// Optional description for dashboard clarity
    public var settingDescription: String?

    /// CloudKit record ID for syncing
    public var recordID: String?

    /// Last modified date
    public var modifiedDate: Date

    /// Creation date
    public var createdDate: Date

    // MARK: - CloudKit Record Type

    /// CloudKit record type name
    public static let recordType = "RemoteSetting"

    /// CloudKit field keys
    public enum FieldKey: String, CaseIterable {
        case key
        case valueType
        case stringValue
        case intValue
        case doubleValue
        case description
    }

    // MARK: - Initialization

    /// Creates a new remote setting
    ///
    /// - Parameters:
    ///   - key: Unique identifier for the setting
    ///   - value: The setting value
    ///   - description: Optional description
    public init(
        key: String,
        value: SettingValue,
        description: String? = nil
    ) {
        self.id = key
        self.key = key
        self.value = value
        self.settingDescription = description
        self.recordID = nil
        self.modifiedDate = Date()
        self.createdDate = Date()
    }

    /// Creates a remote setting from a CloudKit record
    ///
    /// - Parameter record: CloudKit record containing setting data
    /// - Returns: RemoteSetting if record is valid, nil otherwise
    public init?(from record: CKRecord) {
        guard record.recordType == Self.recordType,
              let key = record[FieldKey.key.rawValue] as? String,
              let valueTypeString = record[FieldKey.valueType.rawValue] as? String,
              let valueType = SettingValueType(rawValue: valueTypeString) else {
            return nil
        }

        self.id = key
        self.key = key
        self.settingDescription = record[FieldKey.description.rawValue] as? String
        self.recordID = record.recordID.recordName
        self.modifiedDate = record.modificationDate ?? Date()
        self.createdDate = record.creationDate ?? Date()

        // Parse value based on type
        switch valueType {
        case .string:
            guard let stringValue = record[FieldKey.stringValue.rawValue] as? String else {
                return nil
            }
            self.value = .string(stringValue)

        case .bool:
            guard let intValue = record[FieldKey.intValue.rawValue] as? Int64 else {
                return nil
            }
            self.value = .bool(intValue != 0)

        case .int:
            guard let intValue = record[FieldKey.intValue.rawValue] as? Int64 else {
                return nil
            }
            self.value = .int(Int(intValue))

        case .double:
            guard let doubleValue = record[FieldKey.doubleValue.rawValue] as? Double else {
                return nil
            }
            self.value = .double(doubleValue)

        case .url:
            guard let stringValue = record[FieldKey.stringValue.rawValue] as? String,
                  let url = URL(string: stringValue) else {
                return nil
            }
            self.value = .url(url)
        }
    }

    // MARK: - CloudKit Conversion

    /// Converts the remote setting to a CloudKit record
    ///
    /// - Parameter zoneID: Optional record zone ID
    /// - Returns: CKRecord representing this setting
    public func toRecord(in zoneID: CKRecordZone.ID? = nil) -> CKRecord {
        let recordID: CKRecord.ID
        if let zoneID = zoneID {
            recordID = CKRecord.ID(recordName: key, zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: key)
        }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[FieldKey.key.rawValue] = key
        record[FieldKey.valueType.rawValue] = value.type.rawValue
        record[FieldKey.description.rawValue] = settingDescription

        // Set appropriate value field
        switch value {
        case .string(let stringValue):
            record[FieldKey.stringValue.rawValue] = stringValue
        case .bool(let boolValue):
            record[FieldKey.intValue.rawValue] = boolValue ? 1 : 0
        case .int(let intValue):
            record[FieldKey.intValue.rawValue] = Int64(intValue)
        case .double(let doubleValue):
            record[FieldKey.doubleValue.rawValue] = doubleValue
        case .url(let urlValue):
            record[FieldKey.stringValue.rawValue] = urlValue.absoluteString
        }

        return record
    }
}

// MARK: - Convenience Initializers

extension RemoteSetting {

    /// Creates a string setting
    public static func string(_ key: String, value: String, description: String? = nil) -> RemoteSetting {
        RemoteSetting(key: key, value: .string(value), description: description)
    }

    /// Creates a bool setting
    public static func bool(_ key: String, value: Bool, description: String? = nil) -> RemoteSetting {
        RemoteSetting(key: key, value: .bool(value), description: description)
    }

    /// Creates an int setting
    public static func int(_ key: String, value: Int, description: String? = nil) -> RemoteSetting {
        RemoteSetting(key: key, value: .int(value), description: description)
    }

    /// Creates a double setting
    public static func double(_ key: String, value: Double, description: String? = nil) -> RemoteSetting {
        RemoteSetting(key: key, value: .double(value), description: description)
    }

    /// Creates a URL setting
    public static func url(_ key: String, value: URL, description: String? = nil) -> RemoteSetting {
        RemoteSetting(key: key, value: .url(value), description: description)
    }
}

// MARK: - CustomStringConvertible

extension RemoteSetting: CustomStringConvertible {
    public var description: String {
        "RemoteSetting(\(key): \(value.type.displayName) = \(value.stringRepresentation))"
    }
}

// MARK: - Setting Requirement

/// Defines whether a setting is required or optional
public enum SettingRequirement: Sendable {
    /// Setting must exist - fatal error in debug if missing
    case required
    /// Setting is optional - uses default value if missing
    case optional
}
