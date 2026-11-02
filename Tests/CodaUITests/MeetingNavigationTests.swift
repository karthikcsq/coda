import AppKit
import Foundation
import ScreenCaptureKit
import SwiftUI
import Testing
import CodaCore
@testable import Coda

private func stableMeetingData(_ meetings: [Meeting]) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(meetings)
}

@Test @MainActor func meetingSelectionOpensDetailAndBackKeepsSelectionAndTranscript() throws {
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    let first = try #require(model.meetings.first)
    let second = Meeting(title: "Second synthetic meeting", audioFile: "not-a-recording.m4a")
    model.meetings.append(second)
    let original = try stableMeetingData(model.meetings)
    model.search = "synthetic"
    model.openSettings()
    model.openMeeting(second.id)
    #expect(model.selection == second.id)
    #expect(model.showingMeetingDetail && !model.showSettings)
    model.showMeetingLibrary()
    #expect(!model.showingMeetingDetail && model.selection == second.id)
    #expect(model.search == "synthetic")
    model.openMeeting(first.id)
    #expect(model.showingMeetingDetail && model.selected?.segments == first.segments)
    let encodedAfterNavigation = try stableMeetingData(model.meetings)
    #expect(original == encodedAfterNavigation)
    model.openMeeting(UUID())
    #expect(model.selection == first.id)
}

@Test @MainActor func meetingBackKeepsRecordingAndProcessingControlsReachable() {
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    model.showingMeetingDetail = true
    model.startingCapture = true
    model.showMeetingLibrary(); #expect(model.showingMeetingDetail)
    model.startingCapture = false; model.recording = true
    model.showMeetingLibrary(); #expect(model.showingMeetingDetail)
    model.recording = false; model.busy = true
    model.showMeetingLibrary(); #expect(model.showingMeetingDetail)
    model.busy = false
    model.showMeetingLibrary(); #expect(!model.showingMeetingDetail)
}

@Test @MainActor func deniedSystemAudioOffersExplicitMicrophoneOptionsWithoutStartingCapture() throws {
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    let original = try stableMeetingData(model.meetings)
    model.presentRecordingStartFailure(RecordingStartFailure(stage: .sources, underlying: NSError(domain: SCStreamErrorDomain, code: -3801)))
    #expect(model.recordingStartFailure?.systemAudioPermissionDenied == true)
    #expect(model.includeSystem && !model.showRecordConsent)
    #expect(!model.recording && !model.startingCapture)
    // SwiftUI may dismiss the alert binding before executing the selected action.
    model.error = nil
    model.reviewRecordingOptions(microphoneOnly: true)
    #expect(!model.includeSystem && model.showRecordConsent && model.showingMeetingDetail)
    #expect(model.error == nil && model.recordingStartFailure == nil)
    #expect(!model.recording && !model.startingCapture)
    let encodedAfterRecovery = try stableMeetingData(model.meetings)
    #expect(original == encodedAfterRecovery)
}

@Test @MainActor func captureDeviceFailureDoesNotSuggestPermissionOrChangeAudioSource() {
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    model.presentRecordingStartFailure(RecordingStartFailure(stage: .stream, underlying: NSError(domain: SCStreamErrorDomain, code: -3820)))
    #expect(model.recordingStartFailure?.systemAudioPermissionDenied == false)
    model.reviewRecordingOptions(microphoneOnly: true)
    #expect(model.includeSystem && !model.showRecordConsent)
    model.reviewRecordingOptions()
    #expect(model.includeSystem && model.showRecordConsent)
    #expect(!model.recording && !model.startingCapture)
}

@Test @MainActor func meetingOpenedFromAnotherWorkspaceRoutesToDetailWithoutChangingInitialPage() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    let controller = DictationController(preview: true)
    controller.workspaceSection = "Dictation"
    let host = NSHostingView(rootView: WorkspaceView(model: model, controller: controller, delegate: AppDelegate()))
    host.frame = CGRect(x: 0, y: 0, width: 980, height: 680)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host; host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    #expect(controller.workspaceSection == "Dictation")
    let imported = Meeting(title: "Synthetic imported audio", audioFile: "no-audio.m4a")
    model.meetings.append(imported)
    model.openMeeting(imported.id)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    #expect(controller.workspaceSection == "Meetings" && model.showingMeetingDetail)
    #expect(model.selection == imported.id && !model.recording && !model.startingCapture)
}

@Test @MainActor func renderMeetingDetailWithoutNestedSidebarAtMinimumWorkspaceWidth() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    let controller = DictationController(preview: true)
    model.openMeeting(try #require(model.selection))
    let host = NSHostingView(rootView: NotetakerPage(model: model, controller: controller)
        .background(Color(white: 0.10)).environment(\.colorScheme, .dark).foregroundStyle(Color(white: 0.88)))
    host.frame = CGRect(x: 0, y: 0, width: 764, height: 680)
    host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: "/tmp/coda-meeting-navigation-narrow.png"))
    #expect(model.showingMeetingDetail && !model.recording)

    model.includeSystem = false
    let options = NSHostingView(rootView: RecordingOptionsView(model: model).environment(\.colorScheme, .dark))
    options.frame = CGRect(x: 0, y: 0, width: 510, height: 330)
    let optionsWindow = NSWindow(contentRect: options.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    optionsWindow.contentView = options; options.appearance = NSAppearance(named: .darkAqua)
    options.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let optionsBitmap = try #require(options.bitmapImageRepForCachingDisplay(in: options.bounds))
    options.cacheDisplay(in: options.bounds, to: optionsBitmap)
    let optionsPNG = try #require(optionsBitmap.representation(using: .png, properties: [:]))
    try optionsPNG.write(to: URL(fileURLWithPath: "/tmp/coda-meeting-microphone-options.png"))
}
