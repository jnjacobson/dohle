// Minimal CLI mic recorder: records to the given path until SIGTERM/SIGINT.
// Emits the current input level (RMS, dBFS) per audio buffer (~23x/s) on stdout
// for the waveform UI — computed from the raw samples, so it has no meter lag.
// Compiled once via: swiftc -O recorder.swift -o recorder
import AVFoundation
import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: recorder <output.m4a>\n".data(using: .utf8)!)
    exit(1)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])

let engine = AVAudioEngine()
let input = engine.inputNode
let inputFormat = input.outputFormat(forBus: 0)

// downsample to 16 kHz mono before encoding — plenty for speech, ~10x smaller files
let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                              channels: 1, interleaved: false)!
guard let converter = AVAudioConverter(from: inputFormat, to: outFormat) else {
    FileHandle.standardError.write("failed to create converter\n".data(using: .utf8)!)
    exit(1)
}

let settings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
    AVSampleRateKey: 16_000,
    AVNumberOfChannelsKey: 1,
    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
]

var file: AVAudioFile?
do {
    file = try AVAudioFile(forWriting: url, settings: settings,
                           commonFormat: .pcmFormatFloat32, interleaved: false)
} catch {
    FileHandle.standardError.write("failed to open output file: \(error)\n".data(using: .utf8)!)
    exit(1)
}

input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
    let ratio = outFormat.sampleRate / inputFormat.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
    guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
    var consumed = false
    var convError: NSError?
    converter.convert(to: out, error: &convError) { _, outStatus in
        if consumed {
            outStatus.pointee = .noDataNow
            return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return buffer
    }
    do {
        if convError == nil, out.frameLength > 0 {
            try file?.write(from: out)
        }
    } catch {
        FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
    guard let samples = buffer.floatChannelData?[0] else { return }
    let n = Int(buffer.frameLength)
    guard n > 0 else { return }
    var sum: Float = 0
    for i in 0..<n { sum += samples[i] * samples[i] }
    let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-7))
    FileHandle.standardOutput.write(String(format: "%.1f\n", db).data(using: .utf8)!)
}

do {
    try engine.start()
} catch {
    FileHandle.standardError.write("failed to start engine (mic permission?): \(error)\n".data(using: .utf8)!)
    exit(1)
}

func stopSource(_ sig: Int32) -> DispatchSourceSignal {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        input.removeTap(onBus: 0)
        engine.stop()
        file = nil // closes and finalizes the m4a
        exit(0)
    }
    src.resume()
    return src
}
let sources = [stopSource(SIGTERM), stopSource(SIGINT)]
_ = sources

RunLoop.main.run()
