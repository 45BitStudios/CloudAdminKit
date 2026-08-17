//
//  FeatureRequestService.swift
//  CloudAdminClient
//
//  Direct-CloudKit service for managing feature requests. Rewritten from Ikigai's
//  CloudKitService-backed version to talk to CKContainer directly with async/throws.
//

import CloudKit
import Foundation

/// Errors thrown by ``FeatureRequestService``.
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public enum FeatureRequestServiceError: Error, Sendable {
    /// No request exists for the given ID.
    case recordNotFound
    /// The request failed validation; carries the human-readable reasons.
    case validationFailed([String])
    /// A CloudKit fetch/save/delete failed; carries the underlying error.
    case cloudKit(Error)
}

/// Manages feature requests in a managed app's CloudKit database.
///
/// Talks to `CKContainer(identifier:).publicCloudDatabase` directly (no Ikigai
/// `CloudKitService`). Every mutating method returns the affected value or throws
/// ``FeatureRequestServiceError``.
///
// ua-debt: Ikigai's pre-convergence IkigaiFeatureRequests had bulk/tag methods
// (submitBatch, bulkUpdateStatus, bulkUpdatePriority, bulkDelete, addTags, removeTags,
// fetchByTag, getAllTags) that were not ported here — nothing calls them today. Upgrade
// path: port from Ikigai's pre-deletion git history if a future consumer needs bulk ops.
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
@MainActor
@Observable
public final class FeatureRequestService {
    /// Whether an operation is currently in flight.
    public private(set) var isProcessing = false

    /// Timestamp of the last successful mutation.
    public private(set) var lastOperationDate: Date?

    private let database: CKDatabase
    private var requestCache: [String: FeatureRequest] = [:]
    private let maxCacheSize = 100

    /// Creates a service bound to a container's database.
    ///
    /// - Parameters:
    ///   - containerIdentifier: The CloudKit container (e.g. `iCloud.com.acme.app`).
    ///   - usePublicDatabase: Whether to target the public database (the default and the
    ///     usual choice for community feature requests).
    public init(containerIdentifier: String, usePublicDatabase: Bool = true) {
        let container = CKContainer(identifier: containerIdentifier)
        database = usePublicDatabase ? container.publicCloudDatabase : container.privateCloudDatabase
    }

    // MARK: - Core operations

    /// Validates and saves a new request, returning the stored value.
    public func submit(_ request: FeatureRequest) async throws -> FeatureRequest {
        let validation = request.validate()
        guard validation.isValid else {
            throw FeatureRequestServiceError.validationFailed(validation.errors)
        }
        isProcessing = true
        defer { isProcessing = false }
        let saved = try await save(request)
        lastOperationDate = Date()
        return saved
    }

