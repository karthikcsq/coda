import AppKit
import Testing
import CodaCore
@testable import Coda

@Test @MainActor func transcriptionHidesActualPanelBeforeInsertionAndKeepsHistory() throws {
    _ = NSApplication.shared
    let controller = DictationController(preview: true)
    for index in 0..<3 {
        controller.previewOverlay()
        #expect(controller.overlayIsVisible)
        let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
        let id = try #require(begun)
        let transition1 = controller.lifecycle.listening(id)
    #expect(transition1)
        let transition2 = controller.lifecycle.processing()
    #expect(transition2 == id)
        #expect(controller.acceptTranscription(" Synthetic sentence \(index). ", for: id))
        #expect(!controller.overlayIsVisible)
        // Delivery has not finished; UI dismissal must not unblock overlapping insertion.
        #expect(controller.lifecycle.busy)
        let transition3 = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    #expect(transition3 == nil)
        #expect(controller.records.first?.id == id)
        #expect(controller.records.first?.text == "Synthetic sentence \(index).")
        #expect(controller.records.first?.outcome == .saved)
        let transition4 = controller.lifecycle.complete(id)
    #expect(transition4)
    }
    #expect(controller.records.count == 3)
}

@Test @MainActor func staleCompletionCannotHideNewSessionOrReplaceSavedText() throws {
    _ = NSApplication.shared
    let controller = DictationController(preview: true)
    controller.previewOverlay()
    let firstStart = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let first = try #require(firstStart)
    let transition5 = controller.lifecycle.listening(first)
    #expect(transition5)
    let transition6 = controller.lifecycle.processing()
    #expect(transition6 == first)
    controller.lifecycle.cancel()
    #expect(!controller.acceptTranscription("Cancelled result", for: first))
    controller.lifecycle.settled(first)
    controller.previewOverlay()
    let secondStart = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let second = try #require(secondStart)
    let transition7 = controller.lifecycle.listening(second)
    #expect(transition7)
    #expect(!controller.acceptTranscription("Stale result", for: first))
    #expect(controller.overlayIsVisible)
    #expect(controller.text.isEmpty && controller.records.isEmpty)
    #expect(controller.lifecycle.phase == .listening)
    controller.lifecycle.cancel(); controller.dismissOverlay()
    #expect(!controller.overlayIsVisible)
}

@Test @MainActor func errorDismissalExpiresButOldTimerCannotCloseNewPresentation() async {
    _ = NSApplication.shared
    let controller = DictationController(preview: true)
    controller.records = [DictationRecord(text: "", target: "Synthetic", outcome: .failed, detail: "Synthetic failure")]
    controller.previewOverlay()
    controller.dismissAfterResult(after: .milliseconds(30))
    // Other native renders occupy MainActor; await the observable outcome, not a
    // scheduler race against an 80 ms wall-clock delay.
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while controller.overlayIsVisible && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(20))
    }
    #expect(!controller.overlayIsVisible)
    #expect(controller.records.first?.outcome == .failed)
    controller.previewOverlay()
    controller.dismissAfterResult(after: .milliseconds(30))
    controller.previewOverlay() // New presentation invalidates the previous callback.
    try? await Task.sleep(for: .milliseconds(80))
    #expect(controller.overlayIsVisible)
    controller.dismissOverlay()
}

@Test @MainActor func cleanupKeepsRawAndDismissesBeforeDelivery() throws {
    _ = NSApplication.shared
    let controller = DictationController(preview: true)
    controller.cleanupMode = .light
    controller.previewOverlay()
    let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let id = try #require(begun)
    let listening = controller.lifecycle.listening(id); #expect(listening)
    _ = controller.lifecycle.processing()
    #expect(controller.acceptTranscription("send it Tuesday actually Thursday", for: id))
    #expect(controller.text == "Send it Thursday")
    #expect(controller.records.first?.rawText == "send it Tuesday actually Thursday")
    #expect(!controller.overlayIsVisible && controller.lifecycle.busy)
    _ = controller.lifecycle.complete(id)
    controller.cleanupMode = .none
    let next = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let nextID = try #require(next); _ = controller.lifecycle.listening(nextID); _ = controller.lifecycle.processing()
    #expect(controller.acceptTranscription("  Raw words  ", for: nextID))
    #expect(controller.text == "  Raw words  ")
    #expect(controller.records.first?.rawText == "  Raw words  ")
}
