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
        Window(BuildIdentity.name, id: "main") {
            WorkspaceView(model: model, controller: dictation, delegate: delegate)
                .frame(minWidth: 980, minHeight: 680)
                .background(MainWindowReader { delegate.retainMainWindow($0) })
                .onAppear { delegate.model = model; delegate.dictation = dictation; dictation.attach(model); delegate.installStatusMenu(model: model, dictation: dictation)
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

    }
}
@MainActor struct MeetingMenuAction {
    static func perform(recording: Bool, occupied: Bool, open: () -> Void, start: () -> Void, stop: () -> Void) {
        open()
        if recording { stop() }
        else if !occupied { start() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let meetingDetector = MeetingDetector()
    private var statusMenu: StatusMenuController?
    func installStatusMenu(model: AppModel, dictation: DictationController) {
        guard statusMenu == nil else { return }
        statusMenu = StatusMenuController(model: model, dictation: dictation, delegate: self)
    }
    var reopenMain: (() -> Void)?
    private var mainWindow: NSWindow?
    func retainMainWindow(_ window: NSWindow) {
        guard !(window is NSPanel), window.styleMask.contains(.titled) else { return }
        // Keep the real window available after the close button removes it from
        // NSApp.windows. Reopening an already-running menu app must show it again.
        window.isReleasedWhenClosed = false
        mainWindow = window
    }
    func showMain(open: () -> Void) {
        open() // SwiftUI Window's fixed id reuses the same main window.
        NSApp.activate(ignoringOtherApps: true)
        raiseExistingMain()
        DispatchQueue.main.async { [weak self] in self?.raiseExistingMain() }
    }
    @discardableResult func raiseExistingMain() -> Bool {
        guard let window = mainWindow ?? NSApp.windows.first(where: { $0.title == BuildIdentity.name && !($0 is NSPanel) }) else { return false }
        retainMainWindow(window)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if mainWindow != nil, raiseExistingMain() {
            sender.activate(ignoringOtherApps: true)
            return false // The retained window handled this request.
        }
        reopenMain?()
        return true // Allow SwiftUI's normal reopen path when no window was captured.
    }
    var model: AppModel?
    var dictation: DictationController?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.isVisualReview, model.isOccupied || dictation?.lifecycle.busy == true else { return .terminateNow }
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

/// Capture the actual scene window, rather than relying on title lookup or onAppear timing.
private struct MainWindowReader: NSViewRepresentable {
    let receive: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowView { WindowView(receive: receive) }
    func updateNSView(_ view: WindowView, context: Context) { view.receive = receive }
    final class WindowView: NSView {
        var receive: (NSWindow) -> Void
        init(receive: @escaping (NSWindow) -> Void) { self.receive = receive; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { receive(window) }
        }
    }
}
