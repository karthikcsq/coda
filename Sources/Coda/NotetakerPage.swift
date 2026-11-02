import SwiftUI
import CodaCore

struct NotetakerPage: View {
    @Bindable var model: AppModel
    @Bindable var controller: DictationController
    var operationInProgress: Bool { model.meetingOperationInProgress }
    var body: some View {
        if model.showingMeetingDetail || operationInProgress || model.showRecordConsent {
            VStack(spacing: 0) {
                HStack { Button { model.showMeetingLibrary() } label: { Label("All meetings", systemImage: "chevron.left") }.buttonStyle(.plain).disabled(operationInProgress).accessibilityIdentifier("coda.meetings.back"); Spacer() }.font(.system(size: 12)).padding(.horizontal, 28).padding(.vertical, 12)
                ContentView(model: model, dictation: controller, showsMeetingSidebar: false)
            }
        } else {
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        HStack {
                            Text("Meetings").font(.system(size: 24, weight: .semibold))
                            Spacer()
                            Button { model.openSettings() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Notetaker settings")
                            Button("New recording", systemImage: "record.circle") { model.requestMeetingRecording() }.disabled(model.isOccupied)
                        }
                        HStack(spacing: 14) {
                            Image(systemName: "waveform.circle").font(.system(size: 30, weight: .light))
                            VStack(alignment: .leading, spacing: 6) { Text("Be present. Keep the important parts.").font(.system(size: 14, weight: .medium)); Text("Record a meeting or bring your own audio. Transcription stays local.").font(.system(size: 13)).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Import audio") { model.importAudio() }.disabled(model.isOccupied)
                        }.padding(18).background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1)))
                        HStack { Text("Saved meetings").font(.system(size: 14, weight: .medium)); Spacer(); Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search meetings", text: $model.search).textFieldStyle(.plain).frame(maxWidth: 160) }
                        Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1).padding(.top, -16)
                        if model.filteredMeetings.isEmpty {
                            VStack(spacing: 12) { Image(systemName: "doc.text").font(.system(size: 32, weight: .light)); Text("Your notes start here.").font(.system(size: 20, design: .serif)); Text("Import audio or start a meeting when you’re ready.").font(.system(size: 13)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 60)
                        }
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(model.filteredMeetings) { meeting in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(meeting.created.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.6).foregroundStyle(.secondary)
                                    Button { model.openMeeting(meeting.id) } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "doc.text").font(.system(size: 17)).frame(width: 36, height: 36).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(meeting.title).font(.system(size: 14)).lineLimit(2)
                                                Text(meeting.created.formatted(date: .omitted, time: .shortened)).font(.system(size: 12)).foregroundStyle(.secondary)
                                                Text(meeting.segments.isEmpty ? "Audio saved · ready to transcribe" : "Open transcript\(meeting.summary == nil ? "" : " and summary")").font(.system(size: 11)).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.secondary)
                                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).background(model.selection == meeting.id ? Color.white.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(.plain).help("Open this meeting").accessibilityIdentifier("coda.meetings.open.\(meeting.id.uuidString)")
                                }
                            }
                        }
                    }.padding(38)
                }.frame(maxWidth: .infinity)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                VStack(alignment: .leading, spacing: 20) {
                    if let meeting = model.selected {
                        Text(meeting.title).font(.system(size: 17, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        Text(meeting.created.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13)).foregroundStyle(.secondary)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        Text("SPEAKERS").font(.system(size: 11, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                        let speakers = Set(meeting.segments.flatMap(\.speakers)).sorted()
                        if speakers.isEmpty { Text("Available after transcription").font(.system(size: 12)).foregroundStyle(.secondary) }
                        ForEach(speakers, id: \.self) { speaker in
                            HStack(spacing: 10) { Text(String(meeting.speakerLabel([speaker]).prefix(1))).font(.system(size: 14, design: .serif)).frame(width: 28, height: 28).background(Color.white.opacity(0.1), in: Circle()); Text(meeting.speakerLabel([speaker])).font(.system(size: 13)) }
                        }
                        Button("Open meeting", systemImage: "doc.text") { model.openMeeting(meeting.id) }.buttonStyle(.borderedProminent).tint(Color(white: 0.25))
                        Text(meeting.summary == nil ? "Transcript and summary are available inside the note." : "Includes transcript, decisions, and action items.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else { Text("Select a note").font(.system(size: 17, weight: .medium)); Text("Meeting details and speakers appear here.").font(.system(size: 13)).foregroundStyle(.secondary) }
                    Spacer()
                    Label("Saved on this Mac", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(24).frame(width: 260).frame(maxHeight: .infinity, alignment: .top).background(Color(white: 0.13))
            }
        }
    }
}
