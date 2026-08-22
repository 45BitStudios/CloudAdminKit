import Foundation
import SwiftUI
#if canImport(AppKit)
    import AppKit
#endif

/// Named product screens rendered by `preview-capture` into `Designs/previews/`.
///
/// Keep this list to screens a person would actually look at — not every private row.
/// Light and dark PNGs share the same `rawValue` stem. Fill cases from this app's
/// `#Preview` names (Tubeactions is the working example).
public enum PreviewCaptureScreen: String, CaseIterable, Sendable {
    case home = "Home"
    case settings = "Settings"

    /// Logical iPhone canvas. Prefer ``PreviewCaptureDevice``.
    public static var canvasSize: CGSize { PreviewCaptureDevice.iphone.canvasSize }
}

/// Destination canvases. Capture writes `Designs/previews/<device>/<Screen>-{light,dark}.png`.
///
/// The CLI is a macOS executable, so these are 2D layouts at that size — not a
/// watchOS / tvOS / visionOS runtime. `#if os(watchOS)` views will not appear here.
public enum PreviewCaptureDevice: String, CaseIterable, Sendable {
    case iphone
    case ipad
    case mac
    case tv
    case vision
    case watch

    public var canvasSize: CGSize {
        switch self {
        case .iphone: CGSize(width: 390, height: 844)
        case .ipad: CGSize(width: 834, height: 1194)
        case .mac: CGSize(width: 1280, height: 800)
        case .tv: CGSize(width: 1920, height: 1080)
        case .vision: CGSize(width: 1280, height: 720)
        case .watch: CGSize(width: 198, height: 242)
        }
    }

    public var scale: CGFloat {
        switch self {
        case .tv: 1
        default: 2
        }
    }

    public var horizontalSizeClass: UserInterfaceSizeClass {
        switch self {
        case .iphone, .watch: .compact
        default: .regular
        }
    }
}

/// Renders ``PreviewCaptureScreen`` values to PNG.
public enum PreviewCapture {
    /// Writes light and dark PNGs for every screen into `directory/<device>/`.
    @MainActor
    public static func write(to directory: URL) throws {
        try write(to: directory, devices: Array(PreviewCaptureDevice.allCases))
    }

    @MainActor
    public static func write(to directory: URL, devices: [PreviewCaptureDevice]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for device in devices {
            let deviceDir = directory.appending(path: device.rawValue)
            try FileManager.default.createDirectory(at: deviceDir, withIntermediateDirectories: true)
            for screen in PreviewCaptureScreen.allCases {
                for scheme in [ColorScheme.light, ColorScheme.dark] {
                    let stem = scheme == .light ? "light" : "dark"
                    let url = deviceDir.appending(path: "\(screen.rawValue)-\(stem).png")
                    guard let data = pngData(for: screen, colorScheme: scheme, device: device) else {
                        throw CaptureError.renderFailed("\(device.rawValue)/\(screen.rawValue)", stem)
                    }
                    try data.write(to: url, options: .atomic)
                }
            }
        }
    }

    @MainActor
    static func pngData(
        for screen: PreviewCaptureScreen,
        colorScheme: ColorScheme,
        device: PreviewCaptureDevice = .iphone
    ) -> Data? {
        pngData(for: screen.preview, colorScheme: colorScheme, device: device)
    }

    @MainActor
    static func pngData(
        for view: some View,
        colorScheme: ColorScheme,
        device: PreviewCaptureDevice = .iphone
    ) -> Data? {
        let size = device.canvasSize
        let content = view
            .frame(width: size.width, height: size.height)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, colorScheme)
            .environment(\.horizontalSizeClass, device.horizontalSizeClass)
            .preferredColorScheme(colorScheme)
        #if os(macOS)
            return pngDataUsingHostingView(content, size: size, scale: device.scale)
        #else
            let renderer = ImageRenderer(content: content)
            renderer.scale = device.scale
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
            return renderer.uiImage?.pngData()
        #endif
    }

    #if os(macOS)
        /// `ImageRenderer` often emits an empty bitmap for NavigationStack/List on
        /// macOS. An offscreen `NSHostingView` lays the tree out for real.
        @MainActor
        private static func pngDataUsingHostingView(_ view: some View, size: CGSize, scale: CGFloat = 2) -> Data? {
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.wantsLayer = true
            hosting.layer?.contentsScale = scale
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * scale),
                pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                window.orderOut(nil)
                return nil
            }
            // Point size, not pixel size — otherwise the 1x drawing sits in a corner
            // of a 2x buffer (AppKit origin is bottom-left).
            bitmap.size = size
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            window.orderOut(nil)
            return bitmap.representation(using: .png, properties: [:])
        }
    #endif

    enum CaptureError: Error, LocalizedError {
        case renderFailed(String, String)

        var errorDescription: String? {
            switch self {
            case let .renderFailed(screen, scheme):
                "Failed to render \(screen) (\(scheme))"
            }
        }
    }
}

extension PreviewCaptureScreen {
    @MainActor @ViewBuilder
    var preview: some View {
        // Replace with this app's screens + PreviewData. See Tubeactions
        // Sources/TubeActionsUI/Preview/PreviewCapture.swift.
        switch self {
        case .home:
            EmptyView()
        case .settings:
            EmptyView()
        }
    }
}
