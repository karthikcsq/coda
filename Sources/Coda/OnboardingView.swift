import SwiftUI
import AVFoundation
import KeyboardShortcuts
import CodaCore

private typealias SetupState<Value> = SwiftUI.State<Value>

enum SetupStep: Int, CaseIterable {
    case welcome, model, shortcut, practice
    var title: String {
        switch self { case .welcome: "Welcome"; case .model: "Local speech"; case .shortcut: "Your shortcut"; case .practice: "Try it out" }
    }
}

struct OnboardingView: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    @SetupState private var step: SetupStep
    @SetupState private var acceptTerms = false
    @SetupState private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @SetupState private var permissionPending = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(model: AppModel, controller: DictationController, initialStep: SetupStep? = nil) {
        self.model = model; self.controller = controller
        let ready = controller.readiness(for: model)
        let firstStep: SetupStep = !ready.modelConsent || !ready.modelPrepared ? .welcome :
            (!ready.shortcutAssigned || (ready.modifierShortcut && !ready.accessibilityAllowed) ? .shortcut : .practice)
        _step = SetupState(initialValue: initialStep ?? firstStep)
        if model.isVisualReview { _microphoneStatus = SetupState(initialValue: controller.permissionGranted ? .authorized : .notDetermined) }
    }
    private var locked: Bool { model.settingsChangesLocked || controller.lifecycle.busy }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("coda", systemImage: "waveform.path").font(.system(size: 21, weight: .medium, design: .rounded)).foregroundStyle(CodaStyle.mint)
                Spacer()
                Text("\(step.rawValue + 1) of 4").font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                Button { controller.finishOnboarding() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CodaIconButtonStyle()).accessibilityLabel("Close setup and continue later").disabled(locked)
            }.padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 20)
            HStack(spacing: 8) {
                ForEach(SetupStep.allCases, id: \.rawValue) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(item.rawValue <= step.rawValue ? CodaStyle.mint : CodaStyle.hairline).frame(height: 3)
                        Text(item.title).font(.system(size: 11, weight: item == step ? .medium : .regular))
                            .foregroundStyle(item == step ? CodaStyle.ink : CodaStyle.muted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.horizontal, 30).padding(.bottom, 22)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch step {
                    case .welcome: welcome
                    case .model: localModel
                    case .shortcut: shortcut
                    case .practice: practice
                    }
                }.padding(.horizontal, 30).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(CodaStyle.hairline).frame(height: 1)
            HStack(spacing: 12) {
                if step != .welcome {
                    Button("Back") { step = SetupStep(rawValue: step.rawValue - 1) ?? .welcome }
                        .buttonStyle(CodaSecondaryButtonStyle()).disabled(locked)
                } else {
                    Button("Set up later") { controller.finishOnboarding() }.buttonStyle(CodaQuietButtonStyle()).disabled(locked)
                }
                Spacer()
                if step == .practice {
                    Button(controller.practiceCompleted ? "Start using Coda" : "Open workspace") { controller.finishOnboarding() }
                        .buttonStyle(CodaPrimaryButtonStyle()).disabled(locked)
                } else {
                    Button("Continue") { step = SetupStep(rawValue: step.rawValue + 1) ?? .practice }
                        .buttonStyle(CodaPrimaryButtonStyle()).disabled(locked || (step == .model && !(model.modelConsent && model.dictationModelReady)) ||
                            (step == .shortcut && (controller.shortcutLabel == "Choose a shortcut" || (controller.modifierShortcut && !controller.accessibility.trusted))))
                }
            }.padding(.horizontal, 30).padding(.vertical, 20)
        }
        .frame(width: 760, height: 610)
        .background(CodaStyle.canvas).foregroundStyle(CodaStyle.ink).preferredColorScheme(.dark)
        .interactiveDismissDisabled(locked)
        .animation(CodaStyle.motion(reduceMotion), value: step)
        .onAppear { controller.refreshAccessibility(); controller.practiceShortcutActive = step == .practice }
        .onChange(of: step) { _, value in controller.practiceShortcutActive = value == .practice }
        .onDisappear { controller.practiceShortcutActive = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAccessibility(); refreshMicrophoneStatus()
        }
        .task {
            while !Task.isCancelled {
                controller.refreshAccessibility(); refreshMicrophoneStatus()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    private func heading(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 29, weight: .medium, design: .rounded)).tracking(-0.6)
            Text(description).font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 18) {
                    heading("A little less typing.\nA lot more clarity.", "Speak naturally into your apps, or turn a conversation into notes you can use.")
                    Label("You decide when the microphone starts.", systemImage: "mic.slash")
                        .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.mint)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VoiceIllustration().frame(width: 180, height: 190).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("waveform", "Dictate into any app", "Use a shortcut to speak. Your text is saved before delivery.")
                feature("person.2", "Keep the conversation", "Record meetings with speaker labels and timestamps.")
                feature("lock.shield", "Stay in control", "Transcription runs locally. AI summaries and chat are optional hosted services.")
            }.codaCard(padding: 20)
        }
    }
    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(CodaStyle.mint).font(.system(size: 17, weight: .light)).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(CodaStyle.rowTitleFont)
                Text(detail).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var localModel: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Your speech, processed here.", "Prepare speech recognition once. No account or API key is needed for dictation.")
            VStack(alignment: .leading, spacing: 16) {
                feature("internaldrive", "Local speech recognition", "The first setup downloads and prepares Voz. This can take several minutes. Keep Coda open while it finishes.")
                Text("Powered by Desert Ant Labs. The SDK and models are source-available under separate terms. The SDK sends installation, device, app and model licensing metadata. Audio and transcripts are not part of that report.")
                    .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Link("Read model license", destination: URL(string: "https://license.desertant.com/1.0")!)
                    Link("Privacy policy", destination: URL(string: "https://desertant.com/privacy/")!)
                }.font(CodaStyle.secondaryFont).tint(CodaStyle.mint)
                if !model.modelConsent {
                    Toggle("I accept the model terms and allow downloads and use", isOn: $acceptTerms)
                        .font(CodaStyle.bodyFont).toggleStyle(.checkbox).disabled(locked || model.isVisualReview)
                }
                HStack {
                    CodaStatusChip(readiness: model.modelConsent && model.dictationModelReady ? .ready : .pending,
                                   text: model.modelConsent && model.dictationModelReady ? "Speech recognition is ready" : "Setup required")
                    Spacer()
                    Button(model.dictationModelReady ? "Prepare again" : "Prepare speech recognition") {
                        guard !model.isVisualReview else { return }
                        if acceptTerms { model.modelConsent = true }
                        model.prepareDictation()
                    }.buttonStyle(CodaPrimaryButtonStyle())
                        .disabled(locked || model.isVisualReview || (!model.modelConsent && !acceptTerms))
                }
                if model.busy {
                    if let progress = model.progress { ProgressView(value: progress).tint(CodaStyle.mint) }
                    else { ProgressView().controlSize(.small) }
                    Text(model.status).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                    Button("Cancel preparation") { model.cancel() }.buttonStyle(CodaQuietButtonStyle())
                }
                if let error = model.error {
                    CodaNotice(kind: .caution, text: error)
                    Button("Dismiss error") { model.dismissError() }.buttonStyle(CodaQuietButtonStyle())
                }
            }.codaCard()
        }
    }
    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("One shortcut. Anywhere.", "Click in a text field, then use your shortcut. Coda never presses Return or sends your message.")
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your dictation shortcut").font(CodaStyle.rowTitleFont)
                        Text(controller.shortcutLabel).font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(CodaStyle.mint)
                    }
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .codaDictation)
                        .frame(width: 170).disabled(locked || model.isVisualReview || controller.modifierShortcut)
                }
                HStack(spacing: 10) {
                    Button("Use Control + Option") { controller.modifierShortcut = true; controller.mode = .hold }
                        .buttonStyle(CodaSecondaryButtonStyle()).disabled(locked || model.isVisualReview)
                    Button("Use custom shortcut") { controller.modifierShortcut = false }
                        .buttonStyle(CodaQuietButtonStyle()).disabled(locked || model.isVisualReview)
                }
                if controller.modifierShortcut {
                    Text(controller.modifierShortcutStatus).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                Picker("Behavior", selection: $controller.mode) {
                    Text("Hold to talk").tag(DictationMode.hold)
                    Text("Press to start / stop").tag(DictationMode.toggle)
                }.pickerStyle(.segmented).disabled(locked || model.isVisualReview)
                Divider().opacity(0.4)
                AccessibilitySetupView(controller: controller).disabled(locked || model.isVisualReview)
                Text("Accessibility enables automatic insertion. A custom shortcut can work without it; copy the result yourself. Fn-only and Caps Lock-only bindings are unsupported.")
                    .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
            }.codaCard()
        }
    }
    private var practice: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(controller.practiceCompleted ? "That's your first dictation." : "Give it a try.", "Try a short sentence here. Nothing is pasted into another app. Your result is saved in History.")
            if !model.modelConsent || !model.dictationModelReady {
                CodaNotice(kind: .caution, text: "Prepare speech recognition before practicing.")
                Button("Prepare local speech") { step = .model }.buttonStyle(CodaPrimaryButtonStyle())
            } else if microphoneStatus != .authorized {
                VStack(alignment: .leading, spacing: 14) {
                    feature("mic", "Allow microphone access", "Coda only records when you start dictation or a meeting. No recording begins when you enable access.")
                    Button(microphoneStatus == .notDetermined ? "Enable microphone" : "Open microphone settings") { requestMicrophone() }
                        .buttonStyle(CodaPrimaryButtonStyle()).disabled(permissionPending || model.isVisualReview || locked)
                }.codaCard()
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(controller.lifecycle.phase == .listening && controller.practiceSession ? "Listening" : "Practice dictation", systemImage: "mic")
                            .font(CodaStyle.sectionFont).foregroundStyle(CodaStyle.mint)
                        Spacer()
                        if controller.lifecycle.phase == .processing || controller.lifecycle.phase == .arming { ProgressView().controlSize(.small) }
                    }
                    Text(controller.practiceText.isEmpty ? "Try saying: “Let's meet on Thursday at three.”" : controller.practiceText)
                        .font(.system(size: 20, weight: .regular, design: .rounded)).lineSpacing(5)
                        .foregroundStyle(controller.practiceText.isEmpty ? CodaStyle.muted : CodaStyle.ink)
                        .textSelection(.enabled).frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    HStack(spacing: 12) {
                        Button(controller.practiceSession && controller.lifecycle.phase == .listening ? "Stop & transcribe" : controller.practiceCompleted ? "Try again" : "Start practice") { controller.practice() }
                            .buttonStyle(CodaPrimaryButtonStyle())
                            .disabled(model.isVisualReview || model.meetingOperationInProgress || (controller.lifecycle.busy && !(controller.practiceSession && controller.lifecycle.phase == .listening)))
                        if controller.practiceSession && controller.lifecycle.busy {
                            Button("Cancel") { controller.cancel() }.buttonStyle(CodaQuietButtonStyle())
                        }
                    }
                    if controller.shortcutLabel != "Choose a shortcut" {
                        Text("Or use " + controller.shortcutLabel + (controller.mode == .hold ? ". Hold to speak, release to finish." : ". Press to start, then press again to finish."))
                            .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Button("Choose a keyboard shortcut") { step = .shortcut }.buttonStyle(CodaQuietButtonStyle()).disabled(locked)
                    }
                    if controller.practiceSession || !controller.practiceMessage.isEmpty {
                        Text(controller.practiceSession ? controller.message : controller.practiceMessage).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }.codaCard(padding: 22)
            }
            if controller.practiceCompleted {
                feature("checkmark.circle", "Take Coda into your next app", controller.shortcutLabel == "Choose a shortcut" ? "Choose a shortcut in the previous step to dictate into your apps. Coda stays in the menu bar when you close its window." : "Focus a message or document and use \(controller.shortcutLabel). Close the main window any time; Coda stays in your menu bar.")
            }
        }
    }
    private func refreshMicrophoneStatus() {
        microphoneStatus = model.isVisualReview ? (controller.permissionGranted ? .authorized : .notDetermined) : AVCaptureDevice.authorizationStatus(for: .audio)
    }
    private func requestMicrophone() {
        guard !model.isVisualReview, !locked else { return }
        if microphoneStatus == .notDetermined {
            permissionPending = true
            Task { let allowed = await AVCaptureDevice.requestAccess(for: .audio); permissionPending = false; microphoneStatus = allowed ? .authorized : .denied }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
