import SwiftUI

// Disambiguate the stable property wrapper from the macOS 27 State macro; CLT omits SwiftUIMacros.
private typealias StyleState<Value> = SwiftUI.State<Value>

/// Shared visual tokens for Coda's native surfaces. The dictionary page's charcoal
/// and mint pairing is the anchor; every other surface resolves back to it so the
/// app reads as one piece of software instead of five unrelated screens.
enum CodaStyle {
    // Surfaces.
    static let canvas = BuildIdentity.isDevelopment ? Color(red: 0.14, green: 0.10, blue: 0.21) : Color(red: 0.10, green: 0.10, blue: 0.10)
    static let chrome = BuildIdentity.isDevelopment ? Color(red: 0.20, green: 0.13, blue: 0.29) : Color(white: 0.13)
    static let raised = Color.white.opacity(0.04)
    static let sunken = Color.white.opacity(0.02)
    static let hover = Color.white.opacity(0.055)
    static let selected = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.08)
    static let strongEdge = Color.white.opacity(0.14)

    // Ink.
    static let ink = Color(white: 0.88)
    static let muted = Color.white.opacity(0.57)

    // Accents. `mint` leads; `caution` is the only warning colour.
    static let mint = BuildIdentity.isDevelopment ? Color(red: 0.82, green: 0.68, blue: 1.0) : Color(red: 0.62, green: 0.86, blue: 0.76)
    static let caution = Color(red: 0.96, green: 0.72, blue: 0.42)

    // One radius ramp instead of ten ad-hoc values.
    static let radiusSmall: CGFloat = 8
    static let radius: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusShell: CGFloat = 20

    // Rhythm.
    static let pageInset: CGFloat = 34
    static let blockSpacing: CGFloat = 26
    static let contentWidth: CGFloat = 940
    static let rowHeight: CGFloat = 36

    // Type ramp.
    static let pageTitleFont = Font.system(size: 26, weight: .medium, design: .rounded)
    static let sectionFont = Font.system(size: 15, weight: .semibold)
    static let rowTitleFont = Font.system(size: 13, weight: .medium)
    static let bodyFont = Font.system(size: 14)
    static let secondaryFont = Font.system(size: 12)
    static let captionFont = Font.system(size: 11)

    /// Nil when Reduce Motion is on, so every animated surface can opt out the same way.
    static func motion(_ reduce: Bool, duration: Double = 0.2) -> Animation? {
        reduce ? nil : .easeInOut(duration: duration)
    }

    /// Live-capture red. Reserved for recording state so it never reads as an error.
    static let recording = Color(red: 1.0, green: 0.42, blue: 0.40)

    /// Speaker hues: four muted tones tuned to sit beside mint on charcoal. Index 0 is mint,
    /// so a one-person recording looks exactly like the rest of the app.
    static let speakerPalette: [Color] = [
        mint,
        Color(red: 0.58, green: 0.76, blue: 0.98),
        Color(red: 0.80, green: 0.69, blue: 0.98),
        Color(red: 0.98, green: 0.75, blue: 0.60)
    ]
    static func speakerColor(_ index: Int) -> Color { speakerPalette[abs(index) % speakerPalette.count] }

    static let heroGradient = LinearGradient(
        colors: BuildIdentity.isDevelopment ? [Color(red: 0.29, green: 0.17, blue: 0.40), Color(red: 0.17, green: 0.11, blue: 0.25)] : [Color(red: 0.10, green: 0.17, blue: 0.16), Color(red: 0.12, green: 0.13, blue: 0.13)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension View {
    /// A raised card on the page canvas: one fill, one hairline, one radius.
    func codaCard(padding: CGFloat = 20, radius: CGFloat = CodaStyle.radiusLarge, fill: Color = CodaStyle.raised) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(CodaStyle.hairline))
    }
    /// Page gutters, shared by every workspace page.
    func codaPageInsets() -> some View {
        self.padding(CodaStyle.pageInset)
            .frame(maxWidth: CodaStyle.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    /// A hairline rule that does not need negative padding to sit where it should.
    func codaDivider() -> some View {
        self.overlay(alignment: .bottom) { Rectangle().fill(CodaStyle.hairline).frame(height: 1) }
    }
}

/// Title block shared by Dictionary, Insights, Meetings and Settings.
struct CodaPageHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = CodaStyle.mint
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                titleBlock
                Spacer(minLength: 12)
                trailing().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                trailing()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var titleBlock: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: CodaStyle.radius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                // The title never wraps; the subtitle gets the remaining width.
                Text(title).font(CodaStyle.pageTitleFont).fixedSize(horizontal: true, vertical: false)
                Text(subtitle).font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }.layoutPriority(1)
        }
    }
}

