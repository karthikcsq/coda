import SwiftUI
import AVFoundation
import CodaCore

private typealias AudioViewState<Value> = SwiftUI.State<Value>

struct PersonalAudioView: View {
    @Bindable var tuning: PersonalAudioTuning
    var preview = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Personal voice model").font(.title2)
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("Fine-tune Voz’s decoder output layer on your recordings locally. Meetings keep using generic Voz. Personal voice dictation skips Smart cleanup until that combination is validated.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Listen, then type exactly what you said, including repetitions. Save a verbatim transcript only after checking the audio. Polished text is shown for reference and is never automatically used for acoustic training.")
                .font(.callout)
            HStack {
                Button("Prepare audio training") { tuning.start(prepare: true) }
                    .disabled(preview || tuning.busy || tuning.running || tuning.prepared)
                Button("Fine-tune my voice") { tuning.start(prepare: false) }
                    .disabled(preview || tuning.busy || tuning.running || !tuning.prepared || tuning.reviewedCount < 15)
                if tuning.running { Button("Cancel") { tuning.cancel() } }
                Button("Use generic Voz") { tuning.reset() }
                    .disabled(preview || tuning.busy || tuning.running || !tuning.installed)
            }
            Toggle("Use personal voice model for dictation", isOn: $tuning.enabled)
                .toggleStyle(.switch).tint(CodaStyle.mint)
                .disabled(preview || tuning.busy || tuning.running || !tuning.installed)
            Text("Acceptance requires better held-out word accuracy than generic Voz and your previous personal Voz model. The encoder stays frozen.").font(.caption).foregroundStyle(.secondary)
            Text(tuning.message).font(.callout).foregroundStyle(.secondary)
            Text("\(tuning.reviewedCount) reviewed / \(tuning.pairs.count) saved. Training requires at least 15 distinct clips, each up to 15 seconds. Preparation installs Python packages and copies the generic Voz model; recordings stay on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if tuning.pairs.isEmpty {
                ContentUnavailableView("No recordings yet", systemImage: "waveform", description: Text("Enable Learn from my edits, then dictate to collect recordings."))
            } else {
                List(tuning.pairs, id: \.id) { pair in
                    AudioPairReview(pair: pair, tuning: tuning, disabled: preview || tuning.busy || tuning.running)
                }
            }
        }
        .buttonStyle(CodaSecondaryButtonStyle())
        .foregroundStyle(CodaStyle.ink).background(CodaStyle.canvas)
        .padding(24).background(CodaStyle.canvas).frame(minWidth: 680, idealWidth: 800, minHeight: 600)
        .onAppear { tuning.refresh() }
    }
}

private struct AudioPairReview: View {
    let pair: DictationTrainingPair
    @Bindable var tuning: PersonalAudioTuning
    let disabled: Bool
    @AudioViewState private var expanded = true
    @AudioViewState private var transcript = ""
    @AudioViewState private var player: AVAudioPlayer?
    @AudioViewState private var playbackError = ""
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Play recording") {
                        do {
                            guard let root = tuning.store?.root else { return }
                            player?.stop()
                            player = try AVAudioPlayer(contentsOf: root.appendingPathComponent(pair.id.uuidString + ".m4a"))
                            guard player?.play() == true else { playbackError = "Recording could not play."; return }
                            playbackError = ""
                        } catch { playbackError = "Recording could not play." }
                    }
                    Button("Stop") { player?.stop() }
                    Spacer()
                    Button("Delete recording and pair", role: .destructive) { player?.stop(); tuning.remove(pair.id) }
                }
                if !playbackError.isEmpty { Text(playbackError).foregroundStyle(.red) }
                Text("Raw recognition: \(pair.rawText)").textSelection(.enabled)
                Text("Final observed text: \(pair.finalText)").textSelection(.enabled)
                TextField("Verbatim transcript from listening", text: $transcript, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...8)
                HStack {
                    Button("Save reviewed transcript") { tuning.review(pair.id, transcript: transcript) }.disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Exclude from training") { tuning.review(pair.id, transcript: nil) }
                }
            }.padding(.vertical, 8).disabled(disabled)
        } label: {
            HStack {
                Text(pair.created.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text(pair.reviewedTranscript == nil ? "Needs review" : "Reviewed").foregroundStyle(.secondary)
            }
        }
        .onAppear { transcript = pair.reviewedTranscript ?? "" }
        .onDisappear { player?.stop() }
    }
}
