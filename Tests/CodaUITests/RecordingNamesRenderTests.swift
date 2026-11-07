import AppKit
import SwiftUI
import Testing
@testable import Coda

@Test @MainActor func renderRecordingSheetWithPlannedSpeakerNames() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    model.recordingSpeakerCount = 3
    model.recordingSpeakerNames = ["Karthik", "Wyatt"]
    let host = NSHostingView(rootView: RecordingOptionsView(model: model))
    host.frame = CGRect(x: 0, y: 0, width: 470, height: 620)
    host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/coda-recording-names.png"))
    #expect(model.recordingSpeakerNames.count == 2)
}
