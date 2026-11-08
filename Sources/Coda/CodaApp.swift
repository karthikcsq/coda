import SwiftUI
import AppKit
import ApplicationServices
import CodaCore

// Disambiguate the stable property wrapper from the macOS 27 State macro; CLT omits SwiftUIMacros.
private typealias ViewState<Value> = SwiftUI.State<Value>

@main struct CodaApp: App {
    @ViewState<AppModel> private var model = Self.makeModel()
    @ViewState<DictationController> private var dictation = Self.makeDictation()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private static func makeDictation() -> DictationController {
        DictationController(preview: ProcessInfo.processInfo.arguments.contains("--ui-preview"))
    }
    private static func makeModel() -> AppModel {
        if ProcessInfo.processInfo.arguments.contains("--insertion-diagnostics") {
            print("Accessibility trusted: \(AXIsProcessTrusted())")
            print("Automatic insertion enabled: \(UserDefaults.standard.object(forKey: "dictationAutoInsert") as? Bool ?? true)")
            exit(0)
        }
        return AppModel()
    }
    var body: some Scene {
        Window("Coda", id: "main") {
            WorkspaceView(model: model, controller: dictation, delegate: delegate)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear { delegate.model = model; delegate.dictation = dictation; dictation.attach(model)
                    delegate.meetingDetector.start(model: model) {
                        delegate.reopenMain?()
                        dictation.workspaceSection = "Meetings"
                        model.requestMeetingRecording()
                    }
                }
        }.defaultSize(width: 1350, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Import Audio…") { model.importAudio() }.keyboardShortcut("o").disabled(model.isOccupied) }
            CodaSettingsCommands(model: model)
        }
        MenuBarExtra {
            RecordingMenu(model: model, dictation: dictation, delegate: delegate)
        } label: {
            Label(model.recording ? "Coda • REC" : dictation.lifecycle.phase == .listening ? "Coda • MIC" : "Coda", systemImage: model.recording || dictation.lifecycle.phase == .listening ? "record.circle.fill" : "waveform.path")
        }
    }
}
@MainActor struct MeetingMenuAction {
    static func perform(recording: Bool, occupied: Bool, open: () -> Void, start: () -> Void, stop: () -> Void) {
        open()
        if recording { stop() }
        else if !occupied { start() }
    }
}
struct RecordingMenu: View {
    let model: AppModel
    @Bindable var dictation: DictationController
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    private func openCoda() { delegate.showMain { openWindow(id: "main") } }
    var body: some View {
        Button("Open Coda") { openCoda() }
        Button(dictation.lifecycle.phase == .listening ? "Stop Dictation" : "Start Dictation") {
            if model.modelConsent && model.dictationModelReady { dictation.button() }
            else { dictation.showOnboarding = true; openCoda() }
        }.disabled(model.meetingOperationInProgress || (dictation.lifecycle.busy && dictation.lifecycle.phase != .listening))
        Button("Correct Last Dictation… (\(dictation.correctionShortcutLabel))") { dictation.correctLastDictation() }
            .disabled(dictation.lifecycle.busy)
        Button("Setup Guide") { dictation.showOnboarding = true; openCoda() }.disabled(model.settingsChangesLocked)
        Button(model.recording ? "Stop & Save Meeting" : "Start Meeting") {
            MeetingMenuAction.perform(recording: model.recording, occupied: model.isOccupied, open: {
                model.closeSettings(); dictation.workspaceSection = "Meetings"; openCoda()
            }, start: { model.requestMeetingRecording() }, stop: { model.stopRecording() })
        }.disabled(model.isOccupied && !model.recording)
        if dictation.lifecycle.busy { Button("Cancel Dictation") { dictation.cancel() } }
        Divider()
        Button("Quit Coda") { NSApp.terminate(nil) }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let meetingDetector = MeetingDetector()
    var reopenMain: (() -> Void)?
    func showMain(open: () -> Void) {
        open() // SwiftUI Window's fixed id reuses the same main window.
        NSApp.activate(ignoringOtherApps: true)
        raiseExistingMain()
        DispatchQueue.main.async { [weak self] in self?.raiseExistingMain() }
    }
    func raiseExistingMain() {
        guard let window = NSApp.windows.first(where: { $0.title == "Coda" && !($0 is NSPanel) }) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenMain?()
        return false
    }
    var model: AppModel?
    var dictation: DictationController?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.isVisualReview, model.isOccupied else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Finish the current operation before quitting"
        alert.informativeText = model.recording ? "Stop recording so Coda can save your audio first." : "Cancel processing or wait for it to finish."
        alert.runModal()
        return .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
struct CodaSettingsCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "main")
                model.openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }.keyboardShortcut(",")
        }
    }
}
