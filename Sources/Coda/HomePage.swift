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
    private var modelReady: Bool { model.modelConsent && model.dictationModelReady }
    private var shortcutReady: Bool { readiness.shortcutAssigned && (!readiness.modifierShortcut || readiness.accessibilityAllowed) }
    private var stepsDone: Int { [modelReady, readiness.microphoneAllowed, shortcutReady].filter { $0 }.count }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                if !readiness.canDictate { setupChecklist }
                else if !controller.accessibility.trusted { insertionNotice }
                actions
                recentWork
                HStack(spacing: 7) {
                    Image(systemName: "lock").font(.system(size: 10))
                    Text("Speech recognition runs on your Mac. Summaries and chat use hosted AI only when you choose. The speech SDK sends licensing metadata.")
                        .fixedSize(horizontal: false, vertical: true)
                }.font(CodaStyle.captionFont).foregroundStyle(CodaStyle.faint)
            }.codaPageInsets()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.refreshAccessibility(); refreshID += 1
        }
    }
    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting).font(.system(size: 26, weight: .semibold)).tracking(-0.6)
                if readiness.canDictate {
                    HStack(spacing: 6) {
                        Text("Press").foregroundStyle(CodaStyle.muted)
                        CodaKeycap(controller.shortcutLabel)
                        Text("in any text field to dictate.").foregroundStyle(CodaStyle.muted)
                    }.font(CodaStyle.bodyFont)
                } else {
                    Text("Dictation and meeting notes that stay on your Mac.")
                        .font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }
    private var setupChecklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Finish setting up").font(.system(size: 14, weight: .semibold))
                    Text("About two minutes. Nothing records until you press your shortcut.")
                        .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                }
                Spacer(minLength: 12)
                Text("\(stepsDone) of 3").font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).monospacedDigit()
                Button { controller.showOnboarding = true } label: {
                    HStack(spacing: 6) { Text(stepsDone == 0 ? "Get started" : "Continue"); Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)) }
                }.buttonStyle(CodaPrimaryButtonStyle()).disabled(locked)
            }.padding(18)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(CodaStyle.hairline)
                    Rectangle().fill(CodaStyle.mint).frame(width: proxy.size.width * CGFloat(stepsDone) / 3)
                }
            }.frame(height: 1).accessibilityHidden(true)
            checklistRow("Speech model", detail: "Download and prepare local recognition", done: modelReady)
            Divider().opacity(0.5)
            checklistRow("Microphone", detail: "Allow Coda to hear you while you hold the shortcut", done: readiness.microphoneAllowed)
            Divider().opacity(0.5)
            checklistRow("Shortcut", detail: "Choose the keys that start dictation", done: shortcutReady)
        }
        .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
        .clipShape(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
    }
    private func checklistRow(_ title: String, detail: String, done: Bool) -> some View {
        Button { controller.showOnboarding = true } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14)).foregroundStyle(done ? CodaStyle.mint : CodaStyle.faint)
                Text(title).font(CodaStyle.rowTitleFont).foregroundStyle(done ? CodaStyle.muted : CodaStyle.ink)
                    .strikethrough(done, color: CodaStyle.faint)
                Text(detail).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.faint).lineLimit(1)
                Spacer(minLength: 8)
                if !done { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(CodaStyle.faint) }
            }.padding(.horizontal, 18).frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(CodaTableRowStyle()).disabled(locked)
        .accessibilityLabel(title + (done ? ", ready" : ", needs setup"))
    }
    private var insertionNotice: some View {
        HStack(spacing: 12) {
            CodaNotice(kind: .caution, text: "Coda can't paste into other apps yet. Results are still saved and copyable.")
            Button("Enable insertion") { controller.showOnboarding = true }.buttonStyle(CodaSecondaryButtonStyle()).disabled(locked)
        }
    }
    private var actions: some View {
        HStack(spacing: 12) {
            action(icon: "waveform", title: readiness.canDictate ? "Dictate" : "Set up dictation",
                   detail: "Speak into any app") {
                if readiness.canDictate { model.closeSettings(); controller.workspaceSection = "Dictation" }
                else { controller.showOnboarding = true }
            }
            action(icon: "record.circle", title: "New meeting", detail: "Record, transcribe, summarize") {
                model.closeSettings(); controller.workspaceSection = "Meetings"; model.requestMeetingRecording()
            }
            action(icon: "text.badge.star", title: "Writing style", detail: "Per-app tone and snippets") {
                model.closeSettings(); controller.workspaceSection = "Personalize"
            }
        }
    }
    private func action(icon: String, title: String, detail: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(CodaStyle.ink)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(CodaStyle.hairline))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(CodaStyle.rowTitleFont).foregroundStyle(CodaStyle.ink)
                    Text(detail).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).lineLimit(1)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
            .contentShape(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
        }
        .buttonStyle(CodaListRowStyle(selected: false)).disabled(locked)
    }
    private var recentWork: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(CodaStyle.sectionFont)
                Spacer()
                Button("View all") { model.closeSettings(); controller.workspaceSection = "History" }.buttonStyle(CodaQuietButtonStyle())
            }
            let record = controller.records.first(where: { !$0.text.isEmpty })
            let meeting = model.meetings.first
            if record == nil && meeting == nil {
                CodaEmptyState(icon: "text.bubble", title: "Nothing yet",
                               message: "Your dictations and meetings will show up here.")
            } else {
                VStack(spacing: 0) {
                    if let record {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform").font(.system(size: 12)).foregroundStyle(CodaStyle.muted).frame(width: 16)
                            Text(record.text).font(CodaStyle.bodyFont).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 12)
                            Text(record.target).font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted).lineLimit(1)
                            Text(record.created.formatted(.relative(presentation: .named))).font(CodaStyle.secondaryFont)
                                .foregroundStyle(CodaStyle.faint).lineLimit(1).frame(width: 84, alignment: .trailing)
                            Button { controller.copyRecord(record) } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(CodaIconButtonStyle(size: 24)).help("Copy dictation").accessibilityLabel("Copy most recent dictation")
                        }.padding(.horizontal, 14).frame(height: 44)
                    }
                    if record != nil && meeting != nil { Divider().opacity(0.5) }
                    if let meeting {
                        Button {
                            model.closeSettings(); controller.workspaceSection = "Meetings"; model.openMeeting(meeting.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.2").font(.system(size: 11)).foregroundStyle(CodaStyle.muted).frame(width: 16)
                                Text(meeting.title).font(CodaStyle.bodyFont).lineLimit(1)
                                Spacer(minLength: 12)
                                Text("Meeting").font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
                                Text(meeting.created.formatted(.relative(presentation: .named))).font(CodaStyle.secondaryFont)
                                    .foregroundStyle(CodaStyle.faint).lineLimit(1).frame(width: 84, alignment: .trailing)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(CodaStyle.faint).frame(width: 24)
                            }.padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
                        }.buttonStyle(CodaTableRowStyle())
                    }
                }
                .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
                .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge).strokeBorder(CodaStyle.hairline))
                .clipShape(RoundedRectangle(cornerRadius: CodaStyle.radiusLarge))
            }
        }
    }
}
