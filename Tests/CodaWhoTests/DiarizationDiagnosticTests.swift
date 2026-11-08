import Foundation
import Testing
@testable import CodaWho

/// Local-only diagnosis of one recording. Prints lane and voice statistics, never audio or words.
///   CODA_DIAGNOSE_AUDIO=/path/to/meeting.m4a CODA_DIAGNOSE_SPEAKERS=3 ./scripts/test.sh --filter diagnoseRecording
@Test(.enabled(if: ProcessInfo.processInfo.environment["CODA_DIAGNOSE_AUDIO"] != nil))
func diagnoseRecording() async throws {
    let env = ProcessInfo.processInfo.environment
    let path = env["CODA_DIAGNOSE_AUDIO"]!
    let count = env["CODA_DIAGNOSE_SPEAKERS"].flatMap(Int.init)
    let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Coda/Models").path
    let who = Who(directory: nil, cacheRoot: cache)
    let model = try await who.loadedModel()
    nonisolated(unsafe) var report = ""
    model.inspect = { lanes, voiced, voices, labels in
        for (g, lane) in lanes.enumerated() {
            let speech = lane.turns.reduce(0) { $0 + $1.end - $1.start }
            let solo = lane.solo.reduce(0, +) / 100
            let v = voiced.firstIndex(of: g)
            report += String(format: "lane %2d piece %d q%02d speech %6.1fs solo %6.1fs voiced %@ -> speaker %d\n",
                             g, lane.piece, lane.query, speech, solo, v.map { "v\($0)" } ?? "--", labels[g])
        }
        report += "cosine similarity between voiced lanes:\n      " + voices.indices.map { String(format: "  v%-3d", $0) }.joined() + "\n"
        for i in voices.indices {
            report += String(format: "v%-3d  ", i) + voices.indices.map { String(format: " %5.2f", Linker.dot(voices[i], voices[$0])) }.joined() + "\n"
        }
    }
    let result = try await who.diarize(path: path, speakerCount: count)
    var total: [Int: Double] = [:]
    for turn in result.turns { total[turn.speaker, default: 0] += turn.duration }
    report += "result: \(result.speakerCount) speakers, seconds per speaker \(total.sorted { $0.key < $1.key }.map { "\($0.key): \(Int($0.value))" })\n"
    print(report)
}
