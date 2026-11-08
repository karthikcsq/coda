import SwiftUI
import CodaCore

private typealias LocalState<Value> = SwiftUI.State<Value>

struct WorkspaceView: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var shortcutReady: Bool { controller.shortcutLabel != "Choose a shortcut" }
    private var setupComplete: Bool { controller.readiness(for: model).canDictate }
    private var page: String { model.showSettings ? "Settings" : controller.workspaceSection }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                if model.showSettings { SettingsPanel(model: model, controller: controller) }
                else if controller.workspaceSection == "Home" { HomePage(model: model, controller: controller) }
                else if controller.workspaceSection == "Personalize" { PersonalizationPage(model: model, controller: controller) }
                else if controller.workspaceSection == "Dictionary" { DictionaryPage(controller: controller) }
                else if controller.workspaceSection == "Meetings" { NotetakerPage(model: model, controller: controller) }
                else if controller.workspaceSection == "Insights" { InsightsPage(controller: controller) }
                else { DictationPage(model: model, controller: controller, historyOnly: controller.workspaceSection == "History") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CodaStyle.canvas, in: RoundedRectangle(cornerRadius: CodaStyle.radiusShell))
            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusShell).strokeBorder(CodaStyle.hairline))
            .padding(.trailing, 8).padding(.vertical, 8)
            .animation(CodaStyle.motion(reduceMotion, duration: 0.18), value: page)
        }
        .background(CodaStyle.chrome)
        .preferredColorScheme(.dark).environment(\.colorScheme, .dark).foregroundStyle(CodaStyle.ink)
        .onAppear {
            delegate.reopenMain = { delegate.showMain { openWindow(id: "main") } }
            controller.showDictionaryWindow = { delegate.reopenMain?() }
            controller.refreshAccessibility()
            if !model.isVisualReview && !controller.onboardingSeen && !model.modelConsent && !model.dictationModelReady {
                controller.showOnboarding = true
            }
        }
        .sheet(isPresented: $controller.showOnboarding) { OnboardingView(model: model, controller: controller) }
        .onChange(of: controller.workspaceSection) { _, section in
            if section == "Dictation" { model.warmDictation() }
        }
        .onChange(of: model.selection, initial: true) { _, _ in
            // Imports can originate in the File menu while another workspace is open.
            if model.showingMeetingDetail { controller.workspaceSection = "Meetings" }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path").font(.system(size: 20, weight: .medium)).foregroundStyle(CodaStyle.mint)
                Text("coda").font(.system(size: 23, weight: .semibold, design: .rounded))
            }.padding(.horizontal, 22).frame(height: 76, alignment: .center).accessibilityAddTraits(.isHeader)
            VStack(spacing: 3) {
                navigation("Home", icon: "house", section: "Home", hint: "Setup status, quick actions and recent work")
                navigation("Dictation", icon: "waveform", section: "Dictation", hint: "Start dictating and see recent results")
                navigation("Make it yours", icon: "slider.horizontal.3", section: "Personalize", hint: "Writing style, app preferences and voice snippets")
                navigation("Dictionary", icon: "character.book.closed", section: "Dictionary", hint: "Custom words and suggestions to review")
                navigation("Meetings", icon: "square.and.pencil", section: "Meetings", hint: "Meeting recordings, transcripts and summaries")
                navigation("Insights", icon: "chart.bar", section: "Insights", hint: "Counts from the dictations saved on this Mac")
                navigation("History", icon: "clock.arrow.circlepath", section: "History", hint: "Every dictation Coda has saved")
            }.padding(.horizontal, 12)
            if !setupComplete && controller.workspaceSection != "Home" { setupCard.padding(12).padding(.top, 18) }
            Spacer(minLength: 12)
            VStack(spacing: 3) {
                Button { model.openSettings() } label: { navLabel("Settings", icon: "gearshape") }
                    .buttonStyle(CodaNavRowStyle(selected: model.showSettings))
                    .accessibilityLabel("Settings")
                Button { controller.showOnboarding = true } label: { navLabel("Setup guide", icon: "questionmark.circle") }
                    .buttonStyle(CodaNavRowStyle(selected: false)).disabled(model.settingsChangesLocked)
                    .accessibilityLabel("Open setup guide")
            }.padding(12)
        }
        .frame(width: 216)
        .background(CodaStyle.chrome)
    }
    /// Only shown while a step is genuinely outstanding, and every row is a real control.
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CodaEyebrow(text: "Finish setting up")
            Text(controller.readiness(for: model).nextAction).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
            Button("Continue setup") { controller.showOnboarding = true }.buttonStyle(CodaSecondaryButtonStyle()).disabled(model.settingsChangesLocked)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radius).strokeBorder(CodaStyle.hairline))
    }
    private func setupStep(_ title: String, label: String, icon: String, done: Bool) -> some View {
        Button { model.openSettings() } label: {
            HStack(spacing: 9) {
                Image(systemName: done ? "checkmark.circle.fill" : icon).font(.system(size: 12))
                    .foregroundStyle(done ? CodaStyle.mint : CodaStyle.muted).frame(width: 14)
                Text(label).font(CodaStyle.secondaryFont).lineLimit(1)
                    .foregroundStyle(done ? CodaStyle.muted : CodaStyle.ink)
                Spacer(minLength: 4)
                if !done { Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(CodaStyle.muted) }
            }
            .padding(.horizontal, 6).frame(height: 26).contentShape(Rectangle())
        }
        .buttonStyle(CodaNavRowStyle(selected: false))
        .accessibilityLabel(done ? title + ", done" : title + ", open settings to finish")
    }
    private func navigation(_ title: String, icon: String, section: String, hint: String) -> some View {
        Button { model.closeSettings(); controller.workspaceSection = section } label: { navLabel(title, icon: icon) }
            .buttonStyle(CodaNavRowStyle(selected: !model.showSettings && controller.workspaceSection == section))
            .accessibilityIdentifier("coda.nav.\(section.lowercased())")
            .accessibilityLabel(title)
            .accessibilityHint(hint)
            .accessibilityAddTraits(!model.showSettings && controller.workspaceSection == section ? .isSelected : [])
    }
    private func navLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).frame(width: 16)
            Text(title).font(CodaStyle.bodyFont)
            Spacer(minLength: 4)
            if title == "Dictionary", !controller.dictionary.possible.isEmpty {
                CodaCountBadge(count: controller.dictionary.possible.count, tint: CodaStyle.mint)
                    .accessibilityLabel("\(controller.dictionary.possible.count) possible custom words")
            }
        }
        .padding(.horizontal, 12).frame(height: CodaStyle.rowHeight).contentShape(Rectangle())
    }
}

