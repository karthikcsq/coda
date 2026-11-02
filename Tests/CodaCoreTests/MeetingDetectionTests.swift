import Foundation
import Testing
@testable import CodaCore

private func button(_ text: String, children: [MeetingAccessibilityNode] = []) -> MeetingAccessibilityNode {
    MeetingAccessibilityNode(role: "AXButton", text: text, children: children)
}
private func document(_ url: String, controls: [MeetingAccessibilityNode]) -> MeetingAccessibilityNode {
    MeetingAccessibilityNode(role: "AXWebArea", url: url, children: controls)
}

@Test func detectsActiveMeetZoomAndTeamsWithCountsIncludingSelf() {
    for (url, service, leave, people) in [
        ("https://meet.google.com/abc-defg-hij?authuser=1", "Google Meet", "Leave call", "Show everyone (3)"),
        ("https://teams.microsoft.com/v2/", "Teams", "Leave", "People 3"),
        ("https://teams.cloud.microsoft/v2/", "Teams", "Leave", "Participants (3)"),
        ("https://us02web.zoom.us/wc/123/join", "Zoom", "Leave meeting", "Participants (3)")
    ] {
        let detection = MeetingDetection.detect(document(url, controls: [button(leave), button(people)]))
        #expect(detection?.service == service)
        #expect(detection?.participantCount == 3)
    }
    for bundle in ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams"] {
        let native = MeetingDetection.nativeService(bundleID: bundle)
        #expect(native != nil)
        #expect(MeetingDetection.detect(MeetingAccessibilityNode(children: [button("Leave"), button("Participants (2)")]), nativeService: native, identity: bundle)?.participantCount == 2)
    }
}

@Test func detectionRequiresActiveCallAndTrustedHostAndScopesCountToCall() {
    #expect(MeetingDetection.detect(document("https://meet.google.com/abc-defg-hij", controls: [button("Join now"), button("People 3")])) == nil)
    #expect(MeetingDetection.detect(document("https://meet.google.com.evil.test/abc-defg-hij", controls: [button("Leave call"), button("People 3")])) == nil)
    #expect(MeetingDetection.detect(document("https://meet.google.com/landing", controls: [button("Leave call")])) == nil)
    let root = MeetingAccessibilityNode(children: [
        document("https://meet.google.com/abc-defg-hij", controls: [button("Leave call"), button("Chat 12")]),
        document("https://example.com", controls: [button("People 9")])
    ])
    #expect(MeetingDetection.detect(root)?.participantCount == nil)
    let conflicting = document("https://meet.google.com/abc-defg-hij", controls: [button("Leave call"), button("People 3"), button("Participants 4")])
    #expect(MeetingDetection.detect(conflicting)?.participantCount == nil)
    let badge = document("https://meet.google.com/abc-defg-hij", controls: [button("Leave call"), button("Show everyone", children: [MeetingAccessibilityNode(text: "3")])])
    #expect(MeetingDetection.detect(badge)?.participantCount == 3)
}

@Test func manualSpeakerCountOverridesMeetingHintAndUnavailableCountsStayAutomatic() {
    #expect(SpeakerCountSelection.resolve(manual: 3, detected: 5, useDetected: true) == 3)
    #expect(SpeakerCountSelection.resolve(manual: nil, detected: 2, useDetected: true) == 2)
    #expect(SpeakerCountSelection.resolve(manual: nil, detected: 5, useDetected: true) == nil)
    #expect(SpeakerCountSelection.resolve(manual: nil, detected: 2, useDetected: false) == nil)
    #expect(SpeakerCountSelection.resolve(manual: nil, detected: nil, useDetected: true) == nil)
}

@Test func savedCountRoundTripsAndOldMeetingFilesRemainReadable() throws {
    var meeting = Meeting(title: "Synthetic", audioFile: "none.m4a")
    meeting.expectedSpeakerCount = 3
    let data = try JSONEncoder().encode(meeting)
    #expect(try JSONDecoder().decode(Meeting.self, from: data).expectedSpeakerCount == 3)
    var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    old.removeValue(forKey: "expectedSpeakerCount")
    #expect(try JSONDecoder().decode(Meeting.self, from: JSONSerialization.data(withJSONObject: old)).expectedSpeakerCount == nil)
}
