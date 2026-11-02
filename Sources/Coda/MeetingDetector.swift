import AppKit
import ApplicationServices
import SwiftUI
import CodaCore

/// Bounded, read-only Accessibility snapshots. No browser scripts, clicks, or recording.
enum MeetingAccessibilityReader {
    static func read(apps: [(pid_t, String)]) -> DetectedMeeting? {
        guard AXIsProcessTrusted() else { return nil }
        for (pid, bundle) in apps {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.08)
            guard let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows.prefix(8) {
                var remaining = 2500
                let deadline = Date().addingTimeInterval(0.5)
                let tree = snapshot(window, depth: 0, remaining: &remaining, deadline: deadline)
                if let result = MeetingDetection.detect(tree, nativeService: MeetingDetection.nativeService(bundleID: bundle), identity: "\(pid):\(tree.text)") { return result }
            }
        }
        return nil
    }
    private static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private static func snapshot(_ element: AXUIElement, depth: Int, remaining: inout Int, deadline: Date) -> MeetingAccessibilityNode {
        guard remaining > 0, depth < 40, Date() < deadline else { return MeetingAccessibilityNode() }
        remaining -= 1
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        let parts = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, "AXHelp"].compactMap { attribute(element, $0) as? String }.filter { !$0.isEmpty }
        // Keep duplicate attributes out: a numeric badge often appears as both title and value.
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        let rawURL = attribute(element, "AXURL")
        let url = (rawURL as? URL)?.absoluteString ?? (rawURL as? String)
        let children = (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(300)
        let nodes = children.map { snapshot($0, depth: depth + 1, remaining: &remaining, deadline: deadline) }
        return MeetingAccessibilityNode(role: role, text: unique.joined(separator: " "), url: url, children: nodes)
    }
}

@MainActor final class MeetingDetector {
    private weak var model: AppModel?
    private var task: Task<Void, Never>?
    private var panel: NSPanel?
    private var announced: Set<String> = []
    private var absenceCount = 0
    private var onRecord: (() -> Void)?
    func start(model: AppModel, onRecord: @escaping () -> Void) {
        guard task == nil, !model.isVisualReview else { return }
        self.model = model; self.onRecord = onRecord
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
    }
    private func refresh() async {
        guard let model else { return }
        guard model.detectMeetings, AXIsProcessTrusted(), !model.isOccupied else {
            if !model.detectMeetings { model.detectedMeeting = nil }
            panel?.orderOut(nil)
            return
        }
        let browsers = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.brave.Browser", "org.chromium.Chromium", "org.mozilla.firefox"]
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
            guard let id = app.bundleIdentifier, browsers.contains(id) || MeetingDetection.nativeService(bundleID: id) != nil else { return nil }
            return (app.processIdentifier, id)
        }
        let detected = await Task.detached(priority: .utility) { MeetingAccessibilityReader.read(apps: apps) }.value
        guard model.detectMeetings, !model.isOccupied else { return }
        model.detectedMeeting = detected
        guard let detected else {
            absenceCount += 1
            panel?.orderOut(nil)
            // Ignore transient missing trees during tab changes; allow another call later.
            if absenceCount >= 6 { announced.removeAll() }
            return
        }
        absenceCount = 0
        guard !model.showRecordConsent, !announced.contains(detected.id) else { return }
        announced.insert(detected.id)
        show(detected)
    }
    private func show(_ meeting: DetectedMeeting) {
        panel?.orderOut(nil)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: MeetingDetectedView(meeting: meeting, record: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.onRecord?()
        }, dismiss: { [weak self] in self?.panel?.orderOut(nil) }))
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 380, y: frame.maxY - 175))
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }
}

struct MeetingDetectedView: View {
    let meeting: DetectedMeeting
    let record: () -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(meeting.service) detected", systemImage: "video").font(.headline)
            Text(meeting.participantCount.map { "\($0) participants including you. Review speakers before recording." } ?? "Start the note taker and set the speaker count.").font(.callout).foregroundStyle(.secondary)
            HStack { Button("Not now", action: dismiss); Spacer(); Button("Recording options…", action: record).buttonStyle(.borderedProminent) }
        }.padding(18).frame(width: 360, height: 150).background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14)).preferredColorScheme(.dark)
    }
}
