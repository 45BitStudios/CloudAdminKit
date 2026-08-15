# ``CloudAdminClientUI``

The SwiftUI surface for ``CloudAdminClient``.

## Overview

`CloudAdminClientUI` adds the SwiftUI ergonomics on top of ``CloudAdminClient``: property wrappers
that read feature flags and remote settings declaratively, and view modifiers that track analytics
screens and taps. It's split from the core the way `IkigaiUI` was split from `IkigaiCore`, so an
app (or an extension) that only needs the services can link ``CloudAdminClient`` without pulling in
SwiftUI.

## Topics

### Feature Flags

- ``FeatureEnabled``
- ``FeatureFlagObserver``

### Remote Settings

- ``RemoteStringSetting``
- ``RemoteBoolSetting``
- ``RemoteIntSetting``
- ``RemoteDoubleSetting``
- ``RemoteURLSetting``

### Analytics

- ``AnalyticsObserver``
- ``TrackableButton``
