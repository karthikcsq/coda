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
private let accent = Color(red: 0.55, green: 0.78, blue: 0.72)

struct ContentView: View {
    @Bindable var model: AppModel
    @Bindable var dictation: DictationController
    var showsMeetingSidebar: Bool
    @ViewState<String> private var tab = "Transcript"
    @ViewState<Bool> private var deleteConfirmation = false
    init(model: AppModel, dictation: DictationController, initialTab: String = "Transcript", showsMeetingSidebar: Bool = true) {
        self.model = model; self.dictation = dictation
        self.showsMeetingSidebar = showsMeetingSidebar
        _tab = ViewState(initialValue: initialTab)
    }
    var body: some View {
        HStack(spacing: 0) {
            if showsMeetingSidebar {
            VStack(alignment: .leading, spacing: 18) {
                Text("YOUR MEETINGS").font(.system(size: 11, weight: .medium)).tracking(1).foregroundStyle(.secondary).padding(.top, 8)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search meetings", text: $model.search).textFieldStyle(.plain)
                }.font(.system(size: 12)).padding(10).background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(model.filteredMeetings) { meeting in
                            Button { model.openMeeting(meeting.id) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(meeting.title).font(.system(size: 13, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(meeting.created.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(.secondary)
                                    Label(meeting.segments.isEmpty ? "Ready to transcribe" : "\(Set(meeting.segments.flatMap(\.speakers)).count) speakers", systemImage: meeting.segments.isEmpty ? "waveform" : "person.2").font(.system(size: 11)).foregroundStyle(accent)
                                }.padding(12).background(model.selection == meeting.id ? Color.white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button { model.importAudio() } label: { Label("Import audio", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }.buttonStyle(.bordered).controlSize(.large).disabled(model.isOccupied)
                Label("Saved on this Mac", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(18).frame(width: 220).background(Color(white: 0.115))
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            }
            VStack(spacing: 0) {
                topBar
                Divider()
                if let meeting = model.selected {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("Meeting title", text: Binding(get: { model.selected?.title ?? "" }, set: model.renameMeeting))
                            .font(.system(size: 24, weight: .semibold)).textFieldStyle(.plain).disabled(model.isOccupied)
                        HStack {
                            Label(meeting.created.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            if let end = meeting.segments.last?.end { Label(timestamp(end), systemImage: "clock") }
                            Spacer()
                            Menu { Button("Markdown (.md)") { model.export(markdown: true) }; Button("Plain text (.txt)") { model.export(markdown: false) } } label: { Label("Export", systemImage: "square.and.arrow.up") }
                        }.font(.callout).foregroundStyle(.secondary)
                        Picker("View", selection: $tab) { Text("Transcript").tag("Transcript"); Text("Summary").tag("Summary") }.pickerStyle(.segmented).frame(width: 260)
                        if meeting.segments.isEmpty {
                            ContentUnavailableView {
                                Label(model.busy ? "Transcribing on this Mac" : "Your audio is ready", systemImage: "waveform")
                            } description: { Text(model.busy ? model.status : "Transcribe and identify speakers locally with Voz + Who.") } actions: {
                                if model.busy { ProgressView() }
                                else {
                                    SpeakerCountPicker(selection: Binding(get: { model.selected?.expectedSpeakerCount ?? 0 }, set: { model.setSelectedSpeakerCount($0) }))
                                    Button("Transcribe on this Mac") { model.processSelected() }.buttonStyle(.borderedProminent).tint(accent).disabled(model.isOccupied)
                                }
                            }
                        } else if tab == "Transcript" { transcript(meeting) }
                        else { summary(meeting) }
                    }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Spacer()
                    Image(systemName: "waveform.path").font(.system(size: 64, weight: .light)).foregroundStyle(accent).padding(.bottom, 12)
                    Text("Be present. Keep the important parts.").font(.system(size: 28, weight: .semibold))
                    Text("Record a conversation or bring your own audio.\nCoda turns it into a speaker-labeled transcript and clear next steps.")
                        .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5).padding(.top, 8)
                    HStack(spacing: 12) {
                        Button("Start a recording") { model.requestMeetingRecording() }.buttonStyle(.borderedProminent).tint(accent)
                        Button("Import audio…") { model.importAudio() }.buttonStyle(.bordered)
                    }.controlSize(.large).padding(.top, 24).disabled(model.isOccupied)
                    HStack(spacing: 24) { Label("Local transcription", systemImage: "laptopcomputer"); Label("Up to 4 speakers", systemImage: "person.2"); Label("Optional AI summary", systemImage: "sparkles") }
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 32)
                    Spacer()
                }
                Divider()
                HStack(spacing: 10) {
                    if model.busy || model.startingCapture { ProgressView().controlSize(.small) }
                    else { Circle().fill(model.recording ? .red : accent).frame(width: 7, height: 7) }
                    Text(model.status).font(.caption).lineLimit(2)
                    Spacer()
                    if let progress = model.progress, model.busy { ProgressView(value: progress).frame(width: 110) }
                    if model.busy { Button("Cancel") { model.cancel() }.disabled(model.status == "Finalizing recording") }
                }.padding(14).background(Color(white: 0.13))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(white: 0.10))
        }.tint(accent)
        .sheet(isPresented: $model.showRecordConsent) { RecordingOptionsView(model: model) }
        .alert("Send transcript to OpenAI?", isPresented: $model.showSummaryConsent) {
            Button("Cancel", role: .cancel) {}
            Button("Send transcript") { model.sendSummary() }
        } message: { Text("The selected meeting's full transcript and speaker names leave this Mac and are sent to OpenAI using your API key. Raw audio stays local. API charges and OpenAI data policies apply. Review sensitive content first. AI summaries can be wrong; check their timestamp references.") }
        .alert(model.recordingStartFailure == nil ? "Coda needs your attention" : "Recording couldn’t start", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            if model.recordingStartFailure?.systemAudioPermissionDenied == true {
                Button("Microphone only…") { model.reviewRecordingOptions(microphoneOnly: true) }
                Button("Open audio permissions") { model.reviewSystemAudioPermission() }
            } else if model.recordingStartFailure != nil { Button("Recording options…") { model.reviewRecordingOptions() } }
            Button("OK", role: .cancel) { model.dismissError() }
        } message: { Text(model.error ?? "") }
        .alert("Delete this meeting?", isPresented: $deleteConfirmation) { Button("Cancel", role: .cancel) {}; Button("Delete", role: .destructive) { model.deleteSelected() } } message: { Text("This removes Coda's local audio, transcript, and summary. The original imported file is kept.") }
        .onChange(of: model.selection) { _, _ in tab = "Transcript" }
    }
    private var topBar: some View {
        HStack {
            if model.recording {
                Label("REC", systemImage: "record.circle.fill").foregroundStyle(.red).font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in Text(timestamp(context.date.timeIntervalSince(model.recordingStarted ?? context.date))).monospacedDigit() }
                Text("Microphone\(model.includeSystem ? " + system audio" : "")").foregroundStyle(.secondary)
                Spacer()
                Button("Stop & save", systemImage: "stop.fill") { model.stopRecording() }.buttonStyle(.borderedProminent).tint(.red)
            } else {
                Text("MEETING NOTEBOOK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("New recording", systemImage: "record.circle") { model.requestMeetingRecording() }.disabled(model.isOccupied)
                if model.selected != nil { Button { deleteConfirmation = true } label: { Image(systemName: "trash") }.help("Delete selected meeting").disabled(model.isOccupied) }
            }
        }.padding(.horizontal, 30).padding(.vertical, 18)
    }
    private func transcript(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SpeakerCountPicker(selection: Binding(get: { model.selected?.expectedSpeakerCount ?? 0 }, set: { model.setSelectedSpeakerCount($0) }))
                Button("Apply & transcribe again") { model.processSelected() }
                    .help("Reprocess saved audio with this speaker count. Replaces the transcript and clears speaker names and summary.")
            }.disabled(model.isOccupied)
            Text("Transcribing again replaces the transcript and clears speaker names and the summary.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Speaker names • edit to identify people") {
                ForEach(Set(meeting.segments.flatMap(\.speakers)).sorted(), id: \.self) { speaker in
                    HStack { Text("Speaker \(speaker + 1)").foregroundStyle(.secondary).frame(width: 95, alignment: .leading)
                        TextField("Name", text: Binding(get: { model.selected?.speakerNames[String(speaker)] ?? "" }, set: { model.renameSpeaker(speaker, name: $0) })).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    }
                }
                Text("Renaming a speaker clears any previous summary to avoid stale attribution.").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.isOccupied)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(meeting.segments) { segment in
                        HStack(alignment: .top, spacing: 18) {
                            Text(timestamp(segment.start)).monospacedDigit().font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(meeting.speakerLabel(segment.speakers)).font(.callout.weight(.semibold)).foregroundStyle(accent)
                                Text(segment.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.id(segment.id)
                    }
                }.padding(18).background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Machine-generated transcript. Overlapping voices and unsupported languages can reduce accuracy. Review before sharing.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func summary(_ meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let summary = meeting.summary {
                    Label("AI-generated • verify the timestamp references", systemImage: "sparkles").font(.callout).foregroundStyle(.secondary)
                    summarySection("Discussion notes", icon: "text.alignleft", items: summary.overview, meeting: meeting)
                    summarySection("Decisions", icon: "checkmark.seal", items: summary.decisions, meeting: meeting)
                    summarySection("Action items", icon: "checklist", items: summary.actions, meeting: meeting)
                } else {
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(accent).padding(.top, 30)
                    Text("Turn the conversation into clarity.").font(.title2.weight(.semibold))
                    Text("Summaries, decisions, and action items cite the transcript. Only transcript text and speaker names go to OpenAI; audio stays here.").foregroundStyle(.secondary)
                }
                Button(meeting.summary == nil ? "Summarize with OpenAI…" : "Generate again…") { model.showSummaryConsent = true }.buttonStyle(.borderedProminent).tint(accent).disabled(model.isOccupied)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func summarySection(_ title: String, icon: String, items: [SummaryItem], meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.title3.weight(.semibold))
            if items.isEmpty { Text("None explicitly stated.").foregroundStyle(.secondary) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.text).textSelection(.enabled)
                    if let owner = item.owner { Text("Owner: " + owner).font(.caption).foregroundStyle(.secondary) }
                    if let due = item.dueDate { Text("Due: " + due).font(.caption).foregroundStyle(.secondary) }
                    Text(item.evidence.compactMap { id in meeting.segments.first { $0.id == id } }.map { "[" + timestamp($0.start) + "]" }.joined(separator: " ")).font(.caption.monospaced()).foregroundStyle(accent)
                }
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06)))
    }
}

struct RecordingOptionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Record a conversation", systemImage: "waveform").font(.title2.weight(.semibold))
            Text("Make sure everyone knows you are recording. Coda shows a red recording indicator until you stop.").fixedSize(horizontal: false, vertical: true)
            Picker("Audio source", selection: $model.includeSystem) {
                Text("Microphone + meeting audio").tag(true)
                Text("Microphone only").tag(false)
            }.pickerStyle(.segmented).accessibilityIdentifier("coda.recording.source")
            Text(model.includeSystem ? "Records your microphone and sounds from other apps. Requires Microphone and Screen & System Audio Recording access. Use headphones to reduce echo." : "Records only your microphone. Voices playing through headphones or other apps are not captured. This option uses Microphone access only.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SpeakerCountPicker(selection: $model.recordingSpeakerCount)
            if model.includeSystem, model.detectMeetings, let detected = model.recordingDetectedMeeting {
                if let count = detected.participantCount, (1...4).contains(count) {
                    Toggle("Use \(detected.service) count: \(count), including you", isOn: $model.useDetectedSpeakerCount)
                        .disabled(model.recordingSpeakerCount != 0)
                    Text("Participants can include silent people or shared devices. Set a count above to override.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(detected.participantCount.map { "\(detected.service) shows \($0) participants. Coda supports up to 4 speakers; enter a count or use automatic audio detection." } ?? "\(detected.service) detected; participant count unavailable. Enter a count or use automatic audio detection.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Include yourself. Choose a count to prevent extra speaker groups, or leave Automatic to detect voices from audio.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Toggle("Detect Meet, Zoom, and Teams calls", isOn: $model.detectMeetings)
            if model.detectMeetings && !model.meetingDetectionAvailable {
                Button("Enable meeting detection access…") { model.requestMeetingDetectionAccess() }
                Text("Accessibility lets Coda read meeting controls and participant counts. Manual speaker entry works without it.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if model.autoSummary { Label("Automatic summaries are ON: the transcript will be sent to OpenAI after processing.", systemImage: "arrow.up.right.circle").foregroundStyle(.orange) }
            HStack { Button("Cancel") { model.showRecordConsent = false }; Spacer(); Button("Start recording") { model.showRecordConsent = false; model.startRecording() }.buttonStyle(.borderedProminent).tint(accent) }
        }.padding(30).frame(width: 550).background(Color(white: 0.10))
            .preferredColorScheme(.dark).foregroundStyle(Color(white: 0.88))
    }
}

struct SpeakerCountPicker: View {
    @Binding var selection: Int
    var body: some View {
        Picker("Speakers", selection: $selection) {
            Text("Automatic").tag(0)
            ForEach(1...4, id: \.self) { count in Text("\(count)\(count == 1 ? " speaker" : " speakers")").tag(count) }
        }.accessibilityIdentifier("coda.meeting.speakerCount")
    }
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
