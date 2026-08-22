import ArgumentParser
import Foundation
import {{UI_MODULE}}

/// Writes light/dark PNGs of {{APP_NAME}} SwiftUI screens into `Designs/previews`.
@main
struct PreviewCaptureCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview-capture",
        abstract: "Render {{APP_NAME}} SwiftUI preview screens to PNG."
    )

    @Option(name: .shortAndLong, help: "Root directory. PNGs land in <output>/<device>/<Screen>-{light,dark}.png.")
    var output: String = "Designs/previews"

    @Option(
        name: .long,
        help: "Comma-separated devices: iphone,ipad,mac,tv,vision,watch. Default is all."
    )
    var devices: String = PreviewCaptureDevice.allCases.map(\.rawValue).joined(separator: ",")

    func run() async throws {
        let parsed = devices
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .compactMap(PreviewCaptureDevice.init(rawValue:))
        guard !parsed.isEmpty else {
            throw ValidationError("No valid devices in --devices \(devices)")
        }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try await MainActor.run {
            try PreviewCapture.write(to: directory, devices: parsed)
        }
        let count = PreviewCaptureScreen.allCases.count * parsed.count * 2
        print("Wrote \(count) screenshots to \(directory.path) (\(parsed.map(\.rawValue).joined(separator: ", ")))")
        // NSHostingView / NSWindow can leave AppKit's run loop alive (sign-in SDKs,
        // URLSession, SpriteKit) so `swift run` never returns. The PNGs are on disk.
        Foundation.exit(0)
    }
}
