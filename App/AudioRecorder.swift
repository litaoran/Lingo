import AVFoundation
import Foundation

/// Records from the default input device and converts to 16 kHz mono Float32,
/// the format every supported model expects.
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(TranscriptionEngine.sampleRate),
        channels: 1,
        interleaved: false
    )!

    private let lock = NSLock()
    private var samples: [Float] = []

    /// Called on the audio thread with the RMS level of each buffer.
    var onLevel: ((Float) -> Void)?

    var isRecording: Bool { engine != nil }

    /// Whether the current or last recording used Apple's voice processing.
    private(set) var echoCancellationActive = false
    /// Seconds from `start()` until the first audio buffer arrived.
    private(set) var startupLatency: TimeInterval?
    private var startedAt = Date()

    /// Starts recording. With `echoCancellation`, Apple's voice processing removes
    /// sound the Mac itself is playing (videos, music, calls) from the microphone
    /// signal, so only your voice is transcribed. Falls back to the raw microphone
    /// if voice processing isn't available.
    func start(echoCancellation: Bool) throws {
        guard engine == nil else { return }

        // A fresh engine per recording picks up the current default input device.
        let engine = AVAudioEngine()
        let input = engine.inputNode
        echoCancellationActive = false
        if echoCancellation {
            do {
                try input.setVoiceProcessingEnabled(true)
                // Keep other apps' audio at its normal volume while recording.
                input.voiceProcessingOtherAudioDuckingConfiguration =
                    AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                        enableAdvancedDucking: false, duckingLevel: .min)
                echoCancellationActive = true
            } catch {
                echoCancellationActive = false
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw LingoError.microphoneUnavailable("no input device found")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw LingoError.microphoneUnavailable("unsupported input format \(inputFormat)")
        }
        if inputFormat.channelCount > 1 {
            // Voice processing and multi-channel interfaces put the voice on channel 0.
            converter.channelMap = [0]
        }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        self.converter = converter
        startupLatency = nil
        startedAt = Date()
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.converter = nil
            throw LingoError.microphoneUnavailable(error.localizedDescription)
        }
        self.engine = engine
    }

    /// Stops recording and returns everything captured since `start()`.
    func stop() -> [Float] {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        converter = nil

        lock.lock()
        defer { lock.unlock() }
        let captured = samples
        samples = []
        return captured
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        if startupLatency == nil { startupLatency = Date().timeIntervalSince(startedAt) }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }

        let count = Int(output.frameLength)
        guard count > 0 else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: count)

        var sumOfSquares: Float = 0
        for sample in chunk { sumOfSquares += sample * sample }

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        onLevel?((sumOfSquares / Float(count)).squareRoot())
    }
}
