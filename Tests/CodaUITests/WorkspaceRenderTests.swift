import AppKit
import SwiftUI
import Testing
import CodaCore
@testable import Coda

/// Native render evidence for the UI overhaul. Every page is rendered at the 980x680
/// minimum window size and at the 1350x850 default size, so regressions in either the
/// cramped or the roomy layout are visible in `docs/images`.
private enum RenderTarget {
    static let sizes: [(name: String, size: CGSize)] = [
        ("980x680", CGSize(width: 980, height: 680)),
        ("1350x850", CGSize(width: 1350, height: 850))
    ]
    /// docs/images in the checkout, derived from this file's location.
    static var imageDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["CODA_RENDER_OUTPUT"] { return URL(fileURLWithPath: path) }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/images", isDirectory: true)
    }
}

@MainActor private func renderPNG<V: View>(_ view: V, size: CGSize, to file: URL) throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    #expect(host.bounds.width <= size.width && host.bounds.height <= size.height,
            "The native layout must fit the requested window size: \(file.lastPathComponent)")
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: file)
    #expect(bitmap.pixelsWide >= Int(host.bounds.width))
    #expect(bitmap.pixelsHigh >= Int(host.bounds.height))
}

@MainActor private func syntheticHistory() -> [DictationRecord] {
    [
        DictationRecord(text: "Let's keep the next release focused: I will review the onboarding copy and we can pick a date after the design review.",
                        target: "Mail", outcome: .inserted, detail: "Inserted into Mail.",
                        rawText: "lets keep the next release focused um i will review the onboarding copy and we can pick a date after the design review",
                        cleanupMode: .light),
        DictationRecord(text: "Budget is 12.5% over, so move 3 of the 4 contractor invoices into next quarter.",
                        target: "Notes", outcome: .saved, detail: "Saved locally.",
                        rawText: "budget is twelve point five percent over so move three of the four contractor invoices into next quarter",
                        cleanupMode: .smart),
        DictationRecord(text: "A quieter workspace. A clear next step.", target: "Xcode", outcome: .copyRequired,
                        detail: "The destination changed. Your words are saved — choose Copy or select a new field to retry.")
    ]
}

/// Opt-in: offscreen rendering of these pages holds the main actor long enough to
/// starve the overlay-timer and smart-worker tests, so the docs renders run on request.
///   CODA_RENDER_DOCS=1 ./scripts/test.sh --filter WorkspaceOverhaulRenderSuite
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CODA_RENDER_DOCS"] == "1",
                             "Opt-in docs render; set CODA_RENDER_DOCS=1."))
struct WorkspaceOverhaulRenderSuite {
@Test @MainActor func renderEveryWorkspacePageAtBothSupportedSizes() throws {
    let directory = RenderTarget.imageDirectory
    for (label, size) in RenderTarget.sizes {
        for section in ["Dictation", "History", "Insights", "Dictionary", "Meetings"] {
            let model = AppModel(preview: true)
            let controller = DictationController(preview: true)
            controller.attach(model)
            controller.records = syntheticHistory()
            controller.workspaceSection = section
            try renderPNG(WorkspaceView(model: model, controller: controller, delegate: AppDelegate()),
                          size: size,
                          to: directory.appendingPathComponent("overhaul-\(section.lowercased())-\(label).png"))
            // Presentation only: no recorder, model, clipboard or permission call is made.
            #expect(!model.modelConsent && !model.autoSummary)
        }
    }
}

@Test @MainActor func renderEmptyStatesAndSettingsAtMinimumWidth() throws {
    let directory = RenderTarget.imageDirectory
    for (label, size) in RenderTarget.sizes {
        let model = AppModel(preview: true)
        let controller = DictationController(preview: true)
        controller.attach(model)
        // No records: the honest empty states, not a dashboard of zeroes.
        controller.records = []
        for section in ["Dictation", "Insights"] {
            controller.workspaceSection = section
            try renderPNG(WorkspaceView(model: model, controller: controller, delegate: AppDelegate()),
                          size: size,
                          to: directory.appendingPathComponent("overhaul-empty-\(section.lowercased())-\(label).png"))
        }
        let settingsModel = AppModel(preview: true)
        let settingsController = DictationController(preview: true)
        settingsController.modifierShortcut = true
        settingsModel.openSettings()
        try renderPNG(WorkspaceView(model: settingsModel, controller: settingsController, delegate: AppDelegate()),
                      size: size,
                      to: directory.appendingPathComponent("overhaul-settings-\(label).png"))
        #expect(settingsModel.showSettings)
    }
}

@Test @MainActor func renderMeetingDetailAndFloatingControls() throws {
    let directory = RenderTarget.imageDirectory
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    controller.attach(model)
    for tab in ["Transcript", "Summary"] {
        try renderPNG(ContentView(model: model, dictation: controller, initialTab: tab)
                        .foregroundStyle(Color(white: 0.88)),
                      size: CGSize(width: 1120, height: 810),
                      to: directory.appendingPathComponent("overhaul-meeting-\(tab.lowercased()).png"))
    }
    try renderPNG(RecordCard(record: syntheticHistory()[0], controller: controller, expanded: true)
                    .padding(24).background(Color(white: 0.10)),
                  size: CGSize(width: 900, height: 600),
                  to: directory.appendingPathComponent("overhaul-record-card-expanded.png"))
    controller.message = "Synthetic state · no audio or model use"
    // Mutating lifecycle calls happen outside the macro expansion.
    let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let token = try #require(begun)
    let listening = controller.lifecycle.listening(token)
    #expect(listening)
    controller.level = 0.65
    try renderPNG(DictationHUD(controller: controller).padding(16).background(Color(white: 0.16)),
                  size: CGSize(width: 352, height: 96),
                  to: directory.appendingPathComponent("overhaul-dictation-hud.png"))
    #expect(!model.modelConsent)
}

}

@Test func reduceMotionDisablesEverySharedAnimation() {
    // One token decides motion for the sidebar, history, dictionary and settings jump links.
    #expect(CodaStyle.motion(true) == nil)
    #expect(CodaStyle.motion(true, duration: 0.5) == nil)
    #expect(CodaStyle.motion(false) != nil)
}

@Test func sharedRadiiAndInsetsStayWithinOneRamp() {
    // Guards against the ten-corner-radius drift the overhaul removed.
    let ramp = [CodaStyle.radiusSmall, CodaStyle.radius, CodaStyle.radiusLarge, CodaStyle.radiusShell]
    #expect(ramp == ramp.sorted())
    #expect(Set(ramp).count == ramp.count)
    #expect(CodaStyle.rowHeight >= 28)
    #expect(CodaStyle.contentWidth >= 900)
}
