// Minimal CLI mic recorder: records to the given path until SIGTERM/SIGINT.
// Emits the current input level (RMS, dBFS) per audio buffer on stdout for the
// waveform UI — computed from the raw samples, so it has no meter lag.
// Uses AVCaptureSession (not AVAudioEngine) because its device selection is a
// supported API: AVAudioEngine's inputNode is hard-wired to the system default
// and reverts pinned devices on config changes (e.g. AirPods auto-switching).
// Compiled once via: swiftc -O recorder.swift -o recorder
import AVFoundation
import CoreAudio
import Foundation

func allMics() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                     mediaType: .audio, position: .unspecified).devices
}

let args = CommandLine.arguments
if args.count > 1, args[1] == "--list" {
    for d in allMics() { print(d.localizedName) }
    exit(0)
}
guard args.count > 1 else {
    FileHandle.standardError.write("usage: recorder <output.m4a> [mic-name] | --list\n".data(using: .utf8)!)
    exit(1)
}
let url = URL(fileURLWithPath: args[1])
let preferredMic = args.count > 2 ? args[2] : nil

func warn(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}

// Device selection: prefer the configured mic if present; otherwise the system
// default. If that is unusable (e.g. AirPods busy on another device), fall back
// to the built-in mic.
let mics = allMics()
var device: AVCaptureDevice?
if let wanted = preferredMic, !wanted.isEmpty {
    device = mics.first { $0.localizedName.localizedCaseInsensitiveContains(wanted) }
    if device == nil { warn("mic \"\(wanted)\" not found, using default input") }
}
if device == nil { device = AVCaptureDevice.default(for: .audio) }

func makeInput(_ d: AVCaptureDevice?) -> AVCaptureDeviceInput? {
    guard let d, !d.isSuspended else { return nil }
    return try? AVCaptureDeviceInput(device: d)
}

var input = makeInput(device)
if input == nil {
    if let builtIn = mics.first(where: { $0.transportType == Int32(kAudioDeviceTransportTypeBuiltIn) }) {
        warn("input \"\(device?.localizedName ?? "?")\" unusable, falling back to built-in mic")
        device = builtIn
        input = makeInput(builtIn)
    }
}
guard let input, let device else {
    warn("no usable input device (mic permission?)")
    exit(1)
}

// capture pipeline resamples to 16 kHz mono — plenty for speech, ~10x smaller files
let settings: [String: Any] = [
    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
    AVSampleRateKey: 16_000,
    AVNumberOfChannelsKey: 1,
    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
]
var file: AVAudioFile?
do {
    file = try AVAudioFile(forWriting: url, settings: settings,
                           commonFormat: .pcmFormatFloat32, interleaved: true)
} catch {
    warn("failed to open output file: \(error)")
    exit(1)
}

let queue = DispatchQueue(label: "recorder.audio")

final class Writer: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    // capture buffers arrive ~75x/s — too fast for the waveform UI, so pool the
    // RMS across buffers and emit ~23 levels/s like the old AVAudioEngine tap
    private let framesPerLevel = 16_000 / 23
    private var pooledSquares: Float = 0
    private var pooledFrames = 0

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let desc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let fmt = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return }
        buf.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames),
            into: buf.mutableAudioBufferList) == noErr else { return }
        do {
            try file?.write(from: buf)
        } catch {
            warn("write failed: \(error)")
            exit(1)
        }
        guard let samples = buf.floatChannelData?[0] else { return }
        let n = Int(frames)
        for i in 0..<n { pooledSquares += samples[i] * samples[i] }
        pooledFrames += n
        guard pooledFrames >= framesPerLevel else { return }
        let db = 20 * log10(max(sqrt(pooledSquares / Float(pooledFrames)), 1e-7))
        FileHandle.standardOutput.write(String(format: "%.1f\n", db).data(using: .utf8)!)
        pooledSquares = 0
        pooledFrames = 0
    }
}
let writer = Writer()

let session = AVCaptureSession()
session.beginConfiguration()
guard session.canAddInput(input) else {
    warn("cannot add input \(device.localizedName)")
    exit(1)
}
session.addInput(input)
let dataOut = AVCaptureAudioDataOutput()
dataOut.audioSettings = [
    AVFormatIDKey: Int(kAudioFormatLinearPCM),
    AVSampleRateKey: 16_000,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 32,
    AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsNonInterleaved: false,
]
dataOut.setSampleBufferDelegate(writer, queue: queue)
guard session.canAddOutput(dataOut) else {
    warn("cannot add audio output")
    exit(1)
}
session.addOutput(dataOut)
session.commitConfiguration()
session.startRunning()
warn("recording from: \(device.localizedName)")

func stopSource(_ sig: Int32) -> DispatchSourceSignal {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        session.stopRunning()
        queue.sync {} // drain in-flight writes before closing
        file = nil // closes and finalizes the m4a
        exit(0)
    }
    src.resume()
    return src
}
let sources = [stopSource(SIGTERM), stopSource(SIGINT)]
_ = sources

RunLoop.main.run()
