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
            .clipShape(RoundedRectangle(cornerRadius: CodaStyle.radiusShell))
            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusShell).strokeBorder(CodaStyle.hairline))
            .padding(.trailing, 8).padding(.vertical, 8)
            .animation(CodaStyle.motion(reduceMotion, duration: 0.18), value: page)
        }
        .background(CodaStyle.chrome)
        .tint(CodaStyle.mint)
        .preferredColorScheme(.light).environment(\.colorScheme, .light).foregroundStyle(CodaStyle.ink)
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
            Text(BuildIdentity.name).font(CodaStyle.serif(22)).tracking(-0.4)
                .padding(.horizontal, 20).padding(.top, 10).frame(height: 64, alignment: .center).accessibilityAddTraits(.isHeader)
            if BuildIdentity.isDevelopment {
                Text("DEVELOPMENT").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(CodaStyle.mint).padding(.horizontal, 20).padding(.bottom, 10)
            }
            VStack(spacing: 1) {
                navigation("Home", icon: "house", section: "Home", hint: "Your shortcut, activity and full history")
                navigation("Dictation", icon: "waveform", section: "Dictation", hint: "Start dictating and see recent results")
                navigation("Meetings", icon: "person.2", section: "Meetings", hint: "Meeting recordings, transcripts and summaries")
                navigation("Insights", icon: "chart.bar", section: "Insights", hint: "Counts from the dictations saved on this Mac")
                navGroup("Customize")
                navigation("Make it yours", icon: "slider.horizontal.3", section: "Personalize", hint: "Writing style, app preferences and voice snippets")
                navigation("Dictionary", icon: "character.book.closed", section: "Dictionary", hint: "Custom words and suggestions to review")
            }.padding(.horizontal, 10)
            Spacer(minLength: 12)
            if !setupComplete && controller.workspaceSection != "Home" { setupCard.padding(.horizontal, 10).padding(.bottom, 6) }
            VStack(spacing: 1) {
                Button { model.openSettings() } label: { navLabel("Settings", icon: "gearshape", selected: model.showSettings) }
                    .buttonStyle(CodaNavRowStyle(selected: model.showSettings))
                    .accessibilityLabel("Settings")
                Button { controller.showOnboarding = true } label: { navLabel("Setup guide", icon: "questionmark.circle", selected: false) }
                    .buttonStyle(CodaNavRowStyle(selected: false)).disabled(model.settingsChangesLocked)
                    .accessibilityLabel("Open setup guide")
            }.padding(10)
        }
        .frame(width: 208)
        .background(CodaStyle.chrome)
    }
    /// Only shown while a step is genuinely outstanding, and every row is a real control.
    private var setupCard: some View {
        Button { controller.showOnboarding = true } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(CodaStyle.caution).frame(width: 6, height: 6)
                    Text("Finish setup").font(.system(size: 12, weight: .medium)).foregroundStyle(CodaStyle.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(CodaStyle.muted)
                }
                Text(controller.readiness(for: model).nextAction).font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(model.settingsChangesLocked)
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
        Button { model.closeSettings(); controller.workspaceSection = section } label: {
            navLabel(title, icon: icon, selected: !model.showSettings && controller.workspaceSection == section)
        }
            .buttonStyle(CodaNavRowStyle(selected: !model.showSettings && controller.workspaceSection == section))
            .accessibilityIdentifier("coda.nav.\(section.lowercased())")
            .accessibilityLabel(title)
            .accessibilityHint(hint)
            .accessibilityAddTraits(!model.showSettings && controller.workspaceSection == section ? .isSelected : [])
    }
    private func navGroup(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(CodaStyle.faint)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
    private func navLabel(_ title: String, icon: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12.5)).frame(width: 16)
                .foregroundStyle(selected ? CodaStyle.ink : CodaStyle.muted)
            Text(title).font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? CodaStyle.ink : CodaStyle.ink.opacity(0.78))
            Spacer(minLength: 4)
            if title == "Dictionary", !controller.dictionary.possible.isEmpty {
                CodaCountBadge(count: controller.dictionary.possible.count, tint: CodaStyle.mint)
                    .accessibilityLabel("\(controller.dictionary.possible.count) possible custom words")
            }
        }
        .padding(.horizontal, 10).frame(height: CodaStyle.rowHeight).contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: 24) {
                CodaPageHeader(icon: historyOnly ? "clock" : "waveform", title: historyOnly ? "History" : "Dictation", subtitle: "") {
                    HStack(spacing: 10) {
                        CodaSearchField(prompt: "Search", text: $query, width: 200)
                        if !historyOnly && !controller.readiness(for: model).canDictate {
                            Button("Set up") { controller.showOnboarding = true }.buttonStyle(CodaPrimaryButtonStyle())
                        }
                    }
                }
                if !historyOnly { ShortcutHint(controller: controller, ready: controller.readiness(for: model).canDictate) }
                if let warning = controller.historyWarning { CodaNotice(kind: .caution, text: warning) }
                if records.isEmpty {
                    if !query.isEmpty {
                        CodaEmptyState(icon: "magnifyingglass", title: "No matches", message: "Try another word or app name.")
                    } else if historyOnly {
                        CodaEmptyState(icon: "clock", title: "Nothing yet", message: "Dictations you make will appear here.")
                    }
                } else {
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            CodaEyebrow(text: dayLabel(day)).padding(.leading, 2)
                            VStack(spacing: 0) {
                                let group = records.filter { Calendar.current.isDate($0.created, inSameDayAs: day) }
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, record in
                                    if index > 0 { Rectangle().fill(CodaStyle.hairline).frame(height: 1).padding(.leading, 56) }
                                    RecordCard(record: record, controller: controller)
                                }
                            }
                            .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
                            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
                        }
                    }
                }
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
    @LocalState private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AppIcon(name: record.target, size: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.finalText.isEmpty ? record.detail : record.finalText)
                        .font(CodaStyle.bodyFont).lineSpacing(3).lineLimit(expanded ? nil : 3)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        Text(record.target).lineLimit(1)
                        Text("·")
                        Text(record.created.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                        if record.correctedText != nil {
                            Image(systemName: "pencil").font(.system(size: 9))
                                .accessibilityLabel("You corrected this dictation; the inserted text is in the details")
                        }
                        if cleanedOriginal != nil {
                            Image(systemName: "sparkles").font(.system(size: 9))
                                .accessibilityLabel("Automatic cleanup was applied; the original is in the details")
                        }
                    }.font(CodaStyle.captionFont).foregroundStyle(CodaStyle.faint)
                }
                HStack(spacing: 0) {
                    Button { controller.copyRecord(record) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(CodaIconButtonStyle(size: 26)).help("Copy text").accessibilityLabel("Copy this dictation")
                    // One control owns the disclosure, so the row cannot disagree with itself.
                    Button { expanded.toggle() } label: {
                        Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .buttonStyle(CodaIconButtonStyle(size: 26))
                    .help(expanded ? "Hide dictation details" : "Show dictation details")
                    .accessibilityLabel(expanded ? "Hide dictation details" : "Show dictation details")
                }.opacity(hovering || expanded ? 1 : 0)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(record.detail).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if record.correctedText != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            CodaEyebrow(text: "Coda inserted")
                            Text(record.text).font(.system(size: 13)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
                    }
                    if let original = cleanedOriginal {
                        VStack(alignment: .leading, spacing: 8) {
                            CodaEyebrow(text: "Before cleanup")
                            Text(original).font(.system(size: 13)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
                    }
                    HStack(spacing: 8) {
                        if cleanedOriginal != nil {
                            Button("Copy original") { controller.copyOriginal(record) }.buttonStyle(CodaSecondaryButtonStyle())
                        }
                        Button("Insert into another app…") { controller.armInsertion(record) }.buttonStyle(CodaSecondaryButtonStyle())
                        if !record.text.isEmpty {
                            Button(record.correctedText == nil ? "Mark wrong…" : "Edit correction…") { controller.correct(record) }
                                .buttonStyle(CodaSecondaryButtonStyle()).disabled(controller.lifecycle.busy)
                                .help("Type what you meant. The inserted text is kept.")
                        }
                    }
                }
                .padding(.leading, 40)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(CodaStyle.motion(reduceMotion, duration: 0.15), value: expanded)
        .animation(CodaStyle.motion(reduceMotion, duration: 0.1), value: hovering)
    }
}

/// The destination app's real icon when it can be found; a lettered tile otherwise.
struct AppIcon: View {
    let name: String
    var size: CGFloat = 28
    private static var cache: [String: NSImage?] = [:]
    @MainActor private static func lookup(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                     "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        let path = roots.map { $0 + "/" + name + ".app" }.first { FileManager.default.fileExists(atPath: $0) }
        let image = path.map { NSWorkspace.shared.icon(forFile: $0) }
        cache[name] = image
        return image
    }
    var body: some View {
        Group {
            if let image = Self.lookup(name) {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
            } else {
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(CodaStyle.muted)
                    .frame(width: size, height: size)
                    .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: size * 0.26))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(CodaStyle.hairline))
            }
        }.accessibilityHidden(true)
    }
}