private struct DictationPage: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    let historyOnly: Bool
    @LocalState private var query = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var records: [DictationRecord] { controller.records.filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || $0.target.localizedCaseInsensitiveContains(query) } }
    private var days: [Date] { Array(Set(records.map { Calendar.current.startOfDay(for: $0.created) })).sorted(by: >) }
    private var shortcutReady: Bool { controller.shortcutLabel != "Choose a shortcut" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CodaStyle.blockSpacing) {
                if historyOnly {
                    CodaPageHeader(icon: "clock.arrow.circlepath", title: "History",
                                   subtitle: "Every dictation Coda has saved on this Mac.")
                } else {
                    hero
                }
                HStack(alignment: .center, spacing: 12) {
                    CodaEyebrow(text: historyOnly ? "All dictations" : "Recent dictations")
                    if !records.isEmpty { CodaCountBadge(count: records.count) }
                    Spacer(minLength: 12)
                    CodaSearchField(prompt: "Search dictations", text: $query, width: 210)
                }
                if let warning = controller.historyWarning { CodaNotice(kind: .caution, text: warning) }
                if records.isEmpty {
                    CodaEmptyState(
                        icon: query.isEmpty ? "text.bubble" : "magnifyingglass",
                        title: query.isEmpty ? "Your words will appear here" : "No matching dictations",
                        message: query.isEmpty
                            ? "Click into a text field, use your dictation shortcut, and the result is saved here."
                            : "Try a different word, or search by the app you dictated into.",
                        tint: query.isEmpty ? CodaStyle.mint : CodaStyle.muted)
                } else {
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 12) {
                            CodaEyebrow(text: dayLabel(day))
                            VStack(spacing: 0) {
                                let group = records.filter { Calendar.current.isDate($0.created, inSameDayAs: day) }
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, record in
                                    if index > 0 { Divider().opacity(0.4) }
                                    RecordCard(record: record, controller: controller)
                                }
                            }
                            .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
                            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
                        }
                    }
                }
                Text("Local Voz transcription · Powered by Desert Ant Labs")
                    .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
            }
            .codaPageInsets()
            .animation(CodaStyle.motion(reduceMotion, duration: 0.18), value: records.count)
        }
    }
    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    private var hero: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 9) {
                CodaEyebrow(text: "Dictation")
                Text("A little less typing.").font(.system(size: 27, weight: .medium, design: .rounded))
                Text("Focus a text field and use your shortcut. Your words are saved before insertion.")
                    .font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(controller.readiness(for: model).canDictate ? "Try a dictation" : "Set up dictation") { controller.showOnboarding = true }
                        .buttonStyle(CodaPrimaryButtonStyle())
                    if shortcutReady {
                        CodaStatusChip(readiness: model.dictationModelReady ? .ready : .pending,
                                       text: model.dictationModelReady ? controller.shortcutLabel : "Model needs preparing")
                    }
                }.padding(.top, 7)
            }
            Spacer(minLength: 0)
            Image(systemName: "waveform").font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(CodaStyle.mint.opacity(0.5)).accessibilityHidden(true)
        }
        .padding(28).frame(maxWidth: .infinity, alignment: .leading)
        .background(CodaStyle.heroGradient, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
    }
}

