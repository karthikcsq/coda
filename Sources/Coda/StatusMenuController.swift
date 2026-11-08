import AppKit
import Observation

/// AppKit owns the status item's menu and dispatches explicit target/action
/// commands after tracking ends. No SwiftUI scene environment is needed here.
@MainActor final class StatusMenuController: NSObject, NSMenuDelegate {
    enum Command: Int { case open, dictate, correct, setup, meeting, cancel, releases, quit }
    let menu = NSMenu()
    private var item: NSStatusItem?
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
            self.item = item; item.menu = menu
            updateStatus()
        }
        rebuild()
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
    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let info = NSMenuItem(title: "\(BuildIdentity.name) \(version) · \(BuildIdentity.revision)", action: nil, keyEquivalent: "")
        info.isEnabled = false; menu.addItem(info)
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
        case .quit: NSApp.terminate(nil)
        }
    }
}
