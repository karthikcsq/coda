import Foundation
import Voz

@main struct CodaVozTool {
    struct Clip: Decodable { let id: String; let audio: String }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { throw NSError(domain: "CodaVozTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected model directory, clip manifest, output JSON."]) }
        let model = try Voz(modelDirectory: URL(fileURLWithPath: args[1]))
        let clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        var results: [String: String] = [:]
        for clip in clips {
            try Task.checkCancellation()
            results[clip.id] = try await model.transcribe(URL(fileURLWithPath: clip.audio)).text
        }
        let output = URL(fileURLWithPath: args[3])
        try JSONEncoder().encode(results).write(to: output, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
    }
}
