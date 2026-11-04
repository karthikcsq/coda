import SwiftUI
import CodaCore

// Disambiguate the stable property wrapper from the macOS 27 State macro; CLT omits SwiftUIMacros.
private typealias ViewState<Value> = SwiftUI.State<Value>

/// One meeting as a document: title, transcript and summary, plus recording and processing state.
struct ContentView: View {
    @Bindable var model: AppModel
    @Bindable var dictation: DictationController
    var showsMeetingSidebar: Bool
    var onBack: (() -> Void)?
    @ViewState private var tab: String
    @ViewState private var editingSpeakers: Bool
    @ViewState private var deleteConfirmation = false
    /// Segment a summary citation jumped to; highlighted briefly in the transcript.
    @ViewState private var focusedSegment: String?
    @Namespace private var tabIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, dictation: DictationController, initialTab: String = "Transcript",
         showsMeetingSidebar: Bool = true, editingSpeakers: Bool = false, onBack: (() -> Void)? = nil) {
        self.model = model; self.dictation = dictation
        self.showsMeetingSidebar = showsMeetingSidebar
        self.onBack = onBack
        _tab = ViewState(initialValue: initialTab)
        _editingSpeakers = ViewState(initialValue: editingSpeakers)
    }

    private var capturing: Bool { model.recording || model.startingCapture }

    var body: some View {
        HStack(spacing: 0) {
            if showsMeetingSidebar {
                MeetingSidebar(model: model)
                Rectangle().fill(CodaStyle.hairline).frame(width: 1)
            }
            VStack(spacing: 0) {
                toolbar
                Group {
                    if capturing { RecordingFocusView(model: model) }
                    else if let meeting = model.selected { document(meeting) }
                    else { welcome }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                statusBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CodaStyle.canvas)
        }
        .tint(CodaStyle.mint)
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
        .onChange(of: model.selection) { _, _ in tab = "Transcript"; editingSpeakers = false; focusedSegment = nil }
    }

    // MARK: Chrome

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("All meetings")
                    }
                    .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
                }
                .buttonStyle(CodaNavRowStyle(selected: false))
                .foregroundStyle(CodaStyle.ink.opacity(0.86)).font(.system(size: 13, weight: .medium))
                .disabled(model.meetingOperationInProgress)
                .opacity(model.meetingOperationInProgress ? 0.4 : 1)
                .accessibilityIdentifier("coda.meetings.back")
            } else {
                CodaEyebrow(text: "Meetings").padding(.leading, 10)
            }
            Spacer(minLength: 12)
            if !capturing {
                if model.selected?.segments.isEmpty == false { exportMenu }
                if model.selected != nil {
                    Button { deleteConfirmation = true } label: { Image(systemName: "trash") }
                        .buttonStyle(CodaIconButtonStyle()).help("Delete this meeting")
                        .accessibilityLabel("Delete selected meeting").disabled(model.isOccupied)
                }
                Button { model.requestMeetingRecording() } label: { Label("New recording", systemImage: "record.circle") }
                    .buttonStyle(CodaSecondaryButtonStyle()).disabled(model.isOccupied)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16).frame(height: 56)
        .codaDivider()
    }

    private var exportMenu: some View {
        Menu {
            Button("Markdown (.md)") { model.export(markdown: true) }
            Button("Plain text (.txt)") { model.export(markdown: false) }
        } label: {
            Image(systemName: "square.and.arrow.up").font(.system(size: 13))
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Export transcript").accessibilityLabel("Export")
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.busy || model.startingCapture { ProgressView().controlSize(.mini).frame(width: 12) }
            else { Circle().fill(model.recording ? CodaStyle.recording : CodaStyle.mint.opacity(0.8)).frame(width: 6, height: 6).frame(width: 12) }
            Text(model.status).font(CodaStyle.captionFont).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 12)
            if let progress = model.progress, model.busy {
                ProgressView(value: progress).progressViewStyle(.linear).frame(width: 120)
                Text("\(Int((progress * 100).rounded()))%").font(CodaStyle.captionFont).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
            }
            if model.busy {
                Button("Cancel") { model.cancel() }.buttonStyle(CodaQuietButtonStyle())
                    .disabled(model.status == "Finalizing recording")
            }
        }
        .padding(.horizontal, 22).frame(height: 38)
        .overlay(alignment: .top) { Rectangle().fill(CodaStyle.hairline).frame(height: 1) }
    }

    // MARK: Document

    private func document(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Meeting title", text: Binding(get: { model.selected?.title ?? "" }, set: model.renameMeeting))
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).textFieldStyle(.plain)
                    .disabled(model.isOccupied).accessibilityLabel("Meeting title")
                metaLine(meeting)
            }
            .padding(.top, 28).padding(.bottom, 20)
            .codaColumn()
            if meeting.segments.isEmpty {
                pending(meeting)
            } else {
                tabBar(meeting).codaColumn()
                Rectangle().fill(CodaStyle.hairline).frame(height: 1)
                if tab == "Transcript" { transcript(meeting) } else { summary(meeting) }
            }
        }
    }

    private func metaLine(_ meeting: Meeting) -> some View {
        HStack(spacing: 10) {
            Label(meeting.created.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            if let length = meeting.transcribedDuration {
                separator
                Label(MeetingFormat.duration(length), systemImage: "clock")
            }
            if !meeting.speakerIDs.isEmpty {
                separator
                HStack(spacing: 7) {
                    CodaAvatarStack(meeting: meeting, size: 18)
                    Text(meeting.speakerIDs.map(meeting.displayName).joined(separator: ", ")).lineLimit(1)
                }
            }
        }
        .labelStyle(MetaLabelStyle())
        .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
    }

    private var separator: some View {
        Circle().fill(CodaStyle.muted.opacity(0.6)).frame(width: 3, height: 3).accessibilityHidden(true)
    }

    private func tabBar(_ meeting: Meeting) -> some View {
        HStack(spacing: 24) {
            tabButton("Transcript", detail: "\(meeting.segments.count)")
            tabButton("Summary", detail: meeting.summary == nil ? nil : "AI")
            Spacer()
        }
    }

    private func tabButton(_ name: String, detail: String?) -> some View {
        let selected = tab == name
        return Button {
            withAnimation(CodaStyle.motion(reduceMotion, duration: 0.2)) { tab = name }
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? CodaStyle.ink : CodaStyle.muted)
                    if let detail {
                        Text(detail).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(selected ? CodaStyle.mint : CodaStyle.muted)
                            .padding(.horizontal, 5).frame(height: 16)
                            .background((selected ? CodaStyle.mint : CodaStyle.muted).opacity(0.13), in: Capsule())
                    }
                }
                ZStack {
                    Capsule().fill(.clear).frame(height: 2)
                    if selected {
                        Capsule().fill(CodaStyle.mint).frame(height: 2)
                            .matchedGeometryEffect(id: "tab", in: tabIndicator)
                    }
                }
            }
            .fixedSize().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Transcript

    private func transcript(_ meeting: Meeting) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    speakers(meeting).padding(.top, 20).padding(.bottom, 14)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(meeting.segments.enumerated()), id: \.element.id) { index, segment in
                            let continued = index > 0 && meeting.segments[index - 1].speakers == segment.speakers
                            segmentRow(segment, in: meeting, continued: continued).id(segment.id)
                        }
                    }
                    Text("Machine-generated transcript. Overlapping voices and unsupported languages can reduce accuracy. Review before sharing.")
                        .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 26).padding(.bottom, 34).padding(.leading, 88)
                }
                .codaColumn()
            }
            .onAppear { reveal(focusedSegment, with: proxy) }
            .onChange(of: focusedSegment) { _, id in reveal(id, with: proxy) }
        }
    }

    private func reveal(_ id: String?, with proxy: ScrollViewProxy) {
        guard let id else { return }
        DispatchQueue.main.async {
            withAnimation(CodaStyle.motion(reduceMotion, duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard focusedSegment == id else { return }
            withAnimation(CodaStyle.motion(reduceMotion, duration: 0.5)) { focusedSegment = nil }
        }
    }

    private func segmentRow(_ segment: Segment, in meeting: Meeting, continued: Bool) -> some View {
        let lead = segment.speakers.first ?? 0
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(timestamp(segment.start)).font(.system(size: 11, design: .monospaced))
                .foregroundStyle(CodaStyle.muted).frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if !continued {
                    HStack(alignment: .center, spacing: 10) {
                        Group {
                            if segment.speakers.isEmpty {
                                CodaSpeakerAvatar(monogram: "?", index: 0, size: 22).opacity(0.5)
                            } else {
                                CodaSpeakerAvatar(monogram: meeting.monogram(lead), index: lead, size: 22)
                            }
                        }
                        .frame(width: 22)
                        Text(segment.speakers.isEmpty ? "Unknown speaker" : segment.speakers.map(meeting.displayName).joined(separator: " & "))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(segment.speakers.isEmpty ? CodaStyle.muted : CodaStyle.speakerColor(lead))
                        if segment.speakers.count > 1 { CodaTag(text: "Overlapping · uncertain") }
                    }
                    .padding(.leading, -32)
                }
                Text(segment.text).font(.system(size: 14)).lineSpacing(5)
                    .foregroundStyle(CodaStyle.ink.opacity(0.94))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 32)
        }
        .padding(.top, continued ? 6 : 18).padding(.bottom, 2)
        .padding(.horizontal, 12)
        .background(alignment: .center) {
            RoundedRectangle(cornerRadius: CodaStyle.radius)
                .fill(CodaStyle.mint.opacity(focusedSegment == segment.id ? 0.09 : 0))
                .padding(.top, continued ? 0 : 10).padding(.bottom, -6)
        }
        .padding(.horizontal, -12)
        .accessibilityElement(children: .combine)
    }

    /// Speaker chips; the editor owns names, speaker count and the shared re-transcription warning.
    private func speakers(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(meeting.speakerIDs, id: \.self) { speaker in
                    HStack(spacing: 7) {
                        Circle().fill(CodaStyle.speakerColor(speaker)).frame(width: 7, height: 7)
                        Text(meeting.displayName(speaker)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    .padding(.horizontal, 11).frame(height: 28)
                    .background(CodaStyle.raised, in: Capsule())
                    .overlay(Capsule().strokeBorder(CodaStyle.hairline))
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(CodaStyle.motion(reduceMotion)) { editingSpeakers.toggle() }
                } label: {
                    Label(editingSpeakers ? "Done" : "Edit speakers", systemImage: editingSpeakers ? "checkmark" : "pencil")
                        .padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                }
                .buttonStyle(CodaNavRowStyle(selected: editingSpeakers))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(CodaStyle.ink.opacity(0.86))
                .disabled(model.isOccupied).opacity(model.isOccupied ? 0.45 : 1)
                .help("Rename speakers or transcribe again with a different speaker count")
            }
            if editingSpeakers { speakerEditor(meeting).padding(.top, 12).transition(.opacity) }
        }
    }

    private func speakerEditor(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(meeting.speakerIDs, id: \.self) { speaker in
                HStack(spacing: 12) {
                    CodaSpeakerAvatar(monogram: meeting.monogram(speaker), index: speaker, size: 26)
                    Text("Speaker \(speaker + 1)").font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                        .frame(width: 76, alignment: .leading)
                    TextField("Add a name", text: Binding(get: { model.selected?.speakerNames[String(speaker)] ?? "" }, set: { model.renameSpeaker(speaker, name: $0) }))
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusSmall).strokeBorder(CodaStyle.hairline))
                        .frame(maxWidth: 260)
                        .accessibilityLabel("Name for speaker \(speaker + 1)")
                }
            }
            Rectangle().fill(CodaStyle.hairline).frame(height: 1)
            HStack(spacing: 12) {
                SpeakerCountPicker(selection: Binding(get: { model.selected?.expectedSpeakerCount ?? 0 }, set: { model.setSelectedSpeakerCount($0) }))
                    .frame(width: 190)
                Button("Apply & transcribe again") { model.processSelected() }
                    .buttonStyle(CodaSecondaryButtonStyle())
                    .help("Reprocess saved audio with this speaker count. Replaces the transcript and clears speaker names and summary.")
                Spacer(minLength: 0)
            }
            CodaNotice(kind: .caution, text: "Transcribing again replaces the transcript and clears speaker names and the summary. Renaming a speaker clears the summary.")
        }
        .disabled(model.isOccupied)
        .padding(18)
        .background(CodaStyle.chrome, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
    }

    // MARK: Summary

    private func summary(_ meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if let summary = meeting.summary {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(CodaStyle.mint)
                        Text("AI-generated from the transcript. Check the cited timestamps before sharing.")
                            .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Button("Generate again…") { model.showSummaryConsent = true }
                            .buttonStyle(CodaSecondaryButtonStyle()).disabled(model.isOccupied)
                    }
                    summarySection("Discussion notes", kind: .note, items: summary.overview, meeting: meeting)
                    summarySection("Decisions", kind: .decision, items: summary.decisions, meeting: meeting)
                    summarySection("Action items", kind: .action, items: summary.actions, meeting: meeting)
                } else {
                    CodaEmptyState(icon: "sparkles", title: "No summary yet",
                                   message: "Summaries, decisions and action items cite the transcript. Only transcript text and speaker names go to OpenAI; your audio stays on this Mac.",
                                   tint: CodaStyle.mint) {
                        Button("Summarize with OpenAI…") { model.showSummaryConsent = true }
                            .buttonStyle(CodaPrimaryButtonStyle()).disabled(model.isOccupied)
                            .padding(.top, 10)
                    }
                }
            }
            .padding(.top, 24).padding(.bottom, 36)
            .codaColumn()
        }
    }

    private enum SummaryKind { case note, decision, action }

    private func summarySection(_ title: String, kind: SummaryKind, items: [SummaryItem], meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title).font(CodaStyle.sectionFont)
                if !items.isEmpty { CodaCountBadge(count: items.count) }
            }
            if items.isEmpty {
                Text("None explicitly stated.").font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        if index > 0 { Rectangle().fill(CodaStyle.hairline).frame(height: 1).padding(.leading, 46) }
                        summaryRow(item, kind: kind, meeting: meeting)
                    }
                }
                .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
                .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
            }
        }
    }

    private func summaryRow(_ item: SummaryItem, kind: SummaryKind, meeting: Meeting) -> some View {
        let cited = item.evidence.compactMap { id in meeting.segments.first { $0.id == id } }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Group {
                switch kind {
                case .note: Circle().fill(CodaStyle.mint).frame(width: 5, height: 5).offset(y: -3)
                case .decision: Image(systemName: "checkmark.seal.fill").foregroundStyle(CodaStyle.mint)
                case .action: Image(systemName: "circle").foregroundStyle(CodaStyle.muted)
                }
            }
            .font(.system(size: 13)).frame(width: 18).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(item.text).font(CodaStyle.bodyFont).lineSpacing(4).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if item.owner != nil || item.dueDate != nil || !cited.isEmpty {
                    HStack(spacing: 6) {
                        if let owner = item.owner { CodaTag(icon: "person.fill", text: owner) }
                        if let due = item.dueDate { CodaTag(icon: "calendar", text: due) }
                        ForEach(cited) { segment in citation(segment) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
    }

    /// Citations are links back into the transcript, not decorative brackets.
    private func citation(_ segment: Segment) -> some View {
        Button {
            focusedSegment = segment.id
            withAnimation(CodaStyle.motion(reduceMotion, duration: 0.2)) { tab = "Transcript" }
        } label: {
            Text(timestamp(segment.start)).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(CodaStyle.mint)
            .padding(.horizontal, 8).frame(height: 21)
            .background(CodaStyle.mint.opacity(0.11), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show this moment in the transcript")
        .accessibilityLabel("Show \(timestamp(segment.start)) in the transcript")
    }

    // MARK: Empty and pending

    private func pending(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(CodaStyle.hairline).frame(height: 1)
            // Scrolls so a long status message can never raise the window's minimum height.
            ScrollView { VStack(spacing: 20) {
                CodaEmblem(symbol: model.busy ? "waveform.badge.magnifyingglass" : "waveform")
                VStack(spacing: 8) {
                    Text(model.busy ? "Transcribing on this Mac" : "Your audio is ready")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(model.busy ? model.status : "Transcribe and label up to four speakers locally. Nothing leaves this Mac.")
                        .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.busy {
                    ProgressView(value: model.progress ?? 0).progressViewStyle(.linear).frame(width: 260)
                        .opacity(model.progress == nil ? 0 : 1)
                } else {
                    HStack(spacing: 12) {
                        SpeakerCountPicker(selection: Binding(get: { model.selected?.expectedSpeakerCount ?? 0 }, set: { model.setSelectedSpeakerCount($0) }))
                            .frame(width: 190)
                        Button("Transcribe on this Mac") { model.processSelected() }
                            .buttonStyle(CodaPrimaryButtonStyle()).disabled(model.isOccupied)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60) }
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Spacer()
            CodaEmblem(symbol: "waveform.path")
            VStack(spacing: 8) {
                Text("Be present. Keep the important parts.").font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Record a conversation or bring your own audio. Coda turns it into a speaker-labeled transcript and clear next steps.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .lineSpacing(4).frame(maxWidth: 440)
            }
            HStack(spacing: 10) {
                Button { model.requestMeetingRecording() } label: { Label("Start a recording", systemImage: "record.circle") }
                    .buttonStyle(CodaPrimaryButtonStyle())
                Button { model.importAudio() } label: { Label("Import audio…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(CodaSecondaryButtonStyle())
            }
            .disabled(model.isOccupied)
            HStack(spacing: 20) {
                Label("Local transcription", systemImage: "lock")
                Label("Up to 4 speakers", systemImage: "person.2")
                Label("Optional AI summary", systemImage: "sparkles")
            }
            .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
}

/// Icon tucked close to its text, in a quieter tone.
private struct MetaLabelStyle: LabelStyle {
    func makeBody(configuration: LabelStyleConfiguration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 10.5)).foregroundStyle(CodaStyle.muted)
            configuration.title
        }
    }
}

// MARK: - Recording

/// Full-canvas live state: nothing else competes with the fact that audio is being captured.
struct RecordingFocusView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var breathing = false
    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                Circle().fill(CodaStyle.recording.opacity(0.06)).frame(width: 168, height: 168)
                    .scaleEffect(breathing ? 1 : 0.82)
                Circle().fill(CodaStyle.recording.opacity(0.12)).frame(width: 112, height: 112)
                    .scaleEffect(breathing ? 1 : 0.92)
                Circle().strokeBorder(CodaStyle.recording.opacity(0.35)).frame(width: 64, height: 64)
                if model.recording {
                    Circle().fill(CodaStyle.recording).frame(width: 22, height: 22)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(model.recording ? "RECORDING" : "STARTING")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                    .foregroundStyle(model.recording ? CodaStyle.recording : CodaStyle.muted)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timestamp(model.recording ? context.date.timeIntervalSince(model.recordingStarted ?? context.date) : 0))
                        .font(.system(size: 48, weight: .light, design: .rounded)).monospacedDigit()
                        .foregroundStyle(model.recording ? CodaStyle.ink : CodaStyle.muted)
                }
                Label(model.includeSystem ? "Microphone + meeting audio" : "Microphone only",
                      systemImage: model.includeSystem ? "person.wave.2" : "mic")
                    .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Button { model.stopRecording() } label: { Label("Stop & save", systemImage: "stop.fill") }
                .buttonStyle(CodaPrimaryButtonStyle(tint: CodaStyle.recording, ink: .white))
                .disabled(!model.recording)
                .keyboardShortcut(".", modifiers: .command)
            Text("Make sure everyone knows they’re being recorded. Audio is saved on this Mac before anything is transcribed.")
                .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

struct RecordingOptionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New recording").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Make sure everyone knows you are recording. Coda shows a red indicator until you stop.")
                    .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                CodaEyebrow(text: "Audio source")
                HStack(spacing: 10) {
                    sourceOption(true, icon: "person.wave.2", title: "Microphone + meeting audio", detail: "Your voice and sound from other apps")
                    sourceOption(false, icon: "mic", title: "Microphone only", detail: "Just the voices in the room")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("coda.recording.source")
                Text(model.includeSystem ? "Requires Microphone and Screen & System Audio Recording access. Use headphones to reduce echo." : "Voices playing through headphones or other apps are not captured. Uses Microphone access only.")
                    .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                optionRow(title: "Speakers", detail: speakerDetail) {
                    SpeakerCountPicker(selection: $model.recordingSpeakerCount).labelsHidden().frame(width: 150)
                }
                if model.includeSystem, model.detectMeetings, let detected = model.recordingDetectedMeeting,
                   let count = detected.participantCount, (1...4).contains(count) {
                    optionRow(title: "Use \(detected.service) count: \(count), including you",
                              detail: "Participants can include silent people or shared devices. Set a count above to override.") {
                        Toggle("", isOn: $model.useDetectedSpeakerCount).labelsHidden()
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(model.recordingSpeakerCount != 0)
                    }
                }
                Rectangle().fill(CodaStyle.hairline).frame(height: 1)
                optionRow(title: "Detect Meet, Zoom, and Teams calls",
                          detail: "Suggests a recording when a call starts. It never starts one by itself.") {
                    Toggle("", isOn: $model.detectMeetings).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityLabel("Detect Meet, Zoom, and Teams calls")
                }
                if model.detectMeetings && !model.meetingDetectionAvailable {
                    HStack(alignment: .top, spacing: 10) {
                        Text("Accessibility lets Coda read meeting controls and participant counts. Manual speaker entry works without it.")
                            .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Enable access…") { model.requestMeetingDetectionAccess() }
                            .buttonStyle(CodaSecondaryButtonStyle())
                    }
                }
            }
            .padding(16)
            .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radius).strokeBorder(CodaStyle.hairline))
            if model.autoSummary { CodaNotice(kind: .caution, text: "Automatic summaries are ON: this transcript will be sent to OpenAI after processing.") }
            HStack {
                Button("Cancel") { model.showRecordConsent = false }.buttonStyle(CodaSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button { model.showRecordConsent = false; model.startRecording() } label: {
                    Label("Start recording", systemImage: "record.circle")
                }
                .buttonStyle(CodaPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 560).background(CodaStyle.canvas)
        .preferredColorScheme(.dark).foregroundStyle(CodaStyle.ink)
    }

    private var speakerDetail: String {
        if model.includeSystem, model.detectMeetings, let detected = model.recordingDetectedMeeting {
            if let count = detected.participantCount, (1...4).contains(count) { return "Include yourself. Automatic can use the detected call count." }
            return detected.participantCount.map { "\(detected.service) shows \($0) participants. Coda supports up to 4 speakers; enter a count or use automatic detection." }
                ?? "\(detected.service) detected; participant count unavailable. Enter a count or use automatic detection."
        }
        return "Include yourself. A count prevents extra speaker groups; Automatic detects voices from audio."
    }

    private func optionRow<Control: View>(title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(CodaStyle.rowTitleFont)
                Text(detail).font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control()
        }
    }

    private func sourceOption(_ value: Bool, icon: String, title: String, detail: String) -> some View {
        let selected = model.includeSystem == value
        return Button { model.includeSystem = value } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon).font(.system(size: 15))
                        .foregroundStyle(selected ? CodaStyle.mint : CodaStyle.muted)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
                        .foregroundStyle(selected ? CodaStyle.mint : CodaStyle.strongEdge)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(CodaStyle.captionFont).foregroundStyle(.secondary)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? CodaStyle.mint.opacity(0.07) : CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radius).strokeBorder(selected ? CodaStyle.mint.opacity(0.45) : CodaStyle.hairline))
            .contentShape(RoundedRectangle(cornerRadius: CodaStyle.radius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

/// Compact meeting list for the standalone notebook layout.
private struct MeetingSidebar: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CodaEyebrow(text: "Your meetings").padding(.top, 8)
            CodaSearchField(prompt: "Search meetings", text: $model.search)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.filteredMeetings) { meeting in
                        Button { model.openMeeting(meeting.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(meeting.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 6) {
                                    Text(meeting.created.formatted(date: .abbreviated, time: .omitted))
                                    if let length = meeting.transcribedDuration {
                                        Text("·"); Text(MeetingFormat.duration(length))
                                    }
                                }
                                .font(CodaStyle.captionFont).foregroundStyle(.secondary)
                                if !meeting.speakerIDs.isEmpty { CodaAvatarStack(meeting: meeting, size: 18, ring: CodaStyle.chrome) }
                                else { CodaTag(icon: "waveform", text: "Not transcribed") }
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(CodaListRowStyle(selected: model.selection == meeting.id))
                        .accessibilityLabel("Open " + meeting.title)
                    }
                }
            }
            Button { model.importAudio() } label: { Label("Import audio", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                .buttonStyle(CodaSecondaryButtonStyle()).disabled(model.isOccupied)
            Label("Saved on this Mac", systemImage: "internaldrive").font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
        }
        .padding(18).frame(width: 232).background(CodaStyle.chrome)
    }
}