extension CodaPageHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String, tint: Color = CodaStyle.mint) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

/// Small uppercase label above a list or group.
struct CodaEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .medium)).tracking(1)
            .foregroundStyle(CodaStyle.muted)
    }
}

struct CodaCountBadge: View {
    let count: Int
    var tint: Color = CodaStyle.muted
    var body: some View {
        Text("\(count)").font(.system(size: 11, weight: .medium)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// One search control for every list in the app.
struct CodaSearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat? = nil
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 13))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear " + prompt.lowercased())
            }
        }
        .padding(.horizontal, 12).frame(height: 36).frame(width: width)
        .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusSmall).strokeBorder(CodaStyle.hairline))
    }
}

/// Every empty list uses this shape, so "nothing here yet" always looks deliberate.
struct CodaEmptyState<Action: View>: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = CodaStyle.muted
    @ViewBuilder var action: () -> Action
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundStyle(tint)
                .frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(CodaStyle.rowTitleFont)
                Text(message).font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
            Spacer(minLength: 0)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
    }
}

extension CodaEmptyState where Action == EmptyView {
    init(icon: String, title: String, message: String, tint: Color = CodaStyle.muted) {
        self.init(icon: icon, title: title, message: message, tint: tint) { EmptyView() }
    }
}

/// Inline guidance or warning. Replaces loose orange `Label`s and stacked captions.
struct CodaNotice: View {
    enum Kind { case info, caution }
    let kind: Kind
    let text: String
    private var icon: String { kind == .caution ? "exclamationmark.triangle" : "info.circle" }
    private var tint: Color { kind == .caution ? CodaStyle.caution : CodaStyle.mint }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.ink.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
        .accessibilityElement(children: .combine)
    }
}

/// Honest permission/readiness state. Never shows "ready" for something unverified.
struct CodaStatusChip: View {
    enum Readiness { case ready, pending, blocked }
    let readiness: Readiness
    let text: String
    private var tint: Color {
        switch readiness { case .ready: CodaStyle.mint; case .pending: CodaStyle.muted; case .blocked: CodaStyle.caution }
    }
    private var icon: String {
        switch readiness { case .ready: "checkmark.circle.fill"; case .pending: "circle.dashed"; case .blocked: "exclamationmark.circle.fill" }
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11)).accessibilityHidden(true)
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint).padding(.horizontal, 9).padding(.vertical, 4)
        .background(tint.opacity(0.1), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A labelled group of settings or details.
struct CodaSection<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(CodaStyle.mint)
                    .frame(width: 20).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .medium))
                    Text(subtitle).font(CodaStyle.secondaryFont).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rectangle().fill(CodaStyle.hairline).frame(height: 1)
            content()
        }
        .codaCard(padding: 22, fill: CodaStyle.chrome)
    }
}

// MARK: - Control styles

struct CodaPrimaryButtonStyle: ButtonStyle {
    var tint: Color = CodaStyle.mint
    var ink: Color = Color(white: 0.1)
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16).frame(height: 34)
            .background(tint.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct CodaSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(CodaStyle.ink)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 15).frame(height: 34)
            .background(configuration.isPressed ? CodaStyle.selected : CodaStyle.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(CodaStyle.hairline))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct CodaQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(configuration.isPressed ? CodaStyle.ink : CodaStyle.muted)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Square hit target with hover feedback; 30pt everywhere, including the floating HUD.
