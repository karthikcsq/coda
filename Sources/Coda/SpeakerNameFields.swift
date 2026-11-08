import SwiftUI

/// Optional names for a fixed speaker count, typed before recording. Applied after
/// transcription in first-to-speak order; any can be renamed later.
struct SpeakerNameFields: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<model.recordingSpeakerCount, id: \.self) { index in
                HStack(spacing: 10) {
                    CodaSpeakerAvatar(monogram: monogram(index), index: index, size: 22)
                    TextField(index == 0 ? "First to speak (optional)" : "Speaker \(index + 1) (optional)", text: binding(index))
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusSmall).strokeBorder(CodaStyle.hairline))
                        .accessibilityLabel("Name for speaker \(index + 1)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coda.recording.speakerNames")
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(get: { model.recordingSpeakerNames.indices.contains(index) ? model.recordingSpeakerNames[index] : "" },
                set: { value in
                    while model.recordingSpeakerNames.count <= index { model.recordingSpeakerNames.append("") }
                    model.recordingSpeakerNames[index] = value
                })
    }

    private func monogram(_ index: Int) -> String {
        let name = model.recordingSpeakerNames.indices.contains(index) ? model.recordingSpeakerNames[index].trimmingCharacters(in: .whitespaces) : ""
        return name.first.map { String($0).uppercased() } ?? "\(index + 1)"
    }
}
