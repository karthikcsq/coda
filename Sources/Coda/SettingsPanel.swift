import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AVFoundation
import CodaCore

private typealias PanelState<Value> = SwiftUI.State<Value>

/// A single main-window panel. System approvals remain explicit OS actions.
struct SettingsPanel: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    @PanelState private var approveAuto = false
    @PanelState private var approveModels = false
    @PanelState private var loginEnabled = SMAppService.mainApp.status == .enabled
    @PanelState private var loginMessage = ""
    @PanelState private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var locked: Bool { model.settingsChangesLocked || controller.lifecycle.busy }
    private var microphoneReadiness: CodaStatusChip.Readiness {
        switch microphoneStatus { case .authorized: .ready; case .denied, .restricted: .blocked; default: .pending }
    }
    private var microphoneState: String {
        switch microphoneStatus { case .authorized: "Enabled"; case .denied: "Off"; case .restricted: "Restricted"; default: "Not requested" }
    }
    var body: some View {
        VStack(spacing: 0) {
            CodaPageHeader(icon: "gearshape", title: "Settings",
                           subtitle: "Dictation, permissions, local models and optional summaries.") {
                Button { closePanel() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CodaIconButtonStyle()).help("Close settings").accessibilityLabel("Close settings")
            }
            .padding(.horizontal, 34).padding(.top, 28).padding(.bottom, 22)
            Rectangle().fill(CodaStyle.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    HStack(spacing: 18) {
                        jump("Dictation", "dictation", proxy)
                        jump("System", "system", proxy)
                        jump("Models", "models", proxy)
                        jump("Summaries", "summaries", proxy)
                        Spacer()
                    }.padding(.horizontal, 34).padding(.vertical, 14)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if locked {
                                HStack(spacing: 12) {
                                    Image(systemName: model.recording ? "record.circle.fill" : "hourglass")
                                        .foregroundStyle(model.recording ? .red : CodaStyle.muted).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("An operation is in progress").font(CodaStyle.rowTitleFont)
                                        Text("Setting changes are paused. Your recording or processing continues.")
                                            .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 12)
                                    Button("Return to workspace") { closePanel() }.buttonStyle(CodaSecondaryButtonStyle())
                                }
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(CodaStyle.caution.opacity(0.075), in: RoundedRectangle(cornerRadius: CodaStyle.radius))
                            }
                            dictation.id("dictation")
                            system.id("system")
                            models.id("models")
                            summaries.id("summaries")
                            Text("Coda app code: MIT. Third-party SDK/model terms apply separately. History and recordings are local and unencrypted; protect your Mac account and disk.").font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                            if model.isVisualReview { Text("Synthetic UI preview · recording, downloads, clipboard and system changes are disabled.").font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted) }
                        }.padding(.horizontal, 34).padding(.top, 8).padding(.bottom, 32).frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("coda.settings.scroll")
                }
            }
        }.background(CodaStyle.canvas).preferredColorScheme(.dark).environment(\.colorScheme, .dark).foregroundStyle(Color(white: 0.88))
        .accessibilityIdentifier("coda.settings.panel")
        .onAppear { refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshStatus() }
        .alert("Enable automatic transcript sharing?", isPresented: $approveAuto) {
            Button("Cancel", role: .cancel) {}
            Button("Enable automatic summaries") { if !locked && !model.isVisualReview { model.autoSummary = true } }
        } message: { Text("Every future imported or recorded meeting that you process will send its full transcript and speaker names to OpenAI using your key. Audio stays local. This may include sensitive content and API charges apply. Existing meetings are not sent by enabling this setting. You can turn this off any time.") }
        .alert("Accept model terms and allow downloads?", isPresented: $approveModels) {
            Button("Cancel", role: .cancel) {}
            Button("Accept & enable") { if !locked && !model.isVisualReview { model.modelConsent = true } }
        } message: { Text("You are accepting Desert Ant Labs Source-Available License v1.0 for model use, including usage limits, attribution, restrictions and background installation/device/app/model licensing metadata. Downloads begin only when you prepare dictation or process a meeting.") }
    }
    private var dictation: some View {
        group("Dictation", "Available from the menu bar. Listening starts only when you ask.", icon: "waveform") {
            row("Keyboard shortcut", "Choose a combination that does not overlap with Wispr or your other apps.") {
                Picker("Shortcut", selection: $controller.modifierShortcut) {
                    Text("Control + Option").tag(true)
                    Text("Custom shortcut").tag(false)
                }.labelsHidden().frame(width: 170).disabled(locked || model.isVisualReview)
            }
            if !controller.modifierShortcut {
                KeyboardShortcuts.Recorder("", name: .codaDictation).frame(width: 170).disabled(locked || model.isVisualReview)
            }
            if controller.modifierShortcut { Text(controller.modifierShortcutStatus).font(.system(size: 11)).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                Button("Use ⌃⌥⌘D suggestion") { controller.useSuggestedShortcut() }
                    .buttonStyle(CodaSecondaryButtonStyle()).disabled(locked || model.isVisualReview)
                Text("Checks enabled macOS shortcuts; other apps’ custom bindings cannot all be detected.")
                    .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
            Divider().opacity(0.4)
            row("Shortcut behavior", "Press to start and stop, or hold to talk.") {
                Picker("Shortcut behavior", selection: $controller.mode) { Text("Toggle").tag(DictationMode.toggle); Text("Hold").tag(DictationMode.hold) }.labelsHidden().frame(width: 170).disabled(locked)
            }
            row("Automatic cleanup", "Smart formats numbers and math, removes speech fillers, adds punctuation and clear lists, and applies explicit corrections locally. Originals remain in History.") {
                Picker("Automatic cleanup", selection: $controller.cleanupMode) {
                    Text("None · raw text").tag(DictationCleanupMode.none)
                    Text("Light · rules").tag(DictationCleanupMode.light)
                    Text("Smart · local model").tag(DictationCleanupMode.smart)
                }.labelsHidden().frame(width: 170).disabled(locked)
            }
            Text(controller.smartFormatter.status).font(.system(size: 11)).foregroundStyle(.secondary)
            row("Automatic insertion", "Checks the original field and preserves newer clipboard changes. Never presses Return.") {
                Toggle("Automatic insertion", isOn: $controller.autoInsert).labelsHidden().toggleStyle(.switch).disabled(locked)
            }
            row("Learn from corrections", "Suggest names and unfamiliar terms you correct after dictation. Review them in Dictionary before they affect recognition.") {
                Toggle("Learn from corrections", isOn: $controller.learnWords).labelsHidden().toggleStyle(.switch).disabled(locked || model.isVisualReview)
            }
            row("Learn from my edits", "Save dictation audio, original text, inserted text and observed edits on this Mac. Smart cleanup learns from your text fixes after a quality check. Speech recognition and meeting models stay generic.") {
                Toggle("Learn from my edits", isOn: Binding(get: { controller.personalTuning.enabled }, set: { controller.personalTuning.enabled = $0 }))
                    .labelsHidden().toggleStyle(.switch).disabled(locked || model.isVisualReview)
            }
            Text(controller.personalTuning.summary).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Fine-tune cleanup") { controller.personalTuning.tuneNow() }
                    .buttonStyle(CodaSecondaryButtonStyle())
                    .disabled(locked || model.isVisualReview || controller.personalTuning.running || controller.personalTuning.editCount == 0)
                Button("Use open-weight model") { controller.personalTuning.reset() }
                    .buttonStyle(CodaSecondaryButtonStyle())
                    .disabled(locked || model.isVisualReview || controller.personalTuning.running || !controller.personalTuning.personalInstalled)
            }
            HStack(spacing: 10) {
                Button("Open dictionary") { model.closeSettings(); controller.workspaceSection = "Dictionary" }
                    .buttonStyle(CodaSecondaryButtonStyle())
                Button("Preview overlay") { controller.previewOverlay() }
                    .buttonStyle(CodaSecondaryButtonStyle()).disabled(locked)
            }
            Text("Fn-only and Caps Lock-only shortcuts are not supported. Dictation ends after two minutes at most. Click inside the destination text field before using the shortcut.").font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var system: some View {
        group("System & permissions", "Coda checks access here. macOS approval stays in System Settings.", icon: "laptopcomputer") {
            if model.isVisualReview { Text("Preview-process status only; this does not verify the installed Coda app’s access.").font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted) }
            AccessibilitySetupView(controller: controller).disabled(locked)
            Divider().opacity(0.4)
            row("Microphone", microphoneDescription, status: CodaStatusChip(readiness: microphoneReadiness, text: microphoneState)) {
                Button("Open macOS settings") { openSystem("Privacy_Microphone") }
                    .buttonStyle(CodaSecondaryButtonStyle()).disabled(model.isVisualReview || locked)
            }
            row("System / meeting audio", "macOS requests access when you start a recording with system audio enabled. Coda cannot read this state in advance.",
                status: CodaStatusChip(readiness: .pending, text: "Asked when needed")) {
                Button("Open macOS settings") { openSystem("Privacy_ScreenCapture") }
                    .buttonStyle(CodaSecondaryButtonStyle()).disabled(model.isVisualReview || locked)
            }
            row("Detect video meetings", "Suggest recording for Meet, Zoom, and Teams using visible meeting controls. Reads participant counts when available; requires Accessibility.") {
                Toggle("Detect video meetings", isOn: $model.detectMeetings).labelsHidden().toggleStyle(.switch).disabled(locked || model.isVisualReview)
            }
            Divider().opacity(0.4)
            row("Launch at login", "Optional. Coda remains idle until you start dictation or a meeting.") {
                Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: setLogin)).labelsHidden().toggleStyle(.switch).disabled(locked || model.isVisualReview)
            }
            if !loginMessage.isEmpty { CodaNotice(kind: .caution, text: loginMessage) }
        }
    }
    private var models: some View {
        group("Local models", "Powered by Desert Ant Labs · Voz transcription and Who speaker labels", icon: "internaldrive") {
            Text("Voz transcribes speech; Who labels up to four speakers. The SDK and weights are source-available, not open source. First use downloads and compiles models locally, requiring time and disk space.").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Text("The SDK sends licensing metadata in the background, including installation/device and app/model information. Audio and transcripts are not included in that licensing report.").font(CodaStyle.secondaryFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Link("License v1.0", destination: URL(string: "https://license.desertant.com/1.0")!); Link("Privacy policy", destination: URL(string: "https://desertant.com/privacy/")!) }
            Toggle("Allow model downloads and use under these terms", isOn: Binding(get: { model.modelConsent }, set: { if $0 { approveModels = true } else { model.modelConsent = false } })).disabled(locked || model.isVisualReview)
            HStack(spacing: 12) {
                CodaStatusChip(readiness: model.dictationModelReady ? .ready : .pending,
                               text: model.dictationModelReady ? "Voz is ready" : "Voz needs preparation")
                Spacer(minLength: 12)
                Button("Prepare local dictation") { model.prepareDictation() }
                    .buttonStyle(CodaPrimaryButtonStyle()).disabled(!model.modelConsent || model.isOccupied || locked)
            }
            DisclosureGroup("Supported languages and storage") {
                Text("Bulgarian, Czech, Danish, German, Greek, English, Spanish, Estonian, Finnish, French, Croatian, Hungarian, Italian, Lithuanian, Latvian, Maltese, Dutch, Polish, Portuguese, Romanian, Russian, Slovak, Slovenian, Swedish, Ukrainian. Unsupported languages can produce incorrect text.").font(.system(size: 12))
                Text("History: ~/Library/Application Support/Coda/Meetings\nDictations: ~/Library/Application Support/Coda/Dictations\nModels: ~/Library/Application Support/Coda/Models").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
    private var summaries: some View {
        group("Meeting summaries", "Optional OpenAI processing · local dictation never uses OpenAI", icon: "sparkles") {
            CodaNotice(kind: .caution, text: "Your full transcript and speaker names leave this Mac for OpenAI. Raw audio stays local. API charges apply. Review sensitive conversations before sending; OpenAI data policies apply even with response storage disabled.")
            row("API configuration", "Add OPENAI_API_KEY and optionally OPENAI_MODEL to your .env. Keys are never displayed or logged.") {
                Button("Choose .env…") { model.chooseEnv() }
                    .buttonStyle(CodaSecondaryButtonStyle()).disabled(locked || model.isVisualReview)
            }
            Text(model.envPath).font(.system(size: 11, design: .monospaced)).foregroundStyle(CodaStyle.muted).textSelection(.enabled).lineLimit(2)
            Toggle("Automatically send future transcripts to OpenAI", isOn: Binding(get: { model.autoSummary }, set: { if $0 { approveAuto = true } else { model.autoSummary = false } })).disabled(locked || model.isVisualReview)
            Link("OpenAI API data policies", destination: URL(string: "https://platform.openai.com/docs/guides/your-data")!)
        }
    }
    private var microphoneDescription: String {
        switch microphoneStatus { case .authorized: "Microphone access enabled · system default input"; case .denied: "Microphone access is off in macOS settings"; case .restricted: "Microphone access is restricted by macOS"; default: "Not requested yet · macOS asks when you first record" }
    }
    private func closePanel() {
        if model.recording || model.busy || model.startingCapture { controller.workspaceSection = "Meetings" }
        model.closeSettings()
    }
    private func refreshStatus() { controller.refreshAccessibility(); microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio); loginEnabled = SMAppService.mainApp.status == .enabled }
    private func openSystem(_ pane: String) { guard !model.isVisualReview, !locked, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) else { return }; NSWorkspace.shared.open(url) }
    private func setLogin(_ desired: Bool) {
        guard !model.isVisualReview, !locked else { return }
        do { if desired { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled; loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Approve Coda in System Settings → General → Login Items." : "" }
        catch { loginMessage = "Could not change login launch. Check Coda’s location and macOS Login Items."; loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    /// Jump links scroll instantly when Reduce Motion is on.
    private func jump(_ title: String, _ id: String, _ proxy: ScrollViewProxy) -> some View {
        Button(title) { withAnimation(CodaStyle.motion(reduceMotion)) { proxy.scrollTo(id, anchor: .top) } }
            .buttonStyle(CodaQuietButtonStyle())
            .accessibilityLabel("Jump to " + title + " settings")
    }
    private func group<Content: View>(_ title: String, _ subtitle: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        // Build eagerly: CodaSection stores an escaping view builder.
        let built = content()
        return CodaSection(title: title, subtitle: subtitle, icon: icon) { built }
    }
    private func row<Action: View>(_ title: String, _ subtitle: String, status: CodaStatusChip? = nil, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 9) {
                    Text(title).font(CodaStyle.rowTitleFont)
                    if let status { status }
                }
                Text(subtitle).font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
        }
    }
}
