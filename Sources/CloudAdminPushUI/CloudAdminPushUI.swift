//
//  CloudAdminPushUI.swift
//  CloudAdminPushUI
//
//  Always-compiled module surface so watchOS / tvOS builds of this product
//  are not empty (PushAppDelegate and PushRegistrationController are gated
//  off those platforms).
//

/// Whether this product exposes APNs registration types on the current platform.
public enum CloudAdminPushUIAvailability: Sendable {
    #if os(watchOS) || os(tvOS)
    public static let isSupported = false
    #else
    public static let isSupported = true
    #endif
}