struct RecordCard: View {
    let record: DictationRecord
    @Bindable var controller: DictationController
    @LocalState private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(record: DictationRecord, controller: DictationController, expanded: Bool = false) {
        self.record = record; self.controller = controller
        self._expanded = LocalState(initialValue: expanded)
    }
    private var cleanedOriginal: String? {
        guard let original = record.rawText, original != record.text else { return nil }
        return original
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 16) {
                Text(record.created.formatted(date: .omitted, time: .shortened))
                    .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                    .monospacedDigit().frame(width: 72, alignment: .leading).padding(.top, 2)
                Text(record.text.isEmpty ? record.detail : record.text)
                    .font(CodaStyle.bodyFont).lineSpacing(5).lineLimit(expanded ? nil : 4)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                Button { controller.copyRecord(record) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(CodaIconButtonStyle()).help("Copy text").accessibilityLabel("Copy this dictation")
                // One control owns the disclosure, so the row cannot disagree with itself.
                Button { expanded.toggle() } label: {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .buttonStyle(CodaIconButtonStyle())
                .help(expanded ? "Hide dictation details" : "Show dictation details")
                .accessibilityLabel(expanded ? "Hide dictation details" : "Show dictation details")
            }
            HStack(spacing: 10) {
                Text(record.target).font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted).lineLimit(1)
                if cleanedOriginal != nil {
                    CodaStatusChip(readiness: .ready, text: "Cleaned up")
                        .accessibilityLabel("Automatic cleanup was applied; the original is in the details")
                }
                Spacer(minLength: 0)
            }.padding(.leading, 88)
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().opacity(0.4)
                    Text(record.detail).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let original = cleanedOriginal {
                        VStack(alignment: .leading, spacing: 8) {
                            CodaEyebrow(text: "Original dictation")
                            Text(original).font(.system(size: 13)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Copy original") { controller.copyOriginal(record) }
                                .buttonStyle(CodaSecondaryButtonStyle())
                        }
                        .padding(14)
                        .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
                    }
                    Button("Insert into another app…") { controller.armInsertion(record) }
                        .buttonStyle(CodaSecondaryButtonStyle())
                }
                .padding(.leading, 88)
                .transition(.opacity)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .animation(CodaStyle.motion(reduceMotion, duration: 0.18), value: expanded)
    }
}

private struct MetricTile: View {
    let value: String
    let label: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(CodaStyle.mint).accessibilityHidden(true)
            Text(value).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
            Text(label).font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radius).strokeBorder(CodaStyle.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// Only counts Coda can actually derive from local history. No projections, no invented
/// time-saved figures: the numbers here are the saved records and nothing more.
private struct InsightsPage: View {
    @Bindable var controller: DictationController
    private var words: Int { controller.records.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } }
    private var destinations: [(name: String, count: Int)] {
        Dictionary(grouping: controller.records, by: \.target)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
    private var cleanedUp: Int { controller.records.filter { $0.rawText != nil && $0.rawText != $0.text }.count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CodaStyle.blockSpacing) {
                CodaPageHeader(icon: "chart.bar", title: "Insights",
                               subtitle: "Counted from the dictations saved on this Mac. Nothing is estimated.")
                if controller.records.isEmpty {
                    CodaEmptyState(icon: "chart.bar.doc.horizontal", title: "No dictations to count yet",
                                   message: "Once you dictate, Coda totals what it saved locally: how many dictations, how many words, and which apps you dictated into.",
                                   tint: CodaStyle.mint)
                } else {
                    HStack(spacing: 12) {
                        MetricTile(value: "\(controller.records.count)", label: controller.records.count == 1 ? "Dictation saved" : "Dictations saved", symbol: "waveform")
                        MetricTile(value: "\(words)", label: "Words captured", symbol: "text.alignleft")
                        MetricTile(value: "\(destinations.count)", label: destinations.count == 1 ? "Destination" : "Destinations", symbol: "app.badge")
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 9) {
                            Text("Where your words went").font(CodaStyle.sectionFont)
                            CodaCountBadge(count: destinations.count)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(destinations.prefix(8).enumerated()), id: \.element.name) { index, entry in
                                if index > 0 { Divider().opacity(0.3) }
                                HStack(spacing: 12) {
                                    Text(entry.name).font(.system(size: 13)).lineLimit(1)
                                    Spacer(minLength: 12)
                                    Text(entry.count == 1 ? "1 dictation" : "\(entry.count) dictations")
                                        .font(CodaStyle.secondaryFont).foregroundStyle(.secondary).monospacedDigit()
                                }.padding(.horizontal, 16).frame(height: 40)
                            }
                        }
                        .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
                        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radius).strokeBorder(CodaStyle.hairline))
                        if destinations.count > 8 {
                            Text("Showing the 8 most used destinations.")
                                .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                        }
                    }
                    if cleanedUp > 0 {
                        CodaNotice(kind: .info, text: cleanedUp == 1
                            ? "1 dictation has an original saved before automatic cleanup. Open it in History to compare."
                            : "\(cleanedUp) dictations have originals saved before automatic cleanup. Open one in History to compare.")
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Local by design", systemImage: "internaldrive").font(.system(size: 14, weight: .medium))
                    Text("Dictation is transcribed on this Mac and these counts never leave it. Optional meeting summaries send transcript text to OpenAI, either with your confirmation or after you enable automatic summaries.")
                        .font(CodaStyle.secondaryFont).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.codaCard(fill: CodaStyle.chrome)
            }.codaPageInsets()
        }
    }
}
