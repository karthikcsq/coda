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
    private var readiness: SetupReadiness { _ = refreshID; return controller.readiness(for: model) }
    private var locked: Bool { model.settingsChangesLocked || controller.lifecycle.busy }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label("YOUR WORKSPACE", systemImage: "waveform.path")
                        .font(.system(size: 11, weight: .medium)).tracking(1.5).foregroundStyle(CodaStyle.muted)
                    Spacer()
                    Button("Setup guide") { controller.showOnboarding = true }
                        .buttonStyle(CodaQuietButtonStyle()).disabled(locked)
                }
                hero
                readinessStrip
                HStack(alignment: .top, spacing: 16) {
                    workflow(icon: "waveform", title: "Dictate anywhere", description: "Speak into your favorite apps. Keep your wording, skip the typing.", action: readiness.canDictate ? "Open dictation" : "Set up dictation") {
                        if readiness.canDictate { model.closeSettings(); controller.workspaceSection = "Dictation" }
                        else { controller.showOnboarding = true }
                    }
                    workflow(icon: "person.2.wave.2", title: "Remember the conversation", description: "Record a meeting. Review who said what, then find the next step.", action: "New meeting") {
                        model.closeSettings(); controller.workspaceSection = "Meetings"; model.requestMeetingRecording()
                    }
                }
                recentWork
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(CodaStyle.mint)
                    Text("Speech recognition runs on your Mac. Meeting summaries and chat use hosted AI when you choose. The speech SDK sends licensing metadata.")
                        .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(36).frame(maxWidth: 1100).frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAccessibility(); refreshID += 1
        }
    }
    private var hero: some View {
        HStack(alignment: .center, spacing: 26) {
            VStack(alignment: .leading, spacing: 16) {
                Text(readiness.canDictate ? "Ready when\nyou are." : "Good work starts\nwith your voice.")
                    .font(.system(size: 38, weight: .medium, design: .rounded)).tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(readiness.canDictate ? "A thought, a message, a conversation.\nCoda helps you carry it forward." : "Your dictation companion and meeting notebook.\nA few simple steps, then you're ready to speak.")
                    .font(.system(size: 14)).foregroundStyle(CodaStyle.ink.opacity(0.72)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { controller.showOnboarding = true } label: {
                        Label(readiness.canDictate ? "Try a dictation" : "Get started", systemImage: readiness.canDictate ? "mic" : "arrow.right")
                    }.buttonStyle(CodaPrimaryButtonStyle()).disabled(locked)
                    if readiness.canDictate {
                        Text(controller.shortcutLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(CodaStyle.mint)
                    } else { Text("Set up at your own pace").font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted) }
                }.padding(.top, 6)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VoiceIllustration().frame(width: 210, height: 200).accessibilityHidden(true)
        }
        .padding(30).frame(maxWidth: .infinity, alignment: .leading)
        .background(CodaStyle.heroGradient, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(CodaStyle.mint.opacity(0.13)))
    }
    private var readinessStrip: some View {
        HStack(spacing: 20) {
            readinessItem("Speech model", ready: model.modelConsent && model.dictationModelReady)
            readinessItem("Microphone", ready: readiness.microphoneAllowed)
            readinessItem("Shortcut", ready: readiness.shortcutAssigned && (!readiness.modifierShortcut || readiness.accessibilityAllowed))
            Spacer(minLength: 0)
            if !readiness.canDictate {
                Button("Continue setup") { controller.showOnboarding = true }
                    .buttonStyle(CodaQuietButtonStyle()).disabled(locked)
            } else if !controller.accessibility.trusted {
                Button("Enable insertion") { controller.showOnboarding = true }.buttonStyle(CodaQuietButtonStyle()).disabled(locked)
            }
        }.padding(.horizontal, 4)
    }
    private func readinessItem(_ title: String, ready: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ready ? CodaStyle.mint : CodaStyle.muted)
            Text(title).foregroundStyle(ready ? CodaStyle.ink : CodaStyle.muted)
        }.font(CodaStyle.secondaryFont).accessibilityLabel(title + (ready ? ", ready" : ", needs setup"))
    }
    private func workflow(icon: String, title: String, description: String, action: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundStyle(CodaStyle.mint)
                .frame(height: 28).accessibilityHidden(true)
            Text(title).font(.system(size: 18, weight: .medium, design: .rounded))
            Text(description).font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.muted)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true).frame(minHeight: 44, alignment: .top)
            Button(action, action: perform).buttonStyle(CodaSecondaryButtonStyle()).disabled(locked)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
    }
    private var recentWork: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Pick up where you left off").font(CodaStyle.sectionFont)
                Spacer()
                Button("All history") { model.closeSettings(); controller.workspaceSection = "History" }.buttonStyle(CodaQuietButtonStyle())
            }
            if let record = controller.records.first(where: { !$0.text.isEmpty }) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "text.bubble").foregroundStyle(CodaStyle.mint).frame(width: 24)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(record.text).font(CodaStyle.bodyFont).lineLimit(2).lineSpacing(3).textSelection(.enabled)
                        Text(record.target + " • " + record.created.formatted(date: .abbreviated, time: .shortened))
                            .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                    }
                    Spacer(minLength: 0)
                    Button { controller.copyRecord(record) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(CodaIconButtonStyle()).help("Copy dictation").accessibilityLabel("Copy most recent dictation")
                }.codaCard(padding: 18)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "text.bubble").foregroundStyle(CodaStyle.muted)
                    Text("Your first dictation will be saved here.").font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.muted)
                    Spacer()
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(CodaStyle.hairline))
            }
            if let meeting = model.meetings.first {
                Button {
                    model.closeSettings(); controller.workspaceSection = "Meetings"; model.openMeeting(meeting.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2").foregroundStyle(CodaStyle.mint).frame(width: 24)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(meeting.title).font(CodaStyle.bodyFont).lineLimit(1)
                            Text(meeting.created.formatted(date: .abbreviated, time: .shortened)).font(CodaStyle.captionFont).foregroundStyle(CodaStyle.muted)
                        }
                        Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(CodaStyle.muted)
                    }.padding(18).contentShape(Rectangle())
                }.buttonStyle(.plain).background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(CodaStyle.hairline))
            }
        }
    }
}

/// A native, decorative voice-to-text illustration. It never implies active capture.
struct VoiceIllustration: View {
    private let heights: [CGFloat] = [13, 25, 17, 40, 65, 35, 78, 52, 31, 59, 28, 42, 18, 30, 12]
    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .center, spacing: 5) {
                ForEach(Array(heights.enumerated()), id: \.offset) { i, height in
                    Capsule().fill(CodaStyle.mint.opacity(i > 3 && i < 11 ? 0.85 : 0.25)).frame(width: 5, height: height)
                }
            }.frame(height: 80)
            VStack(alignment: .leading, spacing: 9) {
                RoundedRectangle(cornerRadius: 3).fill(CodaStyle.mint.opacity(0.38)).frame(width: 130, height: 5)
                RoundedRectangle(cornerRadius: 3).fill(CodaStyle.mint.opacity(0.19)).frame(width: 156, height: 5)
                RoundedRectangle(cornerRadius: 3).fill(CodaStyle.mint.opacity(0.12)).frame(width: 95, height: 5)
            }.padding(18).background(CodaStyle.mint.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }.rotationEffect(.degrees(-5))
    }
}
