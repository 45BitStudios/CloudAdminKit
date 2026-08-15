//
//  DeviceInfoCollector.swift
//  CloudAdminClient
//
//  Utility for collecting device and app information for analytics
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Network)
import Network
#endif

/// Collects device and app information for analytics events
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
public final class DeviceInfoCollector: Sendable {

    /// Shared instance
    public static let shared = DeviceInfoCollector()

    /// Cached device info (updated on init and when requested)
    private let cachedInfo: DeviceInfo

    private init() {
        self.cachedInfo = Self.collectDeviceInfo()
    }

    /// Gets the current device info
    public var deviceInfo: DeviceInfo {
        cachedInfo
    }

    /// Collects fresh device info (useful if network status changed)
    public static func collectFresh() -> DeviceInfo {
        collectDeviceInfo()
    }

    // MARK: - Private Collection Methods

    private static func collectDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            model: getDeviceModel(),
            osVersion: getOSVersion(),
            appVersion: getAppVersion(),
            buildNumber: getBuildNumber(),
            locale: getLocale(),
            timezone: getTimezone(),
            screenScale: getScreenScale(),
            isLowPowerMode: getLowPowerMode(),
            networkType: getNetworkType()
        )
    }

    private static func getDeviceModel() -> String {
        #if os(iOS) || os(tvOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
        #elseif os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #elseif os(watchOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
        #elseif os(visionOS)
        return "Apple Vision Pro"
        #else
        return "Unknown"
        #endif
    }

    private static func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func getAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private static func getBuildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private static func getLocale() -> String {
        Locale.current.identifier
    }

    private static func getTimezone() -> String {
        TimeZone.current.identifier
    }

    private static func getScreenScale() -> Double {
        #if os(iOS) || os(tvOS)
        // UITraitCollection.current is nonisolated and not deprecated, unlike UIScreen.main.
        let scale = UITraitCollection.current.displayScale
        return scale > 0 ? Double(scale) : 1.0
        #elseif os(macOS)
        return Double(NSScreen.main?.backingScaleFactor ?? 1.0)
        #elseif os(watchOS)
        return Double(WKInterfaceDevice.current().screenScale)
        #elseif os(visionOS)
        // visionOS doesn't have UIScreen.main; use default scale for spatial computing
        return 2.0
        #else
        return 1.0
        #endif
    }

    private static func getLowPowerMode() -> Bool {
        #if os(iOS) || os(watchOS)
        return ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        return false
        #endif
    }

    private static func getNetworkType() -> NetworkType {
        // Note: For accurate network monitoring, use NWPathMonitor
        // This is a simplified check
        #if canImport(Network)
        // Default to unknown - the AnalyticsService can update this
        // via NWPathMonitor for more accurate tracking
        return .unknown
        #else
        return .unknown
        #endif
    }
}

// MARK: - Network Monitor

#if canImport(Network)
/// Monitors network connectivity for analytics
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
public actor NetworkMonitor {
    public static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cloudadminkit.networkmonitor")
    private var currentNetworkType: NetworkType = .unknown
    private var isMonitoring = false

    private init() {
        // Monitoring started lazily on first access
    }

    /// Starts monitoring network changes (called automatically on first access)
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.updateNetworkType(from: path)
            }
        }
        monitor.start(queue: queue)
    }

    private func updateNetworkType(from path: NWPath) {
        if path.status == .satisfied {
            if path.usesInterfaceType(.wifi) {
                currentNetworkType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                currentNetworkType = .cellular
            } else {
                currentNetworkType = .unknown
            }
        } else {
            currentNetworkType = .offline
        }
    }

    /// Gets the current network type
    public var networkType: NetworkType {
        currentNetworkType
    }

    /// Checks if the device is online
    public var isOnline: Bool {
        currentNetworkType != .offline
    }
}
#endif

// MARK: - watchOS Support

#if os(watchOS)
import WatchKit
#endif
