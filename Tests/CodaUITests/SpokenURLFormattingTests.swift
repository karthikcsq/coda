import Foundation
import Testing
import CodaCore
@testable import Coda

@Test @MainActor func spokenURLFormattingWorksWithoutOptionalCleanupWorker() async {
    let formatter = SmartFormatter(python: URL(fileURLWithPath: "/no-runtime"),
                                  script: URL(fileURLWithPath: "/no-worker"))
    let result = await formatter.format("style.fyi slash style dash md")
    #expect(result.accepted && result.text == "style.fyi/style-md")
    #expect(DictationCleanup.apply("style.fyi slash style dash md", mode: .none).text == "style.fyi slash style dash md")
}

@Test @MainActor func URLCleanupPreservesOriginalInHistoryAndSkipsCorrectionJudgments() async throws {
    let formatter = SmartFormatter(python: URL(fileURLWithPath: "/no-runtime"),
                                  script: URL(fileURLWithPath: "/no-worker"))
    let raw = "Use style.fyi slash style dash md and send it."
    let controller = DictationController(preview: true, formatter: formatter)
    controller.cleanupMode = .smart
    let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let id = try #require(begun)
    _ = controller.lifecycle.listening(id); _ = controller.lifecycle.processing()
    #expect(controller.acceptTranscription(raw, for: id))
    let result = await formatter.format(raw)
    #expect(controller.acceptSmartFormatting(result, for: id))
    #expect(controller.records.first?.rawText == raw)
    #expect(controller.records.first?.text == "Use style.fyi/style-md and send it.")
    let judged = await formatter.format(raw, correctionPairs: [.init(original: "style", corrected: "Style")], edited: raw)
    #expect(!judged.accepted && judged.text == raw)
    controller.cancel()
}
