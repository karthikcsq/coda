import SwiftUI
import AVFoundation
import CodaCore

private typealias HomeState<Value> = SwiftUI.State<Value>

extension DictationController {
    func readiness(for model: AppModel) -> SetupReadiness {
        SetupReadiness(modelConsent: model.modelConsent, modelPrepared: model.dictationModelReady,
                       microphoneAllowed: permissionGranted, shortcutAssigned: shortcutLabel != "Choose a shortcut",
                       modifierShortcut: modifierShortcut, accessibilityAllowed: accessibility.trusted)
    }
}

struct HomePage: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    @HomeState private var refreshID = 0
    @HomeState private var query = ""
    @HomeState private var searching = false
    @HomeState private var selection: UUID?
    @FocusState private var searchFocused: Bool
    init(model: AppModel, controller: DictationController, initialSelection: UUID? = nil) {
        self.model = model; self.controller = controller
        _selection = HomeState(initialValue: initialSelection)
    }
    private var readiness: SetupReadiness { _ = refreshID; return controller.readiness(for: model) }
    private var locked: Bool { model.settingsChangesLocked || controller.lifecycle.busy }
    private var modelReady: Bool { model.modelConsent && model.dictationModelReady }
    private var shortcutReady: Bool { readiness.shortcutAssigned && (!readiness.modifierShortcut || readiness.accessibilityAllowed) }
    private var greeting: String {
        let part = switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? part + "." : part + ", " + first + "."
    }
    /// Dictations and meetings in one timeline, newest first.
    fileprivate enum Item: Identifiable {
        case dictation(DictationRecord), meeting(Meeting)
        var id: UUID { switch self { case .dictation(let r): r.id; case .meeting(let m): m.id } }
        var created: Date { switch self { case .dictation(let r): r.created; case .meeting(let m): m.created } }
    }
    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let records = controller.records.filter { !$0.text.isEmpty && (q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) || $0.target.localizedCaseInsensitiveContains(q)) }
        let meetings = model.meetings.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) }
        return (records.map(Item.dictation) + meetings.map(Item.meeting)).sorted { $0.created > $1.created }
    }
    private var days: [Date] { Array(Set(items.map { Calendar.current.startOfDay(for: $0.created) })).sorted(by: >) }
    private var wordsThisWeek: Int {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return controller.records.filter { $0.created >= start }.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }
    var body: some View {
        let all = items
        let selected = all.first { $0.id == selection } ?? all.first
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                timeline(all, selected: selected?.id).frame(width: 340)
                Rectangle().fill(CodaStyle.hairline).frame(width: 1)
                Group {
                    if let selected { document(for: selected) } else { firstPage }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CodaStyle.sheet)
            }
            dock.padding(.bottom, 20)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAccessibility(); refreshID += 1
        }
    }

    // MARK: Left column

    private func timeline(_ all: [Item], selected: UUID?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(greeting).font(CodaStyle.serif(30)).tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                shortcutChip.padding(.top, 12)
                if searching {
                    CodaSearchField(prompt: "Search history", text: $query).focused($searchFocused).padding(.top, 20)
                }
                if !readiness.canDictate { setupSteps.padding(.top, 26) }
                else if !controller.accessibility.trusted {
                    Button { controller.showOnboarding = true } label: {
                        Label("Allow Coda to paste for you", systemImage: "exclamationmark.circle").font(CodaStyle.secondaryFont)
                    }.buttonStyle(.plain).foregroundStyle(CodaStyle.caution).padding(.top, 14).disabled(locked)
                }
                if let warning = controller.historyWarning { CodaNotice(kind: .caution, text: warning).padding(.top, 16) }
                if all.isEmpty && !query.isEmpty {
                    Text("Nothing matches “\(query)”.").font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.muted).padding(.top, 24)
                }
                ForEach(days, id: \.self) { day in
                    Text(dayLabel(day)).font(CodaStyle.serif(17)).padding(.top, 28).padding(.bottom, 8).padding(.leading, 2)
                    ForEach(all.filter { Calendar.current.isDate($0.created, inSameDayAs: day) }) { item in
                        row(item, selected: item.id == selected)
                    }
                }
                if wordsThisWeek > 0 {
                    Rectangle().fill(CodaStyle.hairline).frame(height: 1).padding(.top, 24)
                    Text("\(wordsThisWeek.formatted()) words dictated this week")
                        .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.faint).padding(.top, 12)
                }
            }
            .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 110)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private var shortcutChip: some View {
        if controller.shortcutLabel == "Choose a shortcut" {
            Button("Choose a shortcut") { controller.showOnboarding = true }
                .buttonStyle(CodaSecondaryButtonStyle()).disabled(locked)
        } else {
            HStack(spacing: 7) {
                Text(compactShortcut).font(.system(size: 12, weight: .semibold))
                Text(controller.mode == .hold ? "hold to talk" : "press to talk").font(.system(size: 12))
                    .foregroundStyle(CodaStyle.muted)
            }
            .padding(.horizontal, 10).frame(height: 26)
            .background(CodaStyle.sunken, in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }
    /// "⇧⌃⌥ Shift + Control + Option" reads as "⇧⌃⌥": the glyphs alone are enough here.
    private var compactShortcut: String {
        let label = controller.shortcutLabel
        if let first = label.split(separator: " ").first, first.contains(where: { "⌃⌥⇧⌘".contains($0) }) { return String(first) }
        return label
    }
    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Get ready").font(CodaStyle.serif(17)).padding(.bottom, 6)
            setupStep(1, "Speech model", done: modelReady)
            setupStep(2, "Microphone", done: readiness.microphoneAllowed)
            setupStep(3, "Shortcut", done: shortcutReady)
        }
    }
    private func setupStep(_ number: Int, _ title: String, done: Bool) -> some View {
        Button { controller.showOnboarding = true } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", number)).font(CodaStyle.serif(15, .regular)).foregroundStyle(CodaStyle.faint)
                    .monospacedDigit().frame(width: 22, alignment: .leading)
                Text(title).font(CodaStyle.rowTitleFont).foregroundStyle(done ? CodaStyle.muted : CodaStyle.ink)
                Spacer(minLength: 8)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(CodaStyle.mint)
                } else {
                    Text("Set up").font(.system(size: 12, weight: .medium)).foregroundStyle(CodaStyle.mint)
                }
            }
            .padding(.vertical, 10).contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(CodaStyle.hairline).frame(height: 1) }
        }
        .buttonStyle(.plain).disabled(locked)
        .accessibilityLabel(title + (done ? ", ready" : ", needs setup"))
    }
    private func row(_ item: Item, selected: Bool) -> some View {
        Button { selection = item.id } label: {
            HStack(alignment: .top, spacing: 11) {
                switch item {
                case .dictation(let record):
                    AppIcon(name: record.target, size: 22).padding(.top, 1)
                    Text(record.text).font(.system(size: 13)).lineLimit(2).lineSpacing(2)
                        .foregroundStyle(CodaStyle.ink).frame(maxWidth: .infinity, alignment: .leading)
                    Text(record.created.formatted(date: .omitted, time: .shortened)).font(CodaStyle.captionFont)
                        .foregroundStyle(CodaStyle.faint).monospacedDigit().padding(.top, 2)
                case .meeting(let meeting):
                    Image(systemName: "calendar").font(.system(size: 15)).foregroundStyle(CodaStyle.muted)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meeting.title).font(CodaStyle.serif(15)).foregroundStyle(CodaStyle.ink).lineLimit(2)
                        HStack(spacing: 5) {
                            if let duration = durationText(meeting) { Chip(text: duration) }
                            if let people = peopleText(meeting) { Chip(text: people) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(meeting.created.formatted(date: .omitted, time: .shortened)).font(CodaStyle.captionFont)
                        .foregroundStyle(CodaStyle.faint).monospacedDigit().padding(.top, 3)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .background(selected ? CodaStyle.selected : .clear, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Document pane

    @ViewBuilder private func document(for item: Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch item {
                case .dictation(let record): dictationDocument(record)
                case .meeting(let meeting): meetingDocument(meeting)
                }
            }
            .padding(.horizontal, 52).padding(.top, 44).padding(.bottom, 120)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(item.id)
    }
    private func dateline(_ date: Date) -> String {
        let day = Calendar.current.isDateInToday(date) ? "Today" : Calendar.current.isDateInYesterday(date) ? "Yesterday"
            : date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return day + ", " + date.formatted(date: .omitted, time: .shortened)
    }
    private func dictationDocument(_ record: DictationRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dateline(record.created)).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.faint)
            HStack(spacing: 8) {
                AppIcon(name: record.target, size: 20)
                Text(record.target).font(.system(size: 13, weight: .medium)).foregroundStyle(CodaStyle.muted)
            }.padding(.top, 14)
            Text(record.text).font(CodaStyle.serif(22, .regular)).lineSpacing(7).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 22)
            HStack(spacing: 8) {
                Button { controller.copyRecord(record) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(CodaSecondaryButtonStyle())
                Button("Insert into another app…") { controller.armInsertion(record) }
                    .buttonStyle(CodaSecondaryButtonStyle())
            }.padding(.top, 28)
            if let original = record.rawText, original != record.text {
                docHeading("Before cleanup").padding(.top, 40)
                Text(original).font(.system(size: 14)).foregroundStyle(CodaStyle.muted).lineSpacing(4)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                Button("Copy original") { controller.copyOriginal(record) }.buttonStyle(CodaQuietButtonStyle()).padding(.top, 10)
            }
        }
    }
    private func meetingDocument(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(dateline(meeting.created)).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.faint)
                Spacer()
                Button("Open meeting") { openMeeting(meeting) }.buttonStyle(CodaQuietButtonStyle())
            }
            Text(meeting.title).font(CodaStyle.serif(36)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            HStack(spacing: 6) {
                if let duration = durationText(meeting) { Chip(text: duration, large: true) }
                ForEach(speakerNames(meeting), id: \.self) { Chip(text: $0, large: true) }
            }.padding(.top, 14)
            if let summary = meeting.summary {
                let lead = summary.brief.map { [$0] } ?? Array(summary.overview.prefix(1))
                if !lead.isEmpty || !summary.takeaways.isEmpty {
                    docHeading("Summary").padding(.top, 36)
                    ForEach(Array(lead.enumerated()), id: \.offset) { _, item in
                        Text(item.text).font(.system(size: 15)).lineSpacing(4).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                    }
                    bullets(summary.takeaways.map(\.text))
                }
                if !summary.actions.isEmpty {
                    docHeading("Next steps").padding(.top, 32)
                    bullets(summary.actions.map { ($0.owner.map { $0 + ": " } ?? "") + $0.text })
                }
            } else {
                Text("No summary yet. Open the meeting to summarize it.").font(CodaStyle.bodyFont)
                    .foregroundStyle(CodaStyle.muted).padding(.top, 32)
            }
            if !meeting.segments.isEmpty {
                docHeading("Transcript").padding(.top, 36)
                ForEach(meeting.segments.prefix(8)) { segment in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meeting.speakerLabel(segment.speakers)).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(CodaStyle.speakerColor(segment.speakers.first ?? 0))
                        Text(segment.text).font(.system(size: 15)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 14)
                }
                if meeting.segments.count > 8 {
                    Button("Read the full transcript") { openMeeting(meeting) }
                        .buttonStyle(CodaQuietButtonStyle()).padding(.top, 16)
                }
            }
        }
    }
    private func docHeading(_ text: String) -> some View {
        Text(text).font(CodaStyle.serif(21)).tracking(-0.3)
    }
    private func bullets(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(CodaStyle.mint).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                    Text(line).font(.system(size: 15)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.padding(.top, 12)
    }
    private var firstPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A fresh page for your voice.").font(CodaStyle.serif(30)).tracking(-0.6)
            Text(readiness.canDictate ? "Dictate into any app with your shortcut, or record a meeting. Everything you say lands here."
                 : "Finish the three steps on the left, then speak into any app or record a meeting.")
                .font(.system(size: 15)).foregroundStyle(CodaStyle.muted).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 440, alignment: .leading)
        }
        .padding(52).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Dock

    private var dock: some View {
        HStack(spacing: 4) {
            Button { model.closeSettings(); controller.workspaceSection = "Meetings"; model.requestMeetingRecording() } label: {
                Label("New meeting", systemImage: "calendar.badge.plus").padding(.horizontal, 12).frame(height: 34)
            }.buttonStyle(DockButtonStyle()).disabled(locked)
            Rectangle().fill(CodaStyle.hairline).frame(width: 1, height: 20)
            Button { searching.toggle(); if searching { searchFocused = true } else { query = "" } } label: {
                Image(systemName: searching ? "xmark" : "magnifyingglass").frame(width: 34, height: 34)
            }.buttonStyle(DockButtonStyle()).help(searching ? "Close search" : "Search history")
                .accessibilityLabel(searching ? "Close search" : "Search history")
            Rectangle().fill(CodaStyle.hairline).frame(width: 1, height: 20)
            Button { controller.showOnboarding = true } label: {
                Label(readiness.canDictate ? "Start dictation" : "Finish setup", systemImage: readiness.canDictate ? "mic" : "arrow.right")
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(CodaStyle.mint, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(CodaStyle.onAccent)
            }.buttonStyle(.plain).disabled(locked)
                .help(readiness.canDictate ? "Practice here; in other apps, use your shortcut" : "Finish setting up dictation")
        }
        .font(.system(size: 13, weight: .medium))
        .padding(5)
        .background(CodaStyle.sheet, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CodaStyle.hairline))
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }

    // MARK: Helpers

    private func openMeeting(_ meeting: Meeting) {
        model.closeSettings(); controller.workspaceSection = "Meetings"; model.openMeeting(meeting.id)
    }
    private func durationText(_ meeting: Meeting) -> String? {
        guard let end = meeting.segments.last?.end, end > 0 else { return nil }
        return Duration.seconds(end).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
    }
    private func speakerNames(_ meeting: Meeting) -> [String] {
        Array(Set(meeting.segments.flatMap(\.speakers))).sorted().map { meeting.speakerLabel([$0]) }
    }
    private func peopleText(_ meeting: Meeting) -> String? {
        let names = speakerNames(meeting)
        return names.isEmpty ? nil : names.count > 2 ? names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)" : names.joined(separator: ", ")
    }
    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

/// Small metadata pill: duration, speakers, dates.
struct Chip: View {
    let text: String
    var large = false
    var body: some View {
        Text(text).font(.system(size: large ? 13 : 11.5)).foregroundStyle(CodaStyle.ink.opacity(0.75)).lineLimit(1)
            .padding(.horizontal, large ? 10 : 7).frame(height: large ? 26 : 20)
            .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: large ? 7 : 6))
    }
}

private struct DockButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        StyleBody(configuration: configuration)
    }
    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @HomeState private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .foregroundStyle(CodaStyle.ink)
                .background(configuration.isPressed ? CodaStyle.selected : hovering ? CodaStyle.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}
