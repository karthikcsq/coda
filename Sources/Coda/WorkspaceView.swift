import SwiftUI
import CodaCore

private typealias LocalState<Value> = SwiftUI.State<Value>
private let canvas = Color(red: 0.10, green: 0.10, blue: 0.10)
private let mutedInk = Color.white.opacity(0.57)

struct WorkspaceView: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path").font(.system(size: 23, weight: .medium))
                    Text("coda").font(.system(size: 24, weight: .semibold, design: .rounded))
                }.padding(.horizontal, 24).frame(height: 84, alignment: .center)
                VStack(spacing: 4) {
                    navigation("Dictation", icon: "waveform", section: "Dictation")
                    navigation("Dictionary", icon: "character.book.closed", section: "Dictionary")
                    navigation("Notetaker", icon: "square.and.pencil", section: "Meetings")
                    navigation("Insights", icon: "chart.bar", section: "Insights")
                    navigation("History", icon: "clock.arrow.circlepath", section: "History")
                }.padding(.horizontal, 12)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Make Coda yours").font(.system(size: 12, weight: .semibold))
                    Label("Choose a shortcut", systemImage: "keyboard").font(.system(size: 12))
                    Label("Prepare local dictation", systemImage: "waveform").font(.system(size: 12))
                    Button("Open settings") { model.openSettings() }.font(.system(size: 12)).buttonStyle(.link)
                }.foregroundStyle(mutedInk).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10)).padding(12).padding(.top, 22)
                Spacer()
                VStack(spacing: 4) {
                    Button { model.openSettings() } label: { navLabel("Settings", icon: "gearshape").background(model.showSettings ? Color.white.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain)
                    Menu { Text("Coda runs transcription locally."); Text("Use your shortcut with a text field focused."); Text("Meeting summaries are optional.") } label: { navLabel("Help", icon: "questionmark.circle") }.menuStyle(.borderlessButton)
                }.padding(12)
            }.frame(width: 216).background(Color(white: 0.13))

            Group {
                if model.showSettings { SettingsPanel(model: model, controller: controller) }
                else if controller.workspaceSection == "Dictionary" { DictionaryPage(controller: controller) }
                else if controller.workspaceSection == "Meetings" { NotetakerPage(model: model, controller: controller) }
                else if controller.workspaceSection == "Insights" { InsightsPage(controller: controller) }
                else { DictationPage(model: model, controller: controller, historyOnly: controller.workspaceSection == "History") }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(canvas, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08))).padding(.trailing, 8).padding(.vertical, 8)
        }.background(Color(white: 0.13)).preferredColorScheme(.dark).environment(\.colorScheme, .dark).foregroundStyle(Color(white: 0.88))
        .onAppear {
            delegate.reopenMain = { delegate.showMain { openWindow(id: "main") } }
            controller.showDictionaryWindow = { delegate.reopenMain?() }
            controller.refreshAccessibility()
        }
        .onChange(of: model.selection, initial: true) { _, _ in
            // Imports can originate in the File menu while another workspace is open.
            if model.showingMeetingDetail { controller.workspaceSection = "Meetings" }
        }
    }
    private func navigation(_ title: String, icon: String, section: String) -> some View {
        Button { model.closeSettings(); controller.workspaceSection = section } label: { navLabel(title, icon: icon)
            .background(!model.showSettings && controller.workspaceSection == section ? Color.primary.opacity(0.075) : .clear, in: RoundedRectangle(cornerRadius: 7)) }
            .buttonStyle(.plain).accessibilityIdentifier("coda.nav.\(section.lowercased())")
    }
    private func navLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).frame(width: 16); Text(title).font(.system(size: 14)); Spacer()
            if title == "Dictionary", !controller.dictionary.possible.isEmpty {
                Text("\(controller.dictionary.possible.count)").font(.system(size: 11)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.white.opacity(0.1), in: Capsule()).accessibilityLabel("\(controller.dictionary.possible.count) possible custom words")
            }
        }
            .padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
    }
}

