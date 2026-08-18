# ``CloudAdminClient``

The client SDK apps embed to consume what Cloud Admin manages.

## Overview

`CloudAdminClient` is the read/write half that a *managed* app links (via CloudKit) so the flags,
settings, analytics, and feature requests an admin configures in Cloud Admin take effect at
runtime. It talks to the app's own CloudKit container directly — no admin credentials, no Cloud
Admin dependency — and matches the record schema Cloud Admin writes (`Schema/client-schema.ckdb`).

This logic was previously provided by the Ikigai package; it now lives here so it's owned
alongside the admin side that shares these record types. For the SwiftUI property wrappers and
view modifiers, see the `CloudAdminClientUI` target.

## Topics

### Getting Started

- <doc:Integration>

### Feature Flags

- ``FeatureFlag``
- ``FeatureFlagService``
- ``FeatureFlagPlatform``

### Remote Settings

- ``RemoteSetting``
- ``RemoteSettingsService``
- ``SettingValue``
- ``SettingValueType``

### Analytics

- ``AnalyticsEvent``
- ``AnalyticsService``
- ``AnalyticsProvider``
- ``AnalyticsProperties``

### Feature Requests

- ``FeatureRequest``
- ``FeatureRequestService``
- ``FeatureRequestStatistics``
- ``FeatureRequestStatus``
- ``FeatureRequestPriority``
- ``FeatureRequestCategory``
