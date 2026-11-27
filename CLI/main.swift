// lingo-cli: transcribe audio files with the same models and code as the Lingo app.
// Useful for trying models and for measuring accuracy on your own test set.

import Foundation
import MLX
import MLXAudioCore

let usage = """
    Usage:
      lingo-cli list
      lingo-cli download <model-id>
      lingo-cli delete <model-id>
      lingo-cli transcribe [--model <id>] [--language zh|en|auto] <audio-file>...
      lingo-cli bench [--model <id>] [--language zh|en|auto] --manifest <in.jsonl> --out <out.jsonl>

    bench reads JSON lines with "id" and "wav" (path to an audio file) and writes
    the same lines with "hyp" (the transcript) and "seconds" (processing time) added.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

struct Options {
    var model = ModelCatalog.defaultModel
    var language = TranscriptionLanguage.chinese
    var manifest: String?
    var out: String?
    var positional: [String] = []
}

func parse(_ args: ArraySlice<String>) -> Options {
    var options = Options()
    var it = args.makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--model":
            guard let id = it.next(), let model = ModelCatalog.model(id: id) else {
                fail("Unknown model. Run `lingo-cli list`.")
            }
            options.model = model
        case "--language":
            guard let raw = it.next(), let language = TranscriptionLanguage(rawValue: raw) else {
                fail("--language must be zh, en or auto")
            }
            options.language = language
        case "--manifest":
            options.manifest = it.next()
        case "--out":
            options.out = it.next()
        default:
            options.positional.append(arg)
        }
    }
    return options
}

func loadSamples(_ path: String) throws -> [Float] {
    let (_, audio) = try loadAudioArray(
        from: URL(fileURLWithPath: path), sampleRate: TranscriptionEngine.sampleRate)
    return audio.asArray(Float.self)
}

func prepare(_ options: Options) async throws -> TranscriptionEngine {
    if !ModelFiles.isInstalled(options.model) {
        log("Downloading \(options.model.displayName) (\(options.model.formattedSize))…")
        try await ModelFiles.download(options.model)
    }
    let engine = TranscriptionEngine()
    let start = Date()
    try await engine.load(options.model)
    log(String(format: "Loaded %@ in %.1fs", options.model.displayName, Date().timeIntervalSince(start)))
    return engine
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { fail(usage) }
let options = parse(arguments.dropFirst())

do {
    switch command {
    case "list":
        for model in ModelCatalog.all {
            let installed = ModelFiles.installedBytes(model).map { "installed, \(ByteFormatter.string($0))" }
                ?? "not downloaded"
            let mark = model.id == ModelCatalog.defaultModelID ? " (default)" : ""
            print("\(model.id)\(mark)\n    \(model.displayName) · \(model.formattedSize) · \(installed)")
        }
        print("\nModels are stored in \(ModelFiles.rootDirectory.path)")

    case "download":
        guard let id = options.positional.first, let model = ModelCatalog.model(id: id) else {
            fail("Usage: lingo-cli download <model-id>")
        }
        var lastPrinted = -1
        try await ModelFiles.download(model) { fraction in
            let percent = Int(fraction * 100)
            if percent != lastPrinted {
                lastPrinted = percent
                log("\(percent)%")
            }
        }
        print("Downloaded \(model.displayName) to \(ModelFiles.directory(for: model).path)")

    case "delete":
        guard let id = options.positional.first, let model = ModelCatalog.model(id: id) else {
            fail("Usage: lingo-cli delete <model-id>")
        }
        ModelFiles.removeFiles(for: model)
        print("Deleted \(model.displayName)")

    case "transcribe":
        guard !options.positional.isEmpty else { fail(usage) }
        let engine = try await prepare(options)
        for path in options.positional {
            let samples = try loadSamples(path)
            let start = Date()
            let text = try await engine.transcribe(samples: samples, language: options.language.modelCode)
            let elapsed = Date().timeIntervalSince(start)
            log(String(format: "%@ (%.1fs audio, %.2fs)", path, Double(samples.count) / 16_000, elapsed))
            print(text)
        }

    case "bench":
        guard let manifest = options.manifest, let out = options.out else { fail(usage) }
        let engine = try await prepare(options)
        let lines = try String(contentsOfFile: manifest, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        FileManager.default.createFile(atPath: out, contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: out))
        defer { try? handle.close() }
        for (index, line) in lines.enumerated() {
            guard var row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let wav = row["wav"] as? String else { continue }
            let samples = try loadSamples(wav)
            let start = Date()
            let text = try await engine.transcribe(samples: samples, language: options.language.modelCode)
            row["hyp"] = text
            row["seconds"] = Date().timeIntervalSince(start)
            row["model"] = options.model.id
            row["language_setting"] = options.language.rawValue
            var data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            data.append(0x0A)
            try handle.write(contentsOf: data)
            log("[\(index + 1)/\(lines.count)] \(text)")
        }

    default:
        fail(usage)
    }
} catch {
    fail("Error: \(error.localizedDescription)")
}
