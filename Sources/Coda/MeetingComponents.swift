import SwiftUI
import CodaCore

// Presentation helpers shared by the meeting library and the meeting document.
extension Meeting {
    /// Distinct diarized speakers, in label order.
    var speakerIDs: [Int] { Set(segments.flatMap(\.speakers)).sorted() }
    /// Length of the transcribed audio. Nil until a transcript exists.
    var transcribedDuration: Double? { segments.last?.end }
    func displayName(_ speaker: Int) -> String { speakerNames[String(speaker)] ?? "Speaker \(speaker + 1)" }
    /// A letter for named speakers and a number otherwise, so unnamed avatars stay distinguishable.
    func monogram(_ speaker: Int) -> String {
        guard let name = speakerNames[String(speaker)]?.trimmingCharacters(in: .whitespaces), let first = name.first else {
            return "\(speaker + 1)"
        }
        return String(first).uppercased()
    }
    /// A one-line preview for the library: the first summary note, else the opening words.
    var previewLine: String? { summary?.brief?.text ?? summary?.overview.first?.text ?? segments.first?.text }
}

enum MeetingFormat {
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total) sec" }
        let hours = total / 3600, minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
    static func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

struct CodaSpeakerAvatar: View {
    let monogram: String
    let index: Int
    var size: CGFloat = 24
    var ring: Color? = nil
    var body: some View {
        let tint = CodaStyle.speakerColor(index)
        ZStack {
            // Opaque base first, so overlapping avatars never show through each other.
            Circle().fill(CodaStyle.canvas)
            Circle().fill(tint.opacity(0.18))
            Circle().strokeBorder(tint.opacity(0.32))
            Text(monogram)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .padding(ring == nil ? 0 : 1.5)
        .background(Circle().fill(ring ?? .clear))
        .accessibilityHidden(true)
    }
}

/// Overlapping avatars for a meeting's speakers; the ring matches the surface behind it.
struct CodaAvatarStack: View {
    let meeting: Meeting
    var size: CGFloat = 22
    var ring: Color = CodaStyle.canvas
    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(meeting.speakerIDs, id: \.self) { speaker in
                CodaSpeakerAvatar(monogram: meeting.monogram(speaker), index: speaker, size: size, ring: ring)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meeting.speakerIDs.map(meeting.displayName).joined(separator: ", "))
    }
}

/// Concentric rings around one symbol. The single illustration the notetaker uses.
struct CodaEmblem: View {
    let symbol: String
    var tint: Color = CodaStyle.mint
    var body: some View {
        ZStack {
            Circle().strokeBorder(tint.opacity(0.07)).frame(width: 124, height: 124)
            Circle().strokeBorder(tint.opacity(0.13)).frame(width: 92, height: 92)
            Circle().fill(tint.opacity(0.10)).frame(width: 60, height: 60)
                .overlay(Circle().strokeBorder(tint.opacity(0.22)))
            Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

/// Small rounded tag for row status and action-item metadata.
struct CodaTag: View {
    var icon: String? = nil
    let text: String
    var tint: Color = CodaStyle.muted
    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).frame(height: 21)
        .background(tint.opacity(0.11), in: Capsule())
        .fixedSize()
    }
}

extension View {
    /// Readable document column, aligned with every other workspace page.
    func codaColumn(horizontal: CGFloat = CodaStyle.pageInset) -> some View {
        self.padding(.horizontal, horizontal)
            .frame(maxWidth: CodaStyle.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left-to-right wrapping row for tags and citations.
struct CodaFlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }
    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
