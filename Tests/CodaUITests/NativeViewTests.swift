import AppKit
import SwiftUI
import Testing
import CodaCore
@testable import Coda

@Test @MainActor func renderSyntheticDictationWorkspaceAndDismissPreservesResult() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    controller.attach(model)
    let record = DictationRecord(text: "Let's keep the next release focused. I will review the onboarding copy, and we can decide on a date after the design review.", target: "Synthetic document", outcome: .copyRequired, detail: "The destination changed. Your words are saved — choose Copy or select a new field to retry.")
    controller.records = [record, DictationRecord(text: "A quieter workspace. A clear next step.", target: "Synthetic document", outcome: .inserted, detail: "Inserted successfully.")]
    controller.selectedRecord = record.id; controller.text = record.text
    controller.dismissOverlay()
    #expect(controller.text == record.text); #expect(controller.records.count == 2)
    let host = NSHostingView(rootView: WorkspaceView(model: model, controller: controller, delegate: AppDelegate()).environment(\.colorScheme, .dark))
    host.frame = CGRect(x: 0, y: 0, width: 1350, height: 850)
    host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.15))
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/coda-review-home.png"))
    #expect(bitmap.pixelsWide >= 1350)
    let hud = NSHostingView(rootView: DictationHUD(controller: controller))
    hud.frame = CGRect(x: 0, y: 0, width: 320, height: 64)
    let hudWindow = NSWindow(contentRect: hud.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    hudWindow.contentView = hud; hud.appearance = NSAppearance(named: .darkAqua)
    hud.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let hudBitmap = try #require(hud.bitmapImageRepForCachingDisplay(in: hud.bounds))
    hud.cacheDisplay(in: hud.bounds, to: hudBitmap)
    let hudPNG = try #require(hudBitmap.representation(using: .png, properties: [:]))
    try hudPNG.write(to: URL(fileURLWithPath: "/tmp/coda-review-overlay.png"))
}

@Test @MainActor func renderHistoryAndInsightsReview() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    controller.attach(model)
    controller.records = [DictationRecord(text: "Synthetic review: keep the proposal short and leave room for questions.", target: "Notes", outcome: .saved, detail: "Saved locally.")]
    for page in ["History", "Insights", "Meetings"] {
        controller.workspaceSection = page
        let host = NSHostingView(rootView: WorkspaceView(model:model,controller:controller,delegate:AppDelegate()))
        host.frame=CGRect(x:0,y:0,width:1350,height:850)
        host.appearance=NSAppearance(named:.darkAqua)
        let window=NSWindow(contentRect:host.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=host
        host.layoutSubtreeIfNeeded(); RunLoop.main.run(until:.now.addingTimeInterval(0.1))
        let image=try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:image)
        let png=try #require(image.representation(using:.png,properties:[:]))
        try png.write(to:URL(fileURLWithPath:"/tmp/coda-review-"+page.lowercased()+".png"))
    }
}

@Test @MainActor func renderMeasuredSettingsReview() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    controller.modifierShortcut = true; controller.mode = .hold
    let host = NSHostingView(rootView: SettingsPanel(model: model, controller: controller))
    host.frame = CGRect(x: 0, y: 0, width: 1100, height: 810)
    host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/coda-review-settings.png"))
    #expect(model.isOccupied)
    #expect(model.isVisualReview)
    #expect(!model.modelConsent && !model.autoSummary)
}

