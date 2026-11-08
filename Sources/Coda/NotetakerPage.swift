import SwiftUI
import CodaCore

struct NotetakerPage: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    var operationInProgress: Bool { model.meetingOperationInProgress }
    private var days: [Date] {
        Array(Set(model.filteredMeetings.map { Calendar.current.startOfDay(for: $0.created) })).sorted(by: >)
    }
    var body: some View {
        if model.showingMeetingDetail || operationInProgress || model.showRecordConsent {
            ContentView(model: model, dictation: controller, showsMeetingSidebar: false,
                        onBack: { model.showMeetingLibrary() })
        } else {
            library
        }
    }

    // MARK: Library

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.meetings.isEmpty {
                    emptyLibrary
                } else {
                    CodaSearchField(prompt: "Search titles, transcripts, people", text: $model.search, width: 330)
                    if model.filteredMeetings.isEmpty {
                        CodaEmptyState(icon: "magnifyingglass", title: "No matching meetings",
                                       message: "Try a name or a word from the conversation.")
                    } else {
                        // Grouped by day, so a date appears once instead of above every row.
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(days, id: \.self) { day in daySection(day) }
                        }
                    }
                }
            }
            .codaPageInsets()
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                titleBlock
                Spacer(minLength: 16)
                actions
            }
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                actions
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meetings").font(CodaStyle.pageTitleFont).fixedSize()
            Text(libraryLine).font(CodaStyle.secondaryFont).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// Honest totals only: counts and transcribed length from what is saved locally.
    private var libraryLine: String {
        let count = model.meetings.count
        guard count > 0 else { return "Record or import a conversation. Transcription runs on your Mac." }
        var parts = [count == 1 ? "1 meeting" : "\(count) meetings"]
        let audio = model.meetings.compactMap(\.transcribedDuration).reduce(0, +)
        if audio > 0 { parts.append(MeetingFormat.duration(audio)) }
        parts.append("Stored on this Mac")
        return parts.joined(separator: "  ·  ")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { model.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(CodaIconButtonStyle(size: 34)).help("Notetaker settings")
                .accessibilityLabel("Notetaker settings")
            Button { model.importAudio() } label: {
                Label("Import audio", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(CodaSecondaryButtonStyle()).disabled(model.isOccupied)
            Button { model.requestMeetingRecording() } label: {
                Label("New recording", systemImage: "record.circle")
            }
            .buttonStyle(CodaPrimaryButtonStyle()).disabled(model.isOccupied)
        }
        .fixedSize()
    }

    private func daySection(_ day: Date) -> some View {
        let group = model.filteredMeetings.filter { Calendar.current.isDate($0.created, inSameDayAs: day) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CodaEyebrow(text: MeetingFormat.dayLabel(day))
                if group.count > 1 { CodaCountBadge(count: group.count) }
            }
            VStack(spacing: 0) {
                ForEach(Array(group.enumerated()), id: \.element.id) { index, meeting in
                    if index > 0 { Rectangle().fill(CodaStyle.hairline).frame(height: 1).padding(.leading, 96) }
                    meetingRow(meeting)
                }
            }
            .background(CodaStyle.sunken)
            .clipShape(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
        }
    }

    private func meetingRow(_ meeting: Meeting) -> some View {
        Button { model.openMeeting(meeting.id) } label: {
            HStack(alignment: .center, spacing: 16) {
                Text(meeting.created.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(CodaStyle.muted)
                    .frame(width: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(meeting.previewLine ?? "Audio saved. Open it to transcribe on this Mac.")
                        .font(CodaStyle.secondaryFont).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                if !meeting.speakerIDs.isEmpty {
                    CodaAvatarStack(meeting: meeting, size: 22, ring: CodaStyle.canvas)
                }
                status(meeting)
                if let length = meeting.transcribedDuration {
                    Text(MeetingFormat.duration(length))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(CodaStyle.muted)
                        .frame(minWidth: 48, alignment: .trailing)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CodaStyle.muted.opacity(0.7)).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(CodaTableRowStyle())
        .help("Open this meeting")
        .accessibilityIdentifier("coda.meetings.open.\(meeting.id.uuidString)")
        .accessibilityLabel("Open " + meeting.title)
    }

    @ViewBuilder private func status(_ meeting: Meeting) -> some View {
        if meeting.segments.isEmpty {
            CodaTag(icon: "waveform", text: "Not transcribed")
        } else if meeting.summary != nil {
            CodaTag(icon: "sparkles", text: "Summary", tint: CodaStyle.mint)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 20) {
            CodaEmblem(symbol: "waveform")
            VStack(spacing: 8) {
                Text("No meetings yet").font(.system(size: 18, weight: .semibold))
                Text("Start a recording or import audio. Coda saves the audio first, then transcribes and labels speakers on this Mac.")
                    .font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineSpacing(3)
                    .frame(maxWidth: 380).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 20) {
                Label("Local transcription", systemImage: "lock")
                Label("Up to 4 speakers", systemImage: "person.2")
                Label("Optional AI summary", systemImage: "sparkles")
            }
            .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56).padding(.horizontal, 24)
        .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
    }
}
