import AppKit
import Observation
import OSLog
@preconcurrency import KeyboardShortcuts

/// AppKit owns the status item's menu and dispatches explicit target/action
/// commands after tracking ends. No SwiftUI scene environment is needed here.
@MainActor final class StatusMenuController: NSObject, NSMenuDelegate {
    enum Command: Int { case open, dictate, correct, setup, meeting, cancel, releases, quit, about }
    let menu = NSMenu()
    private let logger = Logger(subsystem: BuildIdentity.channel.bundleIdentifier, category: "StatusMenu")
    private var item: NSStatusItem?
    private var tracking = false
    private let model: AppModel
    private let dictation: DictationController
    private weak var delegate: AppDelegate?

    init(model: AppModel, dictation: DictationController, delegate: AppDelegate, install: Bool = true) {
        self.model = model; self.dictation = dictation; self.delegate = delegate
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        if install {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            self.item = item
            item.button?.target = self
            item.button?.action = #selector(showMenu(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            updateStatus()
        }
        rebuild()
    }
    @objc private func showMenu(_ sender: NSStatusBarButton) {
        if tracking { menu.cancelTracking(); return }
        rebuild()
        tracking = true
        defer { tracking = false }
        // Track the ordinary AppKit popup directly instead of relying on the
        // status item's automatic menu attachment and its remote presentation.
        MenuShortcutSuspension.perform {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
        }
    }
    private func updateStatus() {
        withObservationTracking {
            let recording = model.recording
            let listening = dictation.lifecycle.phase == .listening
            if BuildIdentity.isDevelopment {
                item?.button?.title = recording ? "Coda Dev REC" : listening ? "Coda Dev MIC" : "Coda Dev"
                item?.button?.image = nil
            } else {
                item?.button?.title = ""
                item?.button?.image = NSImage(systemSymbolName: recording || listening ? "record.circle.fill" : "waveform.path", accessibilityDescription: BuildIdentity.name)
                item?.button?.image?.isTemplate = true
            }
            item?.button?.toolTip = BuildIdentity.name
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.updateStatus() }
        }
    }
    func menuWillOpen(_ menu: NSMenu) { logger.notice("Menu opened") }
    func menuDidClose(_ menu: NSMenu) { logger.notice("Menu closed") }
    func menuNeedsUpdate(_ menu: NSMenu) { if !tracking { rebuild() } }
    func rebuild() {
        menu.removeAllItems()
        add("Open \(BuildIdentity.name)", .open)
        add(dictation.lifecycle.phase == .listening ? "Stop Dictation" : "Start Dictation", .dictate,
            enabled: !model.meetingOperationInProgress && (!dictation.lifecycle.busy || dictation.lifecycle.phase == .listening))
        add("Correct Last Dictation… (\(dictation.correctionShortcutLabel))", .correct, enabled: !dictation.lifecycle.busy)
        add("Setup Guide", .setup, enabled: !model.settingsChangesLocked)
        add(model.recording ? "Stop & Save Meeting" : "Start Meeting", .meeting, enabled: !model.isOccupied || model.recording)
        if dictation.lifecycle.busy { add("Cancel Dictation", .cancel) }
        menu.addItem(.separator())
        add("About \(BuildIdentity.name)…", .about)
        if !BuildIdentity.isDevelopment { add("Production Releases…", .releases) }
        add("Quit \(BuildIdentity.name)", .quit)
    }
    private func add(_ title: String, _ command: Command, enabled: Bool = true) {
        let row = NSMenuItem(title: title, action: #selector(selected(_:)), keyEquivalent: "")
        row.target = self; row.tag = command.rawValue; row.isEnabled = enabled
        menu.addItem(row)
    }
    @objc private func selected(_ sender: NSMenuItem) {
        guard sender.isEnabled, let command = Command(rawValue: sender.tag) else { return }
        logger.notice("Menu selected command \(command.rawValue, privacy: .public)")
        // Presenting a window or permission sheet during menu tracking can cause
        // the action to disappear behind the menu. Execute once tracking unwinds.
        DispatchQueue.main.async { [weak self] in self?.perform(command) }
    }
    private func openMain() {
        guard let delegate else { return }
        if delegate.raiseExistingMain() { NSApp.activate(ignoringOtherApps: true) }
        else { delegate.reopenMain?() }
    }
    private func perform(_ command: Command) {
        logger.notice("Menu dispatched command \(command.rawValue, privacy: .public)")
        switch command {
        case .open: openMain()
        case .dictate:
            guard !model.meetingOperationInProgress,
                  !dictation.lifecycle.busy || dictation.lifecycle.phase == .listening else { return }
            if model.modelConsent && model.dictationModelReady { dictation.button() }
            else { dictation.showOnboarding = true; openMain() }
        case .correct:
            guard !dictation.lifecycle.busy else { return }
            dictation.correctLastDictation()
        case .setup:
            guard !model.settingsChangesLocked else { return }
            dictation.showOnboarding = true; openMain()
        case .meeting:
            MeetingMenuAction.perform(recording: model.recording, occupied: model.isOccupied, open: {
                model.closeSettings(); dictation.workspaceSection = "Meetings"; openMain()
            }, start: { model.requestMeetingRecording() }, stop: { model.stopRecording() })
        case .cancel: dictation.cancel()
        case .releases: NSWorkspace.shared.open(URL(string: "https://github.com/karthikcsq/coda/releases")!)
        case .about:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        case .quit: NSApp.terminate(nil)
        }
    }
}

/// KeyboardShortcuts' tracking-mode observer drains/reposts the whole AppKit
/// event queue. Menu clicks must go directly to AppKit instead. Restore exactly
/// the prior shortcut state after tracking exits, including cancellation.
@MainActor enum MenuShortcutSuspension {
    @discardableResult static func perform<Result>(_ tracking: () throws -> Result) rethrows -> Result {
        let wasEnabled = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
        defer { KeyboardShortcuts.isEnabled = wasEnabled }
        return try tracking()
    }
}