@Test @MainActor func renderMeetingAndSyntheticCaptureStates() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    controller.attach(model)
    func render<V: View>(_ view: V, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark).foregroundStyle(Color(white: 0.88)))
        host.frame = CGRect(origin: .zero, size: size); host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.1))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/coda-meeting-review-" + name + ".png"))
    }
    for tab in ["Transcript", "Summary", "Chat"] {
        try render(ContentView(model: model, dictation: controller, initialTab: tab), name: tab.lowercased(), size: CGSize(width: 1120, height: 810))
    }
    try render(ContentView(model: model, dictation: controller), name: "narrow", size: CGSize(width: 764, height: 680))
    // Presentation-only state; no recorder, permission, model or cloud method is invoked.
    model.busy = true; model.progress = 0.42; model.status = "Synthetic preview · transcribing locally (42%)"
    try render(ContentView(model: model, dictation: controller), name: "processing", size: CGSize(width: 1120, height: 810))
    model.busy = false; model.recording = true; model.recordingStarted = Date(); model.status = "Synthetic preview · no microphone is active"
    try render(ContentView(model: model, dictation: controller), name: "recording", size: CGSize(width: 1120, height: 810))
    model.recording = false
    controller.message = "Synthetic preview · no audio or model use"
    controller.targetName = "Synthetic target"
    let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let token = try #require(begun)
    controller.message = "Preparing microphone…"
    try render(VStack(spacing: 4) { Text("Synthetic state · no microphone active").font(.system(size: 10)); DictationHUD(controller: controller) }, name: "dictation-starting", size: CGSize(width: 320, height: 84))
    let listening = controller.lifecycle.listening(token)
    #expect(listening); controller.level = 0.6
    try render(VStack(spacing: 4) { Text("Synthetic state · no microphone active").font(.system(size: 10)); DictationHUD(controller: controller) }, name: "dictation-listening", size: CGSize(width: 320, height: 84))
    let processing = controller.lifecycle.processing()
    #expect(processing == token)
    controller.message = "Synthetic preview · no audio or model use"
    try render(VStack(spacing: 4) { Text("Synthetic state · no model running").font(.system(size: 10)); DictationHUD(controller: controller) }, name: "dictation-processing", size: CGSize(width: 320, height: 84))
    controller.lifecycle.fail(token)
    controller.message = "Microphone could not start. Check your input device and permission, then retry."
    try render(VStack(spacing: 4) { Text("Synthetic failure · no microphone active").font(.system(size: 10)); DictationHUD(controller: controller) }, name: "dictation-failed", size: CGSize(width: 320, height: 84))
    #expect(!model.modelConsent && !model.autoSummary)
}

@Test @MainActor func notetakerKeepsOperationControlsReachable() {
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    let page = NotetakerPage(model: model, controller: controller)
    // Preview mode disables operations but must not lock overview navigation.
    #expect(model.isOccupied)
    #expect(!page.operationInProgress)
    model.startingCapture = true
    #expect(page.operationInProgress)
    model.startingCapture = false; model.recording = true
    #expect(page.operationInProgress)
    model.recording = false; model.busy = true
    #expect(page.operationInProgress)
    model.busy = false
    #expect(!page.operationInProgress)
}

@Test @MainActor func settingsOpeningIsIdempotentAndPreservesValuesAndOperations() {
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    controller.mode = .hold; controller.autoInsert = false
    controller.workspaceSection = "Meetings"
    model.envPath = "/synthetic/settings-test.env"
    for _ in 0..<3 {
        model.openSettings(); model.openSettings()
        #expect(model.showSettings)
        model.closeSettings()
        #expect(!model.showSettings)
        #expect(controller.workspaceSection == "Meetings")
        #expect(controller.mode == .hold && !controller.autoInsert)
        #expect(model.envPath == "/synthetic/settings-test.env")
        #expect(!model.modelConsent && !model.autoSummary)
    }
    #expect(!model.settingsChangesLocked)
    model.recording = true; model.openSettings()
    #expect(model.showSettings && model.settingsChangesLocked && model.recording)
    model.closeSettings(); #expect(model.recording)
    model.recording = false; model.startingCapture = true
    #expect(model.settingsChangesLocked)
    model.startingCapture = false; model.busy = true
    #expect(model.settingsChangesLocked)
    model.busy = false; model.dictationBusy = true
    #expect(model.settingsChangesLocked)
    model.dictationBusy = false
    #expect(!model.settingsChangesLocked)
}

@Test @MainActor func renderIntegratedSettingsWhileProcessing() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    model.busy = true; model.openSettings()
    let host = NSHostingView(rootView: WorkspaceView(model: model, controller: controller, delegate: AppDelegate()))
    host.frame = CGRect(x: 0, y: 0, width: 980, height: 680); host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host; host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/coda-settings-processing-narrow.png"))
    #expect(model.busy && model.settingsChangesLocked)
}

@Test @MainActor func renderReversibleCleanupHistory() throws {
    _ = NSApplication.shared
    let controller = DictationController(preview: true)
    let record = DictationRecord(text: "Send it Thursday", target: "Synthetic document", outcome: .saved, detail: "Saved locally", rawText: "send it Tuesday actually Thursday", cleanupMode: .light)
    let host = NSHostingView(rootView: RecordCard(record: record, controller: controller, expanded: true).padding(24).background(Color(white: 0.08)).environment(\.colorScheme, .dark))
    host.frame = CGRect(x: 0, y: 0, width: 900, height: 360); host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host; host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/coda-cleanup-history-preview.png"))
    #expect(record.rawText == "send it Tuesday actually Thursday")
}