/// The shortcut drawn as keys: the one thing a person needs to know to dictate.
struct ShortcutHint: View {
    @Bindable var controller: DictationController
    let ready: Bool
    private var keys: [String] {
        let label = controller.shortcutLabel
        if label == "Choose a shortcut" { return [] }
        let symbols = label.filter { "⌃⌥⇧⌘".contains($0) }.map(String.init)
        let rest = label.filter { !"⌃⌥⇧⌘".contains($0) }.trimmingCharacters(in: .whitespaces)
        if symbols.isEmpty { return label.components(separatedBy: " + ").filter { !$0.isEmpty } }
        return symbols + (rest.isEmpty ? [] : [rest])
    }
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                if keys.isEmpty {
                    BigKey(label: "?")
                } else {
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, key in BigKey(label: key) }
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(ready ? (controller.mode == .hold ? "Hold to talk" : "Press to start, press to stop") : "Set up a shortcut to dictate")
                    .font(.system(size: 14, weight: .semibold))
                Text(ready ? "Works in any text field" : "Takes about two minutes")
                    .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
            }
            Spacer(minLength: 0)
            WaveGlyph().frame(width: 96, height: 36).accessibilityHidden(true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
        .accessibilityElement(children: .combine)
    }
}

struct BigKey: View {
    let label: String
    var body: some View {
        Text(label).font(.system(size: label.count > 2 ? 12 : 17, weight: .medium))
            .foregroundStyle(CodaStyle.ink)
            .padding(.horizontal, label.count > 2 ? 10 : 0)
            .frame(minWidth: 40, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 9).fill(CodaStyle.sheet)
            )
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(CodaStyle.strongEdge))
            .shadow(color: .black.opacity(0.10), radius: 0, y: 2)
    }
}

/// Static, symmetrical bars. Decorative only; it never implies capture.
struct WaveGlyph: View {
    private let heights: [CGFloat] = [0.25, 0.45, 0.7, 0.4, 0.95, 0.6, 0.8, 0.35, 0.55, 0.3, 0.2]
    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(heights.enumerated()), id: \.offset) { i, h in
                    Capsule().fill(CodaStyle.mint.opacity(0.25 + 0.6 * h))
                        .frame(width: 3, height: max(4, proxy.size.height * h))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

private struct MetricTile: View {
    let value: String
    let label: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(CodaStyle.muted).accessibilityHidden(true)
            Text(value).font(.system(size: 24, weight: .semibold)).tracking(-0.5).monospacedDigit()
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
