//
//  FeatureRequestable.swift
//  CloudAdminClient
//
//  Feature request protocol and types
//

import Foundation
import CloudKit

/// Protocol for feature request objects
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public protocol FeatureRequestable: Sendable {
    /// Title of the feature request
    var title: String { get }
    
    /// Detailed description of the feature request
    var description: String { get }
    
    /// Priority level of the request
    var priority: FeatureRequestPriority { get }
    
    /// Current status of the request
    var status: FeatureRequestStatus { get }
    
    /// When the request was created
    var createdAt: Date { get }
    
    /// When the request was last updated
    var updatedAt: Date { get }
    
    /// Optional user identifier
    var userID: String? { get }
}

/// Priority levels for feature requests
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public enum FeatureRequestPriority: String, CaseIterable, Sendable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
    
    /// Numeric value for sorting
    public var sortValue: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }
    
    /// Display name
    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
    
    /// Description for UI
    public var description: String {
        switch self {
        case .low: return "Nice to have feature"
        case .medium: return "Important improvement"
        case .high: return "High impact feature"
        case .critical: return "Critical functionality"
        }
    }
}

/// Status of feature requests
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public enum FeatureRequestStatus: String, CaseIterable, Sendable, Codable {
    case submitted = "submitted"
    case reviewing = "reviewing"
    case approved = "approved"
    case inProgress = "in_progress"
    case completed = "completed"
    case rejected = "rejected"
    case onHold = "on_hold"
    
    /// Display name
    public var displayName: String {
        switch self {
        case .submitted: return "Submitted"
        case .reviewing: return "Under Review"
        case .approved: return "Approved"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .rejected: return "Rejected"
        case .onHold: return "On Hold"
        }
    }
    
    /// Description for UI
    public var description: String {
        switch self {
        case .submitted: return "Request has been submitted"
        case .reviewing: return "Request is being reviewed"
        case .approved: return "Request has been approved for development"
        case .inProgress: return "Request is currently being developed"
        case .completed: return "Request has been implemented"
        case .rejected: return "Request has been rejected"
        case .onHold: return "Request development is on hold"
        }
    }
    
    /// Whether this status indicates the request is active
    public var isActive: Bool {
        switch self {
        case .submitted, .reviewing, .approved, .inProgress:
            return true
        case .completed, .rejected, .onHold:
            return false
        }
    }
    
    /// Whether this status indicates completion
    public var isCompleted: Bool {
        return self == .completed
    }
}

/// Category for feature requests
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public enum FeatureRequestCategory: String, CaseIterable, Sendable, Codable {
    case userInterface = "user_interface"
    case performance = "performance"
    case functionality = "functionality"
    case integration = "integration"
    case accessibility = "accessibility"
    case security = "security"
    case documentation = "documentation"
    case bugFix = "bug_fix"
    case other = "other"
    
    /// Display name
    public var displayName: String {
        switch self {
        case .userInterface: return "User Interface"
        case .performance: return "Performance"
        case .functionality: return "Functionality"
        case .integration: return "Integration"
        case .accessibility: return "Accessibility"
        case .security: return "Security"
        case .documentation: return "Documentation"
        case .bugFix: return "Bug Fix"
        case .other: return "Other"
        }
    }
}

/// Validation result for feature requests
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public enum FeatureRequestValidationResult: Sendable {
    case valid
    case invalid([String])
    
    /// Whether the validation passed
    public var isValid: Bool {
        switch self {
        case .valid: return true
        case .invalid: return false
        }
    }
    
    /// Error messages if validation failed
    public var errors: [String] {
        switch self {
        case .valid: return []
        case .invalid(let errors): return errors
        }
    }
}

/// Feature request validation rules
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct FeatureRequestValidator: Sendable {
    
    /// Minimum title length
    public static let minTitleLength = 5
    
    /// Maximum title length
    public static let maxTitleLength = 100
    
    /// Minimum description length
    public static let minDescriptionLength = 10
    
    /// Maximum description length
    public static let maxDescriptionLength = 1000
    
    /// Validate a feature request
    /// - Parameter request: The feature request to validate
    /// - Returns: Validation result
    public static func validate<T: FeatureRequestable>(_ request: T) -> FeatureRequestValidationResult {
        var errors: [String] = []
        
        // Title validation
        if request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Title cannot be empty")
        } else if request.title.count < minTitleLength {
            errors.append("Title must be at least \(minTitleLength) characters")
        } else if request.title.count > maxTitleLength {
            errors.append("Title cannot exceed \(maxTitleLength) characters")
        }
        
        // Description validation
        if request.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Description cannot be empty")
        } else if request.description.count < minDescriptionLength {
            errors.append("Description must be at least \(minDescriptionLength) characters")
        } else if request.description.count > maxDescriptionLength {
            errors.append("Description cannot exceed \(maxDescriptionLength) characters")
        }
        
        // Date validation
        if request.createdAt > Date() {
            errors.append("Creation date cannot be in the future")
        }
        
        if request.updatedAt < request.createdAt {
            errors.append("Update date cannot be before creation date")
        }
        
        return errors.isEmpty ? .valid : .invalid(errors)
    }
}