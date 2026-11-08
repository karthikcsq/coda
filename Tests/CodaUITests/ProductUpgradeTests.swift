import AppKit
import SwiftUI
import Testing
import CodaCore
@testable import Coda

@Test @MainActor func previewPracticeNeverStartsMicrophoneOrChangesReadiness() {
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    controller.attach(model)
    controller.practice()
    #expect(!controller.lifecycle.busy)
    #expect(!controller.practiceSession && !controller.practiceCompleted)
    #expect(!model.modelConsent && !model.dictationBusy)
    #expect(!controller.readiness(for: model).canPractice)
    #expect(!model.summaryCredentials.save("synthetic-only"))
    #expect(throws: CodaError.missingKey) { try model.summaryCredentials.configuration() }
}

@Test @MainActor func previewPreferencesKeepSnippetTextAndFailuresVisible() {
    let controller = DictationController(preview: true)
    #expect(controller.preferences.addSnippet(trigger: "my signature", expansion: "Alex\nResearch team"))
    #expect(controller.preferences.setGlobalStyle(.formal))
    #expect(controller.preferences.personalize("My signature.", bundleID: "com.apple.mail").text == "Alex\nResearch team")
    #expect(!controller.preferences.addSnippet(trigger: "MY SIGNATURE!", expansion: "other"))
    #expect(controller.preferences.error != nil)
    #expect(controller.preferences.snippets.count == 1)
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CODA_RENDER_PRODUCT"] == "1"))
struct ProductUpgradeRenderSuite {
    @Test @MainActor func renderSetupAndWorkspace() throws {
        _ = NSApplication.shared
        let model = AppModel(preview: true)
        let controller = DictationController(preview: true)
        controller.attach(model)
        controller.records = [DictationRecord(text: "Let's keep the launch focused. I'll review the onboarding copy before Thursday's check-in.", target: "Mail", outcome: .saved, detail: "Synthetic render fixture")]
        #expect(controller.preferences.addSnippet(trigger: "my sign off", expansion: "Alex Chen\nResearch & development"))
        #expect(controller.preferences.setStyle(.formal, forBundleID: "com.apple.mail", appName: "Mail"))
        #expect(controller.preferences.setStyle(.casual, forBundleID: "com.hnc.Discord", appName: "Discord"))
        for size in [CGSize(width: 980, height: 680), CGSize(width: 1350, height: 850)] {
            for page in ["Home", "Personalize", "Dictation", "Meetings", "Dictionary"] {
                controller.workspaceSection = page
                try render(WorkspaceView(model: model, controller: controller, delegate: AppDelegate()), name: "\(page.lowercased())-\(Int(size.width))", size: size)
            }
        }
        for step in SetupStep.allCases {
            try render(OnboardingView(model: model, controller: controller, initialStep: step), name: "setup-\(step.rawValue)", size: CGSize(width: 760, height: 610))
        }
        try render(SettingsPanel(model: model, controller: controller), name: "settings", size: CGSize(width: 980, height: 680))
        try render(PersonalizationPage(model: model, controller: controller, initialTab: "Voice snippets"), name: "snippets", size: CGSize(width: 760, height: 680))
        let prepared = AppModel(preview: true, previewModelPrepared: true)
        prepared.modelConsent = true
        let practiceController = DictationController(preview: true, previewMicrophoneAllowed: true)
        practiceController.attach(prepared)
        practiceController.modifierShortcut = true; practiceController.mode = .hold
        try render(OnboardingView(model: prepared, controller: practiceController, initialStep: .practice), name: "setup-practice-ready", size: CGSize(width: 760, height: 610))
        practiceController.records = controller.records
        practiceController.workspaceSection = "Home"
        try render(WorkspaceView(model: prepared, controller: practiceController, delegate: AppDelegate()), name: "home-ready-1350", size: CGSize(width: 1350, height: 850))
        practiceController.practiceText = "Let's meet on Thursday at 3."
        practiceController.practiceCompleted = true
        try render(OnboardingView(model: prepared, controller: practiceController, initialStep: .practice), name: "setup-practice-complete", size: CGSize(width: 760, height: 610))
        #expect(!model.modelConsent && !model.autoSummary && !model.dictationBusy)
    }
    @MainActor private func render<V: View>(_ view: V, name: String, size: CGSize) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark).foregroundStyle(CodaStyle.ink).background(CodaStyle.canvas))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now.addingTimeInterval(0.12))
        #expect(host.bounds.width <= size.width && host.bounds.height <= size.height)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let output = URL(fileURLWithPath: "/tmp/coda-product-upgrade", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try png.write(to: output.appendingPathComponent(name + ".png"))
    }
}

@Test @MainActor func dictationCapturesPreferencesForTheDestinationAndKeepsThemStable() {
    let controller = DictationController(preview: true)
    controller.cleanupMode = .light
    #expect(controller.preferences.setStyle(.formal, forBundleID: "com.apple.mail", appName: "Mail"))
    #expect(controller.preferences.addSnippet(trigger: "my sign off", expansion: "Alex\nResearch team"))
    controller.snapshotPreferences(bundleID: "com.apple.mail")
    #expect(controller.activeStyleLabel == "Formal")
    #expect(controller.deliveryText(recognized: "hello there", cleaned: "hello there").text == "Hello there.")
    #expect(controller.deliveryText(recognized: "My sign off.", cleaned: "my sign-off").text == "Alex\nResearch team")
    #expect(controller.preferences.setStyle(.casual, forBundleID: "com.apple.mail", appName: "Mail"))
    #expect(controller.activeStyleLabel == "Formal") // A live session keeps its reviewed snapshot.
    controller.cleanupMode = .none
    #expect(controller.deliveryText(recognized: "My sign off.", cleaned: "anything").text == "My sign off.")
}
