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
    private var readiness: SetupReadiness { _ = refreshID; return controller.readiness(for: model) }
    private var locked: Bool { model.settingsChangesLocked || controller.lifecycle.busy }
    private var modelReady: Bool { model.modelConsent && model.dictationModelReady }
    private var shortcutReady: Bool { readiness.shortcutAssigned && (!readiness.modifierShortcut || readiness.accessibilityAllowed) }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
    /// Dictations and meetings in one timeline, newest first.
    private enum Item: Identifiable {
        case dictation(DictationRecord), meeting(Meeting)
        var id: UUID { switch self { case .dictation(let r): r.id; case .meeting(let m): m.id } }
        var created: Date { switch self { case .dictation(let r): r.created; case .meeting(let m): m.created } }
    }
    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let records = controller.records.filter { q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) || $0.target.localizedCaseInsensitiveContains(q) }
        let meetings = model.meetings.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) }
        return (records.map(Item.dictation) + meetings.map(Item.meeting)).sorted { $0.created > $1.created }
    }
    private var days: [Date] { Array(Set(items.map { Calendar.current.startOfDay(for: $0.created) })).sorted(by: >) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 12) {
                    Text(greeting).font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                    Spacer(minLength: 12)
                    Button { model.closeSettings(); controller.workspaceSection = "Meetings"; model.requestMeetingRecording() } label: {
                        Label("New meeting", systemImage: "record.circle")
                    }.buttonStyle(CodaSecondaryButtonStyle()).disabled(locked)
                }
                if !readiness.canDictate { setupStrip }
                else if !controller.accessibility.trusted {
                    CodaNotice(kind: .caution, text: "Turn on Accessibility so Coda can paste for you.")
                }
                if readiness.canDictate {
                    HStack(alignment: .top, spacing: 12) {
                        ShortcutHint(controller: controller, ready: true)
                        if !controller.records.isEmpty { ActivityCard(records: controller.records).frame(width: 260) }
                    }.fixedSize(horizontal: false, vertical: true)
                }
                history
            }.codaPageInsets()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAccessibility(); refreshID += 1
        }
    }
    private var setupStrip: some View {
        HStack(spacing: 8) {
            step("Speech model", icon: "cpu", done: modelReady)
            step("Microphone", icon: "mic", done: readiness.microphoneAllowed)
            step("Shortcut", icon: "command", done: shortcutReady)
            Spacer(minLength: 8)
            Button { controller.showOnboarding = true } label: {
                HStack(spacing: 6) { Text("Finish setup"); Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)) }
            }.buttonStyle(CodaPrimaryButtonStyle()).disabled(locked)
        }
        .padding(10).padding(.leading, 2)
        .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
    }
    private func step(_ title: String, icon: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark" : icon).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(done ? Color(white: 0.07) : CodaStyle.muted)
                .frame(width: 20, height: 20)
                .background(done ? CodaStyle.mint : Color.white.opacity(0.07), in: Circle())
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(done ? CodaStyle.muted : CodaStyle.ink)
        }
        .padding(.trailing, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + (done ? ", ready" : ", needs setup"))
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("History").font(.system(size: 15, weight: .semibold)).tracking(-0.2)
                Spacer(minLength: 12)
                CodaSearchField(prompt: "Search", text: $query, width: 200)
            }
            if let warning = controller.historyWarning { CodaNotice(kind: .caution, text: warning) }
            if items.isEmpty {
                CodaEmptyState(icon: query.isEmpty ? "clock" : "magnifyingglass",
                               title: query.isEmpty ? "Nothing yet" : "No matches",
                               message: query.isEmpty ? "Dictations and meetings will appear here." : "Try another word or app name.")
            } else {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        CodaEyebrow(text: dayLabel(day)).padding(.leading, 2)
                        VStack(spacing: 0) {
                            let group = items.filter { Calendar.current.isDate($0.created, inSameDayAs: day) }
                            ForEach(Array(group.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Rectangle().fill(CodaStyle.hairline).frame(height: 1).padding(.leading, 56) }
                                switch item {
                                case .dictation(let record): RecordCard(record: record, controller: controller)
                                case .meeting(let meeting): meetingRow(meeting)
                                }
                            }
                        }
                        .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
                        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
                    }
                }
            }
        }
    }
    private func meetingRow(_ meeting: Meeting) -> some View {
        Button {
            model.closeSettings(); controller.workspaceSection = "Meetings"; model.openMeeting(meeting.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill").font(.system(size: 11)).foregroundStyle(CodaStyle.speakerColor(1))
                    .frame(width: 28, height: 28)
                    .background(CodaStyle.speakerColor(1).opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).font(CodaStyle.rowTitleFont).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("Meeting")
                        Text("·")
                        Text(meeting.created.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                        if let end = meeting.segments.last?.end, end > 0 {
                            Text("·"); Text(Duration.seconds(end).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
                        }
                    }.font(CodaStyle.captionFont).foregroundStyle(CodaStyle.faint)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(CodaStyle.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(CodaTableRowStyle())
    }
    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

/// Real counts only: words dictated on each of the last seven days.
struct ActivityCard: View {
    let records: [DictationRecord]
    private var week: [(day: Date, words: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let words = records.filter { calendar.isDate($0.created, inSameDayAs: day) }
                .reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            return (day, words)
        }
    }
    var body: some View {
        let data = week
        let total = data.reduce(0) { $0 + $1.words }
        let peak = max(data.map(\.words).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(total.formatted()).font(.system(size: 20, weight: .semibold)).tracking(-0.4).monospacedDigit()
                Text("words this week").font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, entry in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(index == data.count - 1 ? CodaStyle.mint : CodaStyle.mint.opacity(entry.words > 0 ? 0.4 : 0.12))
                            .frame(height: max(3, 34 * CGFloat(entry.words) / CGFloat(peak)))
                        Text(entry.day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9, weight: .medium))
                            .foregroundStyle(CodaStyle.faint)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 48, alignment: .bottom)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) words dictated in the last seven days")
    }
}
