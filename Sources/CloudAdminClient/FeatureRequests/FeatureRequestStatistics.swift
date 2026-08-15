//
//  FeatureRequestStatistics.swift
//  CloudAdminClient
//
//  Aggregate statistics computed over a set of feature requests. Pure value type;
//  no CloudKit. Split out of FeatureRequestService.swift to keep files small.
//

import Foundation

/// Statistics about feature requests
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public struct FeatureRequestStatistics: Sendable {
    public let totalRequests: Int
    public let requestsByStatus: [FeatureRequestStatus: Int]
    public let requestsByPriority: [FeatureRequestPriority: Int]
    public let requestsByCategory: [FeatureRequestCategory: Int]
    public let totalVotes: Int
    public let averageVotesPerRequest: Double
    public let mostRecentRequest: Date?
    public let oldestRequest: Date?

    /// Time series data for trend analysis
    public let dailyTrend: [Date: Int]

    /// Weekly submission counts
    public let weeklyTrend: [Date: Int]

    /// Top tags by usage
    public let topTags: [(tag: String, count: Int)]

    /// Completion rate (implemented + rejected / total)
    public let completionRate: Double

    /// Average time to completion (for implemented requests)
    public let averageCompletionDays: Double?

    /// Computes statistics from a set of requests.
    public init(from requests: [FeatureRequest]) {
        self.totalRequests = requests.count

        // Group by status
        var statusCounts: [FeatureRequestStatus: Int] = [:]
        for status in FeatureRequestStatus.allCases {
            statusCounts[status] = requests.filter { $0.status == status }.count
        }
        self.requestsByStatus = statusCounts

        // Group by priority
        var priorityCounts: [FeatureRequestPriority: Int] = [:]
        for priority in FeatureRequestPriority.allCases {
            priorityCounts[priority] = requests.filter { $0.priority == priority }.count
        }
        self.requestsByPriority = priorityCounts

        // Group by category
        var categoryCounts: [FeatureRequestCategory: Int] = [:]
        for category in FeatureRequestCategory.allCases {
            categoryCounts[category] = requests.filter { $0.category == category }.count
        }
        self.requestsByCategory = categoryCounts

        // Calculate vote statistics
        self.totalVotes = requests.reduce(0) { $0 + $1.votes }
        self.averageVotesPerRequest = totalRequests > 0 ? Double(totalVotes) / Double(totalRequests) : 0.0

        // Find date range
        self.mostRecentRequest = requests.map(\.createdAt).max()
        self.oldestRequest = requests.map(\.createdAt).min()

        // Calculate daily trend (last 30 days)
        let calendar = Calendar.current
        let now = Date()
        var daily: [Date: Int] = [:]
        for dayOffset in 0 ..< 30 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) {
                let startOfDay = calendar.startOfDay(for: date)
                let count = requests.filter {
                    calendar.isDate($0.createdAt, inSameDayAs: startOfDay)
                }.count
                daily[startOfDay] = count
            }
        }
        self.dailyTrend = daily

        // Calculate weekly trend (last 12 weeks)
        var weekly: [Date: Int] = [:]
        for weekOffset in 0 ..< 12 {
            if let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now) {
                let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: weekStart)?.start ?? weekStart
                let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) ?? weekStart
                let count = requests.filter {
                    $0.createdAt >= startOfWeek && $0.createdAt < endOfWeek
                }.count
                weekly[startOfWeek] = count
            }
        }
        self.weeklyTrend = weekly

        // Calculate top tags
        var tagCounts: [String: Int] = [:]
        for request in requests {
            for tag in request.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        self.topTags = tagCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { (tag: $0.key, count: $0.value) }

        // Calculate completion rate
        let completedCount = (statusCounts[.completed] ?? 0) + (statusCounts[.rejected] ?? 0)
        self.completionRate = totalRequests > 0 ? Double(completedCount) / Double(totalRequests) * 100 : 0

        // Calculate average completion time for completed requests
        let completedRequests = requests.filter { $0.status == .completed }
        if !completedRequests.isEmpty {
            let totalDays = completedRequests.reduce(0.0) { total, request in
                let days = request.updatedAt.timeIntervalSince(request.createdAt) / (60 * 60 * 24)
                return total + days
            }
            self.averageCompletionDays = totalDays / Double(completedRequests.count)
        } else {
            self.averageCompletionDays = nil
        }
    }

    /// Get requests created in a date range
    public static func requestsInRange(
        _ requests: [FeatureRequest],
        from startDate: Date,
        to endDate: Date
    ) -> [FeatureRequest] {
        requests.filter { $0.createdAt >= startDate && $0.createdAt <= endDate }
    }

    /// Calculate trend direction (increasing, stable, decreasing)
    public var trend: TrendDirection {
        let sortedWeekly = weeklyTrend.sorted { $0.key > $1.key }
        guard sortedWeekly.count >= 2 else { return .stable }

        let recentWeeks = Array(sortedWeekly.prefix(4))
        let olderWeeks = Array(sortedWeekly.dropFirst(4).prefix(4))

        let recentAverage = recentWeeks.isEmpty ? 0 : Double(recentWeeks.map(\.value).reduce(0, +)) / Double(recentWeeks.count)
        let olderAverage = olderWeeks.isEmpty ? 0 : Double(olderWeeks.map(\.value).reduce(0, +)) / Double(olderWeeks.count)

        let threshold = max(1.0, olderAverage * 0.2) // 20% change threshold

        if recentAverage > olderAverage + threshold {
            return .increasing
        } else if recentAverage < olderAverage - threshold {
            return .decreasing
        } else {
            return .stable
        }
    }
}

/// Direction of request submission trend
@available(iOS 26.0, macOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *)
public enum TrendDirection: String, Sendable {
    case increasing
    case stable
    case decreasing

    public var displayName: String {
        switch self {
        case .increasing: return "Increasing"
        case .stable: return "Stable"
        case .decreasing: return "Decreasing"
        }
    }

    public var iconName: String {
        switch self {
        case .increasing: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .decreasing: return "arrow.down.right"
        }
    }
}
