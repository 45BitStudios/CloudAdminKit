//
//  AnalyticsEvent.swift
//  CloudAdminClient
//
//  Analytics event models for CloudKit-based analytics system
//

import Foundation
import CloudKit

// MARK: - Analytics Event Type

/// Types of analytics events that can be tracked
public enum AnalyticsEventType: String, CaseIterable, Codable, Sendable {
    case screenView = "screen_view"
    case buttonTap = "button_tap"
    case appLaunch = "app_launch"
    case appBackground = "app_background"
    case appTerminate = "app_terminate"
    case error = "error"
    case purchase = "purchase"
    case featureUsed = "feature_used"
    case onboardingStep = "onboarding_step"
    case search = "search"
    case share = "share"
    case notification = "notification"
    case deepLink = "deep_link"
    case custom = "custom"

    /// Display name for the event type
    public var displayName: String {
        switch self {
        case .screenView: return "Screen View"
        case .buttonTap: return "Button Tap"
        case .appLaunch: return "App Launch"
        case .appBackground: return "App Background"
        case .appTerminate: return "App Terminate"
        case .error: return "Error"
        case .purchase: return "Purchase"
        case .featureUsed: return "Feature Used"
        case .onboardingStep: return "Onboarding Step"
        case .search: return "Search"
        case .share: return "Share"
        case .notification: return "Notification"
        case .deepLink: return "Deep Link"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Network Type

/// Network connection type
public enum NetworkType: String, Codable, Sendable {
    case wifi
    case cellular
    case offline
    case unknown
}

// MARK: - Device Info

/// Information about the device and app environment
public struct DeviceInfo: Codable, Sendable, Hashable {
    /// Device model identifier (e.g., "iPhone15,2")
    public let model: String
    /// Operating system version (e.g., "18.0")
    public let osVersion: String
    /// App version string (e.g., "1.2.0")
    public let appVersion: String
    /// Build number string (e.g., "42")
    public let buildNumber: String
    /// Locale identifier (e.g., "en_US")
    public let locale: String
    /// Timezone identifier (e.g., "America/Chicago")
    public let timezone: String
    /// Screen scale factor (e.g., 3.0 for 3x displays)
    public let screenScale: Double
    /// Whether the device is in low power mode
    public let isLowPowerMode: Bool
    /// Current network connection type
    public let networkType: NetworkType

    /// Creates device information
    ///
    /// - Parameters:
    ///   - model: Device model identifier
    ///   - osVersion: Operating system version
    ///   - appVersion: App version string
    ///   - buildNumber: Build number
    ///   - locale: Locale identifier
    ///   - timezone: Timezone identifier
    ///   - screenScale: Screen scale factor
    ///   - isLowPowerMode: Low power mode status
    ///   - networkType: Network connection type
    public init(
        model: String,
        osVersion: String,
        appVersion: String,
        buildNumber: String,
        locale: String,
        timezone: String,
        screenScale: Double,
        isLowPowerMode: Bool,
        networkType: NetworkType
    ) {
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.locale = locale
        self.timezone = timezone
        self.screenScale = screenScale
        self.isLowPowerMode = isLowPowerMode
        self.networkType = networkType
    }
}

// MARK: - Error Info

/// Information about an error event
public struct ErrorInfo: Codable, Sendable, Hashable {
    public let domain: String
    public let code: Int
    public let message: String
    public let stackTrace: String?
    public let isFatal: Bool

    public init(
        domain: String,
        code: Int,
        message: String,
        stackTrace: String? = nil,
        isFatal: Bool = false
    ) {
        self.domain = domain
        self.code = code
        self.message = message
        self.stackTrace = stackTrace
        self.isFatal = isFatal
    }

    /// Creates ErrorInfo from a Swift Error
    public init(from error: Error, isFatal: Bool = false) {
        let nsError = error as NSError
        self.domain = nsError.domain
        self.code = nsError.code
        self.message = error.localizedDescription
        self.stackTrace = Thread.callStackSymbols.joined(separator: "\n")
        self.isFatal = isFatal
    }
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for flexible properties dictionary
public struct AnyCodable: Codable, Hashable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable cannot decode value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "AnyCodable cannot encode value of type \(type(of: value))"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case is (NSNull, NSNull):
            return true
        case let (lhs as Bool, rhs as Bool):
            return lhs == rhs
        case let (lhs as Int, rhs as Int):
            return lhs == rhs
        case let (lhs as Double, rhs as Double):
            return lhs == rhs
        case let (lhs as String, rhs as String):
            return lhs == rhs
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch value {
        case is NSNull:
            hasher.combine(0)
        case let bool as Bool:
            hasher.combine(bool)
        case let int as Int:
            hasher.combine(int)
        case let double as Double:
            hasher.combine(double)
        case let string as String:
            hasher.combine(string)
        default:
            hasher.combine(1)
        }
    }
}

// MARK: - Analytics Event

/// An analytics event to be tracked and uploaded to CloudKit
public struct AnalyticsEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let userID: String?
    public let anonymousID: String
    public let eventType: AnalyticsEventType
    public let eventName: String?
    public let timestamp: Date
    public let deviceInfo: DeviceInfo
    public let latitude: Double?
    public let longitude: Double?
    public let screenName: String?
    public let previousScreenName: String?
    public let duration: TimeInterval?
    public let properties: [String: AnyCodable]
    public let errorInfo: ErrorInfo?

    // MARK: - CloudKit Record Type

    /// CloudKit record type name
    public static let recordType = "AnalyticsEvent"

    /// CloudKit field keys
    public enum FieldKey: String {
        case id
        case sessionID
        case userID
        case anonymousID
        case eventType
        case eventName
        case timestamp
        case deviceInfo
        case latitude
        case longitude
        case screenName
        case previousScreenName
        case duration
        case properties
        case errorInfo
    }

    // MARK: - Initialization

    /// Creates a new analytics event
    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        userID: String? = nil,
        anonymousID: String,
        eventType: AnalyticsEventType,
        eventName: String? = nil,
        timestamp: Date = Date(),
        deviceInfo: DeviceInfo,
        latitude: Double? = nil,
        longitude: Double? = nil,
        screenName: String? = nil,
        previousScreenName: String? = nil,
        duration: TimeInterval? = nil,
        properties: [String: AnyCodable] = [:],
        errorInfo: ErrorInfo? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.userID = userID
        self.anonymousID = anonymousID
        self.eventType = eventType
        self.eventName = eventName
        self.timestamp = timestamp
        self.deviceInfo = deviceInfo
        self.latitude = latitude
        self.longitude = longitude
        self.screenName = screenName
        self.previousScreenName = previousScreenName
        self.duration = duration
        self.properties = properties
        self.errorInfo = errorInfo
    }