    /// Fetches a request by ID, or `nil` if it doesn't exist. Serves from cache when warm.
    public func fetch(_ requestID: String) async throws -> FeatureRequest? {
        if let cached = requestCache[requestID] {
            return cached
        }
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: requestID))
            guard let request = try FeatureRequest.fromCKRecord(record) else { return nil }
            cache(request)
            return request
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw FeatureRequestServiceError.cloudKit(error)
        }
    }

    /// Fetches requests matching the optional filters.
    ///
    /// - Parameters:
    ///   - status: Restrict to requests in this status, if given.
    ///   - priority: Restrict to requests at this priority, if given.
    ///   - category: Restrict to requests in this category, if given.
    ///   - userID: Restrict to requests submitted by this user, if given.
    ///   - limit: Maximum number of requests to return.
    ///   - includePrivate: When `false`, only requests marked public are returned.
    public func fetchAll(
        status: FeatureRequestStatus? = nil,
        priority: FeatureRequestPriority? = nil,
        category: FeatureRequestCategory? = nil,
        userID: String? = nil,
        limit: Int = 50,
        includePrivate: Bool = false
    ) async throws -> [FeatureRequest] {
        var predicates: [NSPredicate] = []
        if let status {
            predicates.append(NSPredicate(format: "%K == %@", FeatureRequest.FieldKey.status.rawValue, status.rawValue))
        }
        if let priority {
            predicates.append(NSPredicate(format: "%K == %@", FeatureRequest.FieldKey.priority.rawValue, priority.rawValue))
        }
        if let category {
            predicates.append(NSPredicate(format: "%K == %@", FeatureRequest.FieldKey.category.rawValue, category.rawValue))
        }
        if let userID {
            predicates.append(NSPredicate(format: "%K == %@", FeatureRequest.FieldKey.userID.rawValue, userID))
        }
        if !includePrivate {
            predicates.append(NSPredicate(format: "%K == %@", FeatureRequest.FieldKey.isPublic.rawValue, NSNumber(value: true)))
        }
        let predicate = predicates.isEmpty
            ? NSPredicate(value: true)
            : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let requests = try await query(predicate, limit: limit)
        requests.forEach(cache)
        return requests
    }

    /// Moves a request to a new status, returning the updated value.
    public func updateStatus(for requestID: String, to newStatus: FeatureRequestStatus) async throws -> FeatureRequest {
        try await mutate(requestID) { $0.withStatus(newStatus) }
    }

    /// Changes a request's priority, returning the updated value.
    public func updatePriority(for requestID: String, to newPriority: FeatureRequestPriority) async throws -> FeatureRequest {
        try await mutate(requestID) { $0.withPriority(newPriority) }
    }

    /// Adds (or, when negative, removes) votes, returning the updated value.
    public func addVotes(to requestID: String, votes: Int) async throws -> FeatureRequest {
        try await mutate(requestID) { $0.withAdditionalVotes(votes) }
    }

    /// Deletes a request, returning its ID.
    @discardableResult
    public func delete(_ requestID: String) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await database.deleteRecord(withID: CKRecord.ID(recordName: requestID))
        } catch {
            throw FeatureRequestServiceError.cloudKit(error)
        }
        requestCache.removeValue(forKey: requestID)
        lastOperationDate = Date()
        return requestID
    }

    /// Full-text search over titles and descriptions.
    ///
    /// `title` is QUERYABLE SEARCHABLE; `description` is SEARCHABLE only. CloudKit
    /// rejects `CONTAINS` on a non-QUERYABLE field, so the server query is limited
    /// to public records (`isPublic` is QUERYABLE) and both fields are filtered
    /// client-side.
    public func search(_ searchText: String, limit: Int = 20) async throws -> [FeatureRequest] {
        guard let trimmed = Self.normalizedSearchQuery(searchText) else { return [] }
        let candidates = try await query(Self.searchCandidatePredicate(), limit: max(limit * 10, 100))
        return Array(candidates.filter { Self.matchesSearch($0, query: trimmed) }.prefix(limit))
    }

    /// `nil` when the query is empty or whitespace — callers must not hit CloudKit.
    public static func normalizedSearchQuery(_ searchText: String) -> String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// CloudKit predicate for search candidates. Uses only QUERYABLE fields.
    public static func searchCandidatePredicate() -> NSPredicate {
        NSPredicate(
            format: "%K == %@",
            FeatureRequest.FieldKey.isPublic.rawValue,
            NSNumber(value: true)
        )
    }

    /// Title or description substring match (case-insensitive).
    public static func matchesSearch(_ request: FeatureRequest, query: String) -> Bool {
        request.title.localizedCaseInsensitiveContains(query)
            || request.description.localizedCaseInsensitiveContains(query)
    }

    /// Aggregate statistics computed from up to 1000 requests.
    public func getStatistics() async throws -> FeatureRequestStatistics {
        let requests = try await fetchAll(limit: 1000, includePrivate: true)
        return FeatureRequestStatistics(from: requests)
    }

    // MARK: - Private helpers

    private func mutate(
        _ requestID: String,
        _ transform: (FeatureRequest) -> FeatureRequest
    ) async throws -> FeatureRequest {
        isProcessing = true
        defer { isProcessing = false }
        guard let existing = try await fetch(requestID) else {
            throw FeatureRequestServiceError.recordNotFound
        }
        let saved = try await save(transform(existing))
        lastOperationDate = Date()
        return saved
    }

    private func save(_ request: FeatureRequest) async throws -> FeatureRequest {
        do {
            let record = try request.toCKRecord()
            let saved = try await database.save(record)
            guard let stored = try FeatureRequest.fromCKRecord(saved) else { return request }
            cache(stored)
            return stored
        } catch let error as FeatureRequestServiceError {
            throw error
        } catch {
            throw FeatureRequestServiceError.cloudKit(error)
        }
    }

    private func query(_ predicate: NSPredicate, limit: Int) async throws -> [FeatureRequest] {
        let query = CKQuery(recordType: FeatureRequest.recordType, predicate: predicate)
        do {
            let (matches, _) = try await database.records(matching: query, resultsLimit: limit)
            return try matches.compactMap { _, result in
                try FeatureRequest.fromCKRecord(try result.get())
            }
        } catch {
            throw FeatureRequestServiceError.cloudKit(error)
        }
    }

    private func cache(_ request: FeatureRequest) {
        if requestCache.count >= maxCacheSize, let firstKey = requestCache.keys.first {
            requestCache.removeValue(forKey: firstKey)
        }
        requestCache[request.id] = request
    }
}