private struct DictationPage: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    let historyOnly: Bool
    @LocalState private var query = ""
    private var records: [DictationRecord] { controller.records.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.target.localizedCaseInsensitiveContains(query) } }
    private var days: [Date] { Array(Set(records.map { Calendar.current.startOfDay(for: $0.created) })).sorted(by: >) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(historyOnly ? "Your history" : "Welcome back.").font(.system(size: 24, weight: .semibold))
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 42) {
                        if !historyOnly { hero }
                        HStack {
                            Text(historyOnly ? "ALL DICTATIONS" : "RECENT DICTATIONS").font(.system(size: 11, weight: .medium)).tracking(1).foregroundStyle(mutedInk)
                            Spacer()
                            TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 120)
                            Image(systemName: "magnifyingglass").foregroundStyle(mutedInk)
                        }
                        if let warning = controller.historyWarning { Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                        if records.isEmpty {
                            VStack(spacing: 12) { Image(systemName: "text.bubble").font(.system(size: 28, weight: .light)); Text(query.isEmpty ? "Your words will appear here." : "No matching dictations."); Text("Click a text field and use your dictation shortcut.").font(.callout).foregroundStyle(mutedInk) }.frame(maxWidth: .infinity).padding(.vertical, 44)
                        }
                        ForEach(days, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 14) {
                                Text(day.formatted(.dateTime.month(.wide).day().year()).uppercased()).font(.system(size: 11, weight: .medium)).tracking(1).foregroundStyle(mutedInk)
                                VStack(spacing: 0) {
                                    let group = records.filter { Calendar.current.isDate($0.created, inSameDayAs: day) }
                                    ForEach(Array(group.enumerated()), id: \.element.id) { index, record in
                                        if index > 0 { Divider().opacity(0.5) }
                                        RecordCard(record: record, controller: controller)
                                    }
                                }.overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.09))).clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        Text("Local Voz transcription · Powered by Desert Ant Labs").font(.system(size: 11)).foregroundStyle(mutedInk)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !historyOnly { statistics.frame(width: 248) }
                }
            }.padding(40).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A little less typing.").font(.system(size: 27, weight: .regular, design: .serif))
            Text("Speak naturally. Keep your words on your Mac.").font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.8))
            Button { model.openSettings() } label: { Text(controller.shortcutLabel == "Choose a shortcut" ? "Set up dictation" : controller.shortcutLabel).font(.system(size: 13, weight: .medium)).padding(.horizontal, 17).padding(.vertical, 11).background(Color(white: 0.19), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).padding(.top, 10)
        }.padding(32).frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.06, green: 0.27, blue: 0.29), Color(red: 0.17, green: 0.22, blue: 0.24), Color(red: 0.35, green: 0.23, blue: 0.17)], startPoint: .leading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
    }
    private var statistics: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                stat("\(controller.records.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count })", "total words")
                stat("\(controller.records.count)", "dictations")
                stat("\(Set(controller.records.map(\.target)).count)", "destinations")
            }.padding(24)
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Label("Local by design", systemImage: "waveform").font(.system(size: 16, weight: .medium))
                Text("Your voice stays on this Mac. Meeting summaries are optional.").font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }.padding(24)
        }.background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
    }
    private func stat(_ value: String, _ label: String) -> some View { HStack(alignment: .firstTextBaseline, spacing: 7) { Text(value).font(.system(size: 27, design: .serif)); Text(label).font(.system(size: 14)).foregroundStyle(Color.white.opacity(0.75)) } }
}
struct RecordCard: View {
    let record: DictationRecord
    @Bindable var controller: DictationController
    @LocalState private var expanded = false
    init(record: DictationRecord, controller: DictationController, expanded: Bool = false) {
        self.record = record; self.controller = controller
        self._expanded = LocalState(initialValue: expanded)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                Text(record.created.formatted(date: .omitted, time: .shortened)).font(.system(size: 12)).foregroundStyle(mutedInk).frame(width: 78, alignment: .leading)
                Text(record.text.isEmpty ? record.detail : record.text).font(.system(size: 14)).lineSpacing(5).lineLimit(expanded ? nil : 4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button { controller.copyRecord(record) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy text")
                Button { expanded.toggle() } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)) }.buttonStyle(.plain).help("Dictation details")
            }
            if let original = record.rawText, original != record.text {
                Button(expanded ? "Cleanup · hide original" : "Cleanup · view original") { expanded.toggle() }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(mutedInk)
            }
            if expanded {
                Divider()
                Text(record.target + " · " + record.detail).font(.system(size: 12)).foregroundStyle(mutedInk)
                if let original = record.rawText, original != record.text {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original dictation").font(.system(size: 11, weight: .semibold)).foregroundStyle(mutedInk)
                        Text(original).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Copy original") { controller.copyOriginal(record) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Button("Insert into another app…") { controller.armInsertion(record) }.buttonStyle(.bordered).controlSize(.small)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
    }
}
private struct MetricTile: View {
    let value: String; let label: String; let symbol: String
    var body: some View {
        HStack { VStack(alignment: .leading, spacing: 7) { Text(value).font(.system(size: 25, weight: .medium)); Text(label).font(.system(size: 12)).foregroundStyle(mutedInk) }; Spacer(); Image(systemName: symbol).foregroundStyle(.tertiary) }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }
}
private struct InsightsPage: View {
    @Bindable var controller: DictationController
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Your voice in numbers").font(.system(size: 28, weight: .semibold))
            Text("Calculated from the dictations saved on this Mac.").font(.system(size: 14)).foregroundStyle(mutedInk)
            HStack(spacing: 12) {
                MetricTile(value: "\(controller.records.count)", label: "Dictations saved", symbol: "waveform")
                MetricTile(value: "\(controller.records.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count })", label: "Words captured", symbol: "text.alignleft")
            }
            Spacer()
        }.padding(40).padding(.top, 18).frame(maxWidth: .infinity, alignment: .leading)
    }
}