struct CodaIconButtonStyle: ButtonStyle {
    var size: CGFloat = 30
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, size: size)
    }
    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let size: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @StyleState private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(CodaStyle.ink)
                .frame(width: size, height: size)
                .background(configuration.isPressed ? CodaStyle.selected : hovering && isEnabled ? CodaStyle.hover : .clear,
                            in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                .contentShape(RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}

/// Sidebar navigation row: hover, pressed and selected states that read distinctly.
struct CodaNavRowStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, selected: selected)
    }
    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @StyleState private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private var fill: Color {
            if selected { return CodaStyle.selected }
            if configuration.isPressed { return CodaStyle.hover }
            return hovering ? CodaStyle.raised : .clear
        }
        var body: some View {
            configuration.label
                .background(fill, in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                .contentShape(RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                .onHover { hovering = $0 }
                .animation(CodaStyle.motion(reduceMotion, duration: 0.12), value: hovering)
        }
    }
}

/// Selectable list row (meeting library, history groups).
struct CodaListRowStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, selected: selected)
    }
    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @StyleState private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private var fill: Color {
            if configuration.isPressed { return CodaStyle.selected }
            if selected { return CodaStyle.hover }
            return hovering ? CodaStyle.raised : .clear
        }
        var body: some View {
            configuration.label
                .background(fill, in: RoundedRectangle(cornerRadius: CodaStyle.radius))
                .overlay(RoundedRectangle(cornerRadius: CodaStyle.radius)
                    .strokeBorder(selected ? CodaStyle.strongEdge : .clear))
                .contentShape(RoundedRectangle(cornerRadius: CodaStyle.radius))
                .onHover { hovering = $0 }
                .animation(CodaStyle.motion(reduceMotion, duration: 0.12), value: hovering)
        }
    }
}

/// Flat row inside a shared list surface: hover and press fill edge to edge, no per-row border.
struct CodaTableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }
    struct StyleBody: View {
        let configuration: ButtonStyleConfiguration
        @StyleState private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .background(configuration.isPressed ? CodaStyle.selected : hovering ? CodaStyle.hover : .clear)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(CodaStyle.motion(reduceMotion, duration: 0.12), value: hovering)
        }
    }
}

/// Slim segmented control: one sunken track and a raised thumb that slides between options.
struct CodaSegmented<Value: Hashable>: View {
    struct Option {
        let value: Value
        let label: String
        var icon: String? = nil
    }
    let options: [Option]
    @Binding var selection: Value
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    withAnimation(CodaStyle.motion(reduceMotion, duration: 0.18)) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = option.icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)) }
                        Text(option.label).font(.system(size: 12, weight: selected ? .semibold : .medium)).lineLimit(1)
                    }
                    .foregroundStyle(selected ? CodaStyle.ink : CodaStyle.muted)
                    .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 26)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.11))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.07)))
                                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(CodaStyle.hairline))
        .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Mint switch in Coda's palette instead of the system accent.
struct CodaSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { StyleBody(configuration: configuration) }
    struct StyleBody: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            Button {
                withAnimation(CodaStyle.motion(reduceMotion, duration: 0.15)) { configuration.isOn.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                    ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                        Capsule().fill(configuration.isOn ? CodaStyle.mint : Color.white.opacity(0.14))
                        Circle().fill(Color.white.opacity(configuration.isOn ? 1 : 0.7)).padding(2)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    }
                    .frame(width: 30, height: 18)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
        }
    }
}

/// Keyboard hint shown inside a button, e.g. ↩ or esc.
struct CodaKeycap: View {
    let key: String
    var onAccent = false
    init(_ key: String, onAccent: Bool = false) { self.key = key; self.onAccent = onAccent }
    var body: some View {
        Text(key).font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(onAccent ? Color(white: 0.1).opacity(0.6) : CodaStyle.muted)
            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 17)
            .background(onAccent ? Color.black.opacity(0.1) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityHidden(true)
    }
}
