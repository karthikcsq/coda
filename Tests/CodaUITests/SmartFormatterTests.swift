import AppKit
import Foundation
import Testing
import CodaCore
@testable import Coda

@MainActor private func fixture(_ body: String) throws -> (SmartFormatter, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let script = root.appendingPathComponent("worker.py")
    try body.write(to: script, atomically: true, encoding: .utf8)
    return (SmartFormatter(python: URL(fileURLWithPath: "/opt/homebrew/bin/python3.13"), script: script, model: root), root)
}
@Test @MainActor func correctionClassifierUsesTypedJudgmentsAndCannotInventWords() async throws {
    let (worker, root) = try fixture("""
    import json,sys
    print(json.dumps({'ready':True}),flush=True)
    for line in sys.stdin:
        r=json.loads(line)
        if r.get('kind') == 'corrections':
            print(json.dumps({'id':r['id'],'accepted':True,'decisions':[True,False]}),flush=True)
        else:
            print(json.dumps({'id':r['id'],'accepted':True,'text':r['text']}),flush=True)
    """)
    defer { worker.stop(); try? FileManager.default.removeItem(at: root) }
    let pairs = [WordCorrection(original: "Cartick", corrected: "Karthik"), WordCorrection(original: "Postgres", corrected: "Supabase")]
    // This is a stdio protocol test. Native render tests can occupy MainActor
    // longer than the production background-classification deadline.
    let decisions = await worker.classifyCorrections(original: "Meet Cartick at Postgres", edited: "Meet Karthik at Supabase", pairs: pairs, timeout: .seconds(10))
    #expect(decisions == [true, false])
    #expect(CorrectionEvidence.filter(pairs, judgments: decisions) == [pairs[0]])
    let malformed = await worker.classifyCorrections(original: "Cartick", edited: "Karthik", pairs: [pairs[0]], timeout: .seconds(10))
    #expect(malformed == nil) // A mismatched response is not a partial approval.
    let formatted = await worker.format("Original words", timeout: .seconds(10))
    #expect(formatted.text == "Original words" && formatted.accepted)
}
@Test @MainActor func undoneCorrectionCannotReappearAfterLocalClassifierFinishes() async throws {
    let (worker, root) = try fixture("""
    import json,sys,time
    print(json.dumps({'ready':True}),flush=True)
    for line in sys.stdin:
        r=json.loads(line); time.sleep(0.2)
        print(json.dumps({'id':r['id'],'accepted':True,'decisions':[True]}),flush=True)
    """)
    defer { worker.stop(); try? FileManager.default.removeItem(at: root) }
    let controller = DictationController(preview: true, formatter: worker)
    let session = UUID(), pair = WordCorrection(original: "Clod", corrected: "Claude")
    #expect(CorrectionEvidence.strength(pair) == .plausible)
    controller.reviewCorrections([pair], original: "Ask Clod to review", edited: "Ask Claude to review", session: session)
    await Task.yield()
    controller.reviewCorrections([], original: "Ask Clod to review", edited: "Ask Clod to review", session: session)
    try? await Task.sleep(for: .milliseconds(350))
    #expect(controller.dictionary.possible.isEmpty && controller.wordSuggestions.current == nil)
    controller.reviewCorrections([pair], original: "Ask Clod to review", edited: "Ask Claude to review", session: session)
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while controller.dictionary.possible.isEmpty && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
    #expect(controller.dictionary.possible.first?.word == "Claude")
    controller.reviewCorrections([], original: "Ask Clod to review", edited: "Ask Clod to review", session: session)
    #expect(controller.dictionary.possible.isEmpty && controller.wordSuggestions.current == nil)
}
@Test @MainActor func smartWorkerRoundTripRepetitionAndNonePreservation() async throws {
    let (worker, root) = try fixture("""
    import json,sys
    print(json.dumps({'ready':True}),flush=True)
    for line in sys.stdin:
        r=json.loads(line)
        print(json.dumps({'id':r['id'],'text':r['text'],'accepted':True}),flush=True)
    """)
    defer { worker.stop(); try? FileManager.default.removeItem(at: root) }
    for _ in 0..<3 {
        // This checks the stdio protocol; concurrent offscreen rendering may occupy
        // MainActor longer than the production interactive deadline.
        let result = await worker.format("Synthetic words", timeout: .seconds(10))
        #expect(result.accepted && result.text == "Synthetic words")
    }
    let empty = await worker.format(""); #expect(empty.text.isEmpty)
    let controller = DictationController(preview: true); controller.cleanupMode = .none
    let startedID = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let id = try #require(startedID)
    _ = controller.lifecycle.listening(id); _ = controller.lifecycle.processing()
    #expect(controller.acceptTranscription("  raw exactly  ", for: id))
    #expect(controller.text == "  raw exactly  ")
    #expect(controller.smartFormatter.status == "Local model idle")
}
@Test @MainActor func smartWorkerTimeoutMalformedAndCancellationUseRaw() async throws {
    for body in ["import time;time.sleep(30)", "print('not JSON',flush=True);import time;time.sleep(30)"] {
        let (worker, root) = try fixture(body)
        let result = await worker.format("Do not lose these words", timeout: .milliseconds(100))
        #expect(!result.accepted && result.text == "Do not lose these words")
        worker.stop(); try? FileManager.default.removeItem(at: root)
    }
    let (worker, root) = try fixture("import time;time.sleep(30)")
    defer { worker.stop(); try? FileManager.default.removeItem(at: root) }
    let task = Task { await worker.format("Original", timeout: .seconds(20)) }
    await Task.yield(); task.cancel()
    let result = await task.value
    #expect(!result.accepted && result.text == "Original")
}
@Test @MainActor func smartDefaultBudgetRejectsSlowFormatterAndKeepsExactRaw() async throws {
    let (worker, root) = try fixture("""
    import json,sys,time
    print(json.dumps({'ready':True}),flush=True)
    for line in sys.stdin:
        r=json.loads(line)
        time.sleep(2)
        print(json.dumps({'id':r['id'],'text':'Replacement','accepted':True}),flush=True)
    """)
    defer { worker.stop(); try? FileManager.default.removeItem(at: root) }
    let result = await worker.format("  um keep my exact original  ")
    #expect(!result.accepted)
    #expect(result.text == "  um keep my exact original  ")
}
@Test @MainActor func smartResultCannotReplaceCancelledOrNewSession() throws {
    let controller = DictationController(preview: true); controller.cleanupMode = .smart
    let firstID = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let first = try #require(firstID)
    _ = controller.lifecycle.listening(first); _ = controller.lifecycle.processing()
    #expect(controller.acceptTranscription("old words", for: first))
    controller.lifecycle.cancel(); controller.lifecycle.settled(first)
    let secondID = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let second = try #require(secondID)
    _ = controller.lifecycle.listening(second); _ = controller.lifecycle.processing()
    #expect(!controller.acceptSmartFormatting(.init(text: "stale", accepted: true, reason: "fixture"), for: first))
    #expect(controller.text == "old words")
    #expect(controller.acceptTranscription("new words", for: second))
    #expect(controller.acceptSmartFormatting(.init(text: "New words.", accepted: true, reason: "fixture"), for: second))
    #expect(controller.records.first?.rawText == "new words")
    #expect(controller.records.first?.text == "New words.")
}
@Test @MainActor func menuMeetingRoutesNeverRestartOccupiedOperation() {
    var opened=0, started=0, stopped=0
    let open = { opened += 1 }; let start = { started += 1 }; let stop = { stopped += 1 }
    MeetingMenuAction.perform(recording: false, occupied: false, open: open, start: start, stop: stop)
    #expect(opened == 1 && started == 1 && stopped == 0)
    MeetingMenuAction.perform(recording: false, occupied: true, open: open, start: start, stop: stop)
    #expect(opened == 2 && started == 1)
    MeetingMenuAction.perform(recording: true, occupied: true, open: open, start: start, stop: stop)
    #expect(opened == 3 && started == 1 && stopped == 1)
    // Permission failures remain in the existing model start route, visible in main window.
    let model = AppModel(preview: true); model.error = "Synthetic permission failure"
    let delegate = AppDelegate(); var reopenCount=0
    delegate.reopenMain = { reopenCount += 1 }
    _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
    _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
    #expect(reopenCount == 2 && model.error == "Synthetic permission failure")
}

@Test @MainActor func fillerOnlyResultNeverDropsSubstantiveInputAndPreservesOriginal() async throws {
    let (worker, root) = try fixture("""
    import json,sys
    print(json.dumps({'ready':True}),flush=True)
    for line in sys.stdin:
        r=json.loads(line)
        print(json.dumps({'id':r['id'],'text':'','accepted':True,'reason':'filler-only'}),flush=True)
    """)
    defer { worker.stop(); try? FileManager.default.removeItem(at: root) }
    let empty = await worker.format("Um, uh.", timeout: .seconds(10))
    #expect(empty.accepted && empty.text.isEmpty)
    let substantive = await worker.format("Keep these words", timeout: .seconds(10))
    #expect(!substantive.accepted && substantive.text == "Keep these words")
    let controller = DictationController(preview: true)
    controller.cleanupMode = .smart
    let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let id = try #require(begun)
    _ = controller.lifecycle.listening(id); _ = controller.lifecycle.processing()
    #expect(controller.acceptTranscription("Um, uh.", for: id))
    #expect(controller.acceptSmartFormatting(empty, for: id))
    #expect(controller.text.isEmpty)
    #expect(controller.records.first?.rawText == "Um, uh.")
}
