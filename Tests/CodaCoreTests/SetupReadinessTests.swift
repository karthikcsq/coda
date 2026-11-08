import Foundation
import Testing
@testable import CodaCore

@Test func setupRequiresActualCapabilities() {
    var state = SetupReadiness(modelConsent: false, modelPrepared: true, microphoneAllowed: true,
                               shortcutAssigned: true, modifierShortcut: false, accessibilityAllowed: true)
    #expect(!state.canPractice && !state.canDictate)
    #expect(state.nextAction == "Review local model terms")
    state.modelConsent = true
    #expect(state.canInsert && state.completedSteps == 3)
    state.microphoneAllowed = false
    #expect(!state.canDictate && state.completedSteps == 2)
}
@Test func customShortcutCanWorkWithoutAutomaticInsertion() {
    var state = SetupReadiness(modelConsent: true, modelPrepared: true, microphoneAllowed: true,
                               shortcutAssigned: true, modifierShortcut: false, accessibilityAllowed: false)
    #expect(state.canDictate && !state.canInsert)
    state.modifierShortcut = true
    #expect(!state.canDictate && state.canPractice)
    #expect(state.nextAction == "Enable your shortcut access")
}

@Test func meetingSearchFindsConversationAndPeopleAcrossTerms() {
    var meeting = Meeting(title: "Planning", audioFile: "no-audio.m4a")
    meeting.speakerNames = ["0": "Alex Chen"]
    meeting.segments = [Segment(id: "s1", start: 0, end: 2, speakers: [0], text: "The onboarding review is Thursday.")]
    #expect(meeting.matchesSearch("Alex thursday"))
    #expect(meeting.matchesSearch("  PLANNING \n onboarding  "))
    #expect(meeting.matchesSearch("   "))
    #expect(!meeting.matchesSearch("onboarding Friday"))
}

@Test func deliveryNeverExpandsATriggerCreatedByCleanup() throws {
    var settings = DictationPreferenceSettings()
    _ = settings.addSnippet(trigger: "my signature", expansion: "Alex\nResearch team")
    settings.globalStyle = .formal
    let unrelated = DictationPersonalization.forDelivery(recognized: "Do not insert my signature", cleaned: "my signature", mode: .smart, bundleID: nil, settings: settings)
    #expect(unrelated.snippet == nil)
    #expect(unrelated.text == "My signature.")
    let explicit = DictationPersonalization.forDelivery(recognized: "My signature.", cleaned: "wrong cleanup", mode: .smart, bundleID: nil, settings: settings)
    #expect(explicit.text == "Alex\nResearch team" && explicit.snippet != nil)
    let raw = DictationPersonalization.forDelivery(recognized: "My signature.", cleaned: "anything", mode: .none, bundleID: nil, settings: settings)
    #expect(raw.text == "My signature." && raw.snippet == nil)
}

@Test func snippetMetadataSurvivesHistoryAndOlderRecordsStillDecode() throws {
    let record = DictationRecord(text: "Alex", target: "Mail", outcome: .saved, detail: "Snippet", snippetTrigger: "my signature")
    #expect(try JSONDecoder().decode(DictationRecord.self, from: JSONEncoder().encode(record)).snippetTrigger == "my signature")
    var older = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    older.removeValue(forKey: "snippetTrigger")
    #expect(try JSONDecoder().decode(DictationRecord.self, from: JSONSerialization.data(withJSONObject: older)).snippetTrigger == nil)
}