    // MARK: - CloudKit Conversion

    /// Converts the event to a CloudKit record
    public func toRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)

        record[FieldKey.id.rawValue] = id.uuidString
        record[FieldKey.sessionID.rawValue] = sessionID.uuidString
        record[FieldKey.userID.rawValue] = userID
        record[FieldKey.anonymousID.rawValue] = anonymousID
        record[FieldKey.eventType.rawValue] = eventType.rawValue
        record[FieldKey.eventName.rawValue] = eventName
        record[FieldKey.timestamp.rawValue] = timestamp
        record[FieldKey.latitude.rawValue] = latitude
        record[FieldKey.longitude.rawValue] = longitude
        record[FieldKey.screenName.rawValue] = screenName
        record[FieldKey.previousScreenName.rawValue] = previousScreenName
        record[FieldKey.duration.rawValue] = duration

        // Encode complex types as JSON strings
        if let deviceInfoData = try? JSONEncoder().encode(deviceInfo),
           let deviceInfoString = String(data: deviceInfoData, encoding: .utf8) {
            record[FieldKey.deviceInfo.rawValue] = deviceInfoString
        }

        if !properties.isEmpty,
           let propertiesData = try? JSONEncoder().encode(properties),
           let propertiesString = String(data: propertiesData, encoding: .utf8) {
            record[FieldKey.properties.rawValue] = propertiesString
        }

        if let errorInfo = errorInfo,
           let errorInfoData = try? JSONEncoder().encode(errorInfo),
           let errorInfoString = String(data: errorInfoData, encoding: .utf8) {
            record[FieldKey.errorInfo.rawValue] = errorInfoString
        }

        return record
    }

    /// Creates an event from a CloudKit record
    public init?(from record: CKRecord) {
        guard record.recordType == Self.recordType,
              let idString = record[FieldKey.id.rawValue] as? String,
              let id = UUID(uuidString: idString),
              let sessionIDString = record[FieldKey.sessionID.rawValue] as? String,
              let sessionID = UUID(uuidString: sessionIDString),
              let anonymousID = record[FieldKey.anonymousID.rawValue] as? String,
              let eventTypeString = record[FieldKey.eventType.rawValue] as? String,
              let eventType = AnalyticsEventType(rawValue: eventTypeString),
              let timestamp = record[FieldKey.timestamp.rawValue] as? Date,
              let deviceInfoString = record[FieldKey.deviceInfo.rawValue] as? String,
              let deviceInfoData = deviceInfoString.data(using: .utf8),
              let deviceInfo = try? JSONDecoder().decode(DeviceInfo.self, from: deviceInfoData)
        else {
            return nil
        }

        self.id = id
        self.sessionID = sessionID
        self.userID = record[FieldKey.userID.rawValue] as? String
        self.anonymousID = anonymousID
        self.eventType = eventType
        self.eventName = record[FieldKey.eventName.rawValue] as? String
        self.timestamp = timestamp
        self.deviceInfo = deviceInfo
        self.latitude = record[FieldKey.latitude.rawValue] as? Double
        self.longitude = record[FieldKey.longitude.rawValue] as? Double
        self.screenName = record[FieldKey.screenName.rawValue] as? String
        self.previousScreenName = record[FieldKey.previousScreenName.rawValue] as? String
        self.duration = record[FieldKey.duration.rawValue] as? Double

        // Decode properties
        if let propertiesString = record[FieldKey.properties.rawValue] as? String,
           let propertiesData = propertiesString.data(using: .utf8),
           let properties = try? JSONDecoder().decode([String: AnyCodable].self, from: propertiesData) {
            self.properties = properties
        } else {
            self.properties = [:]
        }

        // Decode error info
        if let errorInfoString = record[FieldKey.errorInfo.rawValue] as? String,
           let errorInfoData = errorInfoString.data(using: .utf8),
           let errorInfo = try? JSONDecoder().decode(ErrorInfo.self, from: errorInfoData) {
            self.errorInfo = errorInfo
        } else {
            self.errorInfo = nil
        }
    }
}

// MARK: - CustomStringConvertible

extension AnalyticsEvent: CustomStringConvertible {
    public var description: String {
        var desc = "AnalyticsEvent(\(eventType.rawValue)"
        if let name = eventName {
            desc += ": \(name)"
        }
        if let screen = screenName {
            desc += " on \(screen)"
        }
        desc += ")"
        return desc
    }
}
