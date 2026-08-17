//
//  FeatureRequest.swift
//  CloudAdminClient
//
//  Core feature request implementation
//

import Foundation
import CloudKit

/// Concrete implementation of a feature request
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct FeatureRequest: FeatureRequestable, Sendable, Codable, Identifiable, Hashable {
    
    // MARK: - Properties
    
    /// Unique identifier
    public let id: String
    
    /// CloudKit record identifier
    public let recordID: String
    
    /// Title of the feature request
    public let title: String
    
    /// Detailed description
    public let description: String
    
    /// Priority level
    public let priority: FeatureRequestPriority
    
    /// Current status
    public let status: FeatureRequestStatus
    
    /// Creation timestamp
    public let createdAt: Date
    
    /// Last update timestamp
    public let updatedAt: Date
    
    /// Optional user identifier
    public let userID: String?
    
    /// Category of the request
    public let category: FeatureRequestCategory
    
    /// Optional tags for categorization
    public let tags: [String]
    
    /// Optional contact email
    public let contactEmail: String?
    
    /// Number of votes/upvotes
    public let votes: Int
    
    /// Whether the request is public
    public let isPublic: Bool
    
    /// CloudKit record type
    public static let recordType = "FeatureRequest"

    /// CloudKit record type (instance accessor, kept for existing call sites).
    public var recordType: String { Self.recordType }

    /// CloudKit field names. Raw values are the stored schema — append, never rename.
    /// There is no `id` field; the record name is the identifier.
    public enum FieldKey: String, CaseIterable {
        case title
        case description
        case priority
        case status
        case createdAt
        case updatedAt
        case category
        case votes
        case isPublic
        case userID
        case contactEmail
        case tags
    }

    // MARK: - Initialization
    
    /// Initialize a new feature request
    /// - Parameters:
    ///   - title: Request title
    ///   - description: Detailed description
    ///   - priority: Priority level (default: medium)
    ///   - category: Request category (default: functionality)
    ///   - userID: Optional user identifier
    ///   - contactEmail: Optional contact email
    ///   - tags: Optional tags
    ///   - isPublic: Whether request is public (default: true)
    public init(
        title: String,
        description: String,
        priority: FeatureRequestPriority = .medium,
        category: FeatureRequestCategory = .functionality,
        userID: String? = nil,
        contactEmail: String? = nil,
        tags: [String] = [],
        isPublic: Bool = true
    ) {
        let now = Date()
        self.id = UUID().uuidString
        self.recordID = self.id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.priority = priority
        self.status = .submitted
        self.createdAt = now
        self.updatedAt = now
        self.userID = userID
        self.category = category
        self.tags = tags
        self.contactEmail = contactEmail
        self.votes = 0
        self.isPublic = isPublic
    }
    
    /// Initialize from existing data (for updates)
    /// - Parameters:
    ///   - id: Existing ID
    ///   - recordID: CloudKit record ID
    ///   - title: Request title
    ///   - description: Detailed description
    ///   - priority: Priority level
    ///   - status: Current status
    ///   - createdAt: Creation timestamp
    ///   - updatedAt: Update timestamp
    ///   - userID: Optional user identifier
    ///   - category: Request category
    ///   - tags: Optional tags
    ///   - contactEmail: Optional contact email
    ///   - votes: Number of votes
    ///   - isPublic: Whether request is public
    public init(
        id: String,
        recordID: String,
        title: String,
        description: String,
        priority: FeatureRequestPriority,
        status: FeatureRequestStatus,
        createdAt: Date,
        updatedAt: Date,
        userID: String? = nil,
        category: FeatureRequestCategory,
        tags: [String] = [],
        contactEmail: String? = nil,
        votes: Int = 0,
        isPublic: Bool = true
    ) {
        self.id = id
        self.recordID = recordID
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.priority = priority
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userID = userID
        self.category = category
        self.tags = tags
        self.contactEmail = contactEmail
        self.votes = votes
        self.isPublic = isPublic
    }
    
    // MARK: - CloudKit Integration
    
    /// Convert to CloudKit record with optional custom record type
    public func toCKRecord(recordType: String? = nil) throws -> CKRecord {
        let recordTypeName = recordType ?? self.recordType
        let record = CKRecord(recordType: recordTypeName, recordID: CKRecord.ID(recordName: recordID))

        record[FieldKey.title.rawValue] = title
        record[FieldKey.description.rawValue] = description
        record[FieldKey.priority.rawValue] = priority.rawValue
        record[FieldKey.status.rawValue] = status.rawValue
        record[FieldKey.createdAt.rawValue] = createdAt
        record[FieldKey.updatedAt.rawValue] = updatedAt
        record[FieldKey.category.rawValue] = category.rawValue
        record[FieldKey.votes.rawValue] = votes
        record[FieldKey.isPublic.rawValue] = isPublic ? 1 : 0

        if let userID = userID {
            record[FieldKey.userID.rawValue] = userID
        }

        if let contactEmail = contactEmail {
            record[FieldKey.contactEmail.rawValue] = contactEmail
        }

        if !tags.isEmpty {
            record[FieldKey.tags.rawValue] = tags
        }

        return record
    }
    
    /// Convert to CloudKit record using default record type
    public func toCKRecord() throws -> CKRecord {
        return try toCKRecord(recordType: nil)
    }
    
    /// Create from CloudKit record
    public static func fromCKRecord(_ record: CKRecord) throws -> FeatureRequest? {
        // Admin-written records may still carry a leftover `id` field; client-written
        // records use the record name only. Prefer the stored field when present.
        let id = (record["id"] as? String) ?? record.recordID.recordName
        guard let title = record[FieldKey.title.rawValue] as? String,
              let description = record[FieldKey.description.rawValue] as? String,
              let priorityRaw = record[FieldKey.priority.rawValue] as? String,
              let statusRaw = record[FieldKey.status.rawValue] as? String,
              let createdAt = record[FieldKey.createdAt.rawValue] as? Date,
              let updatedAt = record[FieldKey.updatedAt.rawValue] as? Date,
              let categoryRaw = record[FieldKey.category.rawValue] as? String,
              let priority = FeatureRequestPriority(rawValue: priorityRaw),
              let status = FeatureRequestStatus(rawValue: statusRaw),
              let category = FeatureRequestCategory(rawValue: categoryRaw) else {
            return nil
        }

        let userID = record[FieldKey.userID.rawValue] as? String
        let contactEmail = record[FieldKey.contactEmail.rawValue] as? String
        let tags = record[FieldKey.tags.rawValue] as? [String] ?? []
        let votes = record[FieldKey.votes.rawValue] as? Int ?? 0
        let isPublic = (record[FieldKey.isPublic.rawValue] as? Int ?? 1) == 1
        
        return FeatureRequest(
            id: id,
            recordID: record.recordID.recordName,
            title: title,
            description: description,
            priority: priority,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            userID: userID,
            category: category,
            tags: tags,
            contactEmail: contactEmail,
            votes: votes,
            isPublic: isPublic
        )
    }
    
    // MARK: - Update Methods
    
    /// Create an updated copy with new status
    /// - Parameter newStatus: The new status
    /// - Returns: Updated feature request
    public func withStatus(_ newStatus: FeatureRequestStatus) -> FeatureRequest {
        return FeatureRequest(
            id: id,
            recordID: recordID,
            title: title,
            description: description,
            priority: priority,
            status: newStatus,
            createdAt: createdAt,
            updatedAt: Date(),
            userID: userID,
            category: category,
            tags: tags,
            contactEmail: contactEmail,
            votes: votes,
            isPublic: isPublic
        )
    }
    
    /// Create an updated copy with new priority
    /// - Parameter newPriority: The new priority
    /// - Returns: Updated feature request
    public func withPriority(_ newPriority: FeatureRequestPriority) -> FeatureRequest {
        return FeatureRequest(
            id: id,
            recordID: recordID,
            title: title,
            description: description,
            priority: newPriority,
            status: status,
            createdAt: createdAt,
            updatedAt: Date(),
            userID: userID,
            category: category,
            tags: tags,
            contactEmail: contactEmail,
            votes: votes,
            isPublic: isPublic
        )
    }
    
    /// Create an updated copy with additional votes
    /// - Parameter additionalVotes: Number of votes to add
    /// - Returns: Updated feature request
    public func withAdditionalVotes(_ additionalVotes: Int) -> FeatureRequest {
        return FeatureRequest(
            id: id,
            recordID: recordID,
            title: title,
            description: description,
            priority: priority,
            status: status,
            createdAt: createdAt,
            updatedAt: Date(),
            userID: userID,
            category: category,
            tags: tags,
            contactEmail: contactEmail,
            votes: max(0, votes + additionalVotes),
            isPublic: isPublic
        )
    }
    
    /// Create an updated copy with new tags
    /// - Parameter newTags: The new tags
    /// - Returns: Updated feature request
    public func withTags(_ newTags: [String]) -> FeatureRequest {
        return FeatureRequest(
            id: id,
            recordID: recordID,
            title: title,
            description: description,
            priority: priority,
            status: status,
            createdAt: createdAt,
            updatedAt: Date(),
            userID: userID,
            category: category,
            tags: newTags,
            contactEmail: contactEmail,
            votes: votes,
            isPublic: isPublic
        )
    }
    
    // MARK: - Validation
    
    /// Validate this feature request
    /// - Returns: Validation result
    public func validate() -> FeatureRequestValidationResult {
        return FeatureRequestValidator.validate(self)
    }
    
    // MARK: - Hashable & Equatable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: FeatureRequest, rhs: FeatureRequest) -> Bool {
        return lhs.id == rhs.id
    }
}