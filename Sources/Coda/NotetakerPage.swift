import SwiftUI
import CodaCore

struct NotetakerPage: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    var operationInProgress: Bool { model.meetingOperationInProgress }
    private var days: [Date] {
        Array(Set(model.filteredMeetings.map { Calendar.current.startOfDay(for: $0.created) })).sorted(by: >)
    }
    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    var body: some View {
        if model.showingMeetingDetail || operationInProgress || model.showRecordConsent {
            VStack(spacing: 0) {
                HStack {
                    Button { model.showMeetingLibrary() } label: {
                        Label("All meetings", systemImage: "chevron.left").font(CodaStyle.secondaryFont)
                    }
                    .buttonStyle(CodaQuietButtonStyle()).disabled(operationInProgress)
                    .accessibilityIdentifier("coda.meetings.back")
                    Spacer()
                }
                .padding(.horizontal, 28).padding(.vertical, 14)
                .codaDivider()
                ContentView(model: model, dictation: controller, showsMeetingSidebar: false)
            }
        } else {
            HStack(spacing: 0) {
                library
                Rectangle().fill(CodaStyle.hairline).frame(width: 1)
                detail
            }
        }
    }
    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CodaStyle.blockSpacing) {
                CodaPageHeader(icon: "square.and.pencil", title: "Notetaker",
                               subtitle: "Record or import audio locally.") {
                    HStack(spacing: 8) {
                        Button { model.openSettings() } label: { Image(systemName: "gearshape") }
                            .buttonStyle(CodaIconButtonStyle()).help("Notetaker settings")
                            .accessibilityLabel("Notetaker settings")
                        Button("Import audio") { model.importAudio() }
                            .buttonStyle(CodaSecondaryButtonStyle()).disabled(model.isOccupied)
                        Button("New recording") { model.requestMeetingRecording() }
                            .buttonStyle(CodaPrimaryButtonStyle()).disabled(model.isOccupied)
                    }
                }
                HStack(alignment: .center, spacing: 12) {
                    CodaEyebrow(text: "Saved meetings")
                    if !model.filteredMeetings.isEmpty { CodaCountBadge(count: model.filteredMeetings.count) }
                    Spacer(minLength: 12)
                    CodaSearchField(prompt: "Search meetings", text: $model.search, width: 200)
                }
                if model.filteredMeetings.isEmpty {
                    CodaEmptyState(icon: model.search.isEmpty ? "doc.text" : "magnifyingglass",
                                   title: model.search.isEmpty ? "Your notes start here" : "No matching meetings",
                                   message: model.search.isEmpty
                                    ? "Start a recording or import audio. Coda saves the audio first, then transcribes and labels speakers locally."
                                    : "Try part of a meeting title.",
                                   tint: model.search.isEmpty ? CodaStyle.mint : CodaStyle.muted)
                } else {
                    // Grouped by day, so a date appears once instead of above every row.
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(days, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 10) {
                                CodaEyebrow(text: dayLabel(day))
                                ForEach(model.filteredMeetings.filter { Calendar.current.isDate($0.created, inSameDayAs: day) }) { meeting in
                                    meetingRow(meeting)
                                }
                            }
                        }
                    }
                }
            }.padding(CodaStyle.pageInset)
        }.frame(maxWidth: .infinity)
    }
    private func meetingRow(_ meeting: Meeting) -> some View {
        Button { model.openMeeting(meeting.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: meeting.segments.isEmpty ? "waveform" : "doc.text").font(.system(size: 16))
                    .foregroundStyle(meeting.segments.isEmpty ? CodaStyle.muted : CodaStyle.mint)
                    .frame(width: 36, height: 36)
                    .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    HStack(spacing: 8) {
                        Text(meeting.created.formatted(date: .omitted, time: .shortened))
                            .font(CodaStyle.secondaryFont).foregroundStyle(.secondary).monospacedDigit()
                        Text("·").foregroundStyle(.secondary)
                        Text(meeting.segments.isEmpty
                             ? "Audio saved · ready to transcribe"
                             : meeting.summary == nil ? "Transcript ready" : "Transcript and summary")
                            .font(CodaStyle.secondaryFont).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(CodaStyle.muted)
                    .accessibilityHidden(true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(CodaListRowStyle(selected: model.selection == meeting.id))
        .help("Open this meeting")
        .accessibilityIdentifier("coda.meetings.open.\(meeting.id.uuidString)")
        .accessibilityLabel("Open " + meeting.title)
    }
    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let meeting = model.selected {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.title).font(.system(size: 17, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meeting.created.formatted(date: .abbreviated, time: .shortened))
                        .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                }
                CodaStatusChip(readiness: meeting.segments.isEmpty ? .pending : .ready,
                               text: meeting.segments.isEmpty ? "Ready to transcribe" : meeting.summary == nil ? "Transcribed" : "Transcribed · summarized")
                Rectangle().fill(CodaStyle.hairline).frame(height: 1)
                let speakers = Set(meeting.segments.flatMap(\.speakers)).sorted()
                VStack(alignment: .leading, spacing: 10) {
                    CodaEyebrow(text: "Speakers")
                    if speakers.isEmpty {
                        Text("Available after transcription.").font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                    }
                    ForEach(speakers, id: \.self) { speaker in
                        HStack(spacing: 10) {
                            Text(String(meeting.speakerLabel([speaker]).prefix(1)))
                                .font(.system(size: 13, weight: .medium))
                                .frame(width: 26, height: 26)
                                .background(CodaStyle.mint.opacity(0.12), in: Circle())
                                .foregroundStyle(CodaStyle.mint)
                                .accessibilityHidden(true)
                            Text(meeting.speakerLabel([speaker])).font(.system(size: 13))
                        }
                    }
                }
                Button("Open meeting") { model.openMeeting(meeting.id) }
                    .buttonStyle(CodaPrimaryButtonStyle())
                    .accessibilityLabel("Open " + meeting.title)
                Text(meeting.summary == nil
                     ? "The transcript and the optional summary live inside the note."
                     : "Includes the transcript, decisions and action items.")
                    .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meeting details").font(.system(size: 17, weight: .medium))
                    Text("Select a meeting to see its speakers and open the transcript.")
                        .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Label("Saved on this Mac", systemImage: "internaldrive")
                .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
        }
        .padding(22).frame(width: 248).frame(maxHeight: .infinity, alignment: .top)
        .background(CodaStyle.chrome)
    }
}
