import Testing
import AppKit
import ApplicationServices
@testable import Coda

@Test(.enabled(if: AXIsProcessTrusted() && ProcessInfo.processInfo.environment["CODA_INSERTION_FIXTURE"] == "1", "Opt-in disposable fixture test; requires existing test-runner trust.")) @MainActor
func testSyntheticFixtureInsertion() async throws {
        // Separate test process must have its own trust. Never reuse or alter Coda's TCC identity.
        _ = NSApplication.shared
        _ = NSApp.setActivationPolicy(.prohibited) // The test runner must never compete with its fixture for keyboard focus.
        guard let fixture = NSRunningApplication.runningApplications(withBundleIdentifier: "app.coda.synthetic-insertion-fixture").max(by: { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }),
              fixture.bundleURL?.resolvingSymlinksInPath() == URL(fileURLWithPath: "/tmp/CodaInsertionFixture.app").resolvingSymlinksInPath() else { Issue.record("Expected disposable fixture not running."); return }
        defer { _ = fixture.terminate() }
        try await Task.sleep(for: .seconds(1))
        _ = fixture.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        try await Task.sleep(for: .milliseconds(500))
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "app.coda.synthetic-insertion-fixture" else {
            Issue.record("Disposable synthetic fixture is not focused; no other app inspected."); return
        }
        let insertion = DictationInsertion()
        let output = "/tmp/coda-insertion-fixture-\(app.processIdentifier).txt"
        #expect(try String(contentsOfFile: output, encoding: .utf8) == "Before ")
        for cycle in 1...3 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { Issue.record("Fixture lost focus to \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"); stopping."); return }
            insertion.captureTarget()
            try await Task.sleep(for: .milliseconds(200))
            _ = await insertion.insertWithFallback("Coda synthetic sentence. ")
            #expect(insertion.deliveryAttempted, Comment(rawValue: insertion.reason))
            _ = await insertion.insertWithFallback("MUST NOT DUPLICATE")
            try await Task.sleep(for: .milliseconds(150))
            let actual = try String(contentsOfFile: output, encoding: .utf8)
            guard actual == "Before " + String(repeating: "Coda synthetic sentence. ", count: cycle) else {
                Issue.record("Unexpected fixture contents after cycle \(cycle): \(actual)"); return
            }
            insertion.clear()
        }
        // Read the fixture's own model, rather than accepting a cached AX wrapper.
        try await Task.sleep(for: .milliseconds(200))
        let value = try String(contentsOfFile: output, encoding: .utf8)
        #expect(value == "Before " + String(repeating: "Coda synthetic sentence. ", count: 3))
        insertion.captureTarget(); insertion.clear()
        #expect(await !insertion.insertWithFallback("MUST NOT APPEAR"))
    }
