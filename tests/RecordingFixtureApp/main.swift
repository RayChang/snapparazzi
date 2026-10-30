import AppKit
import CoreAudio
@preconcurrency import AVFoundation

// A scripted window for real-recording acceptance tests, launched as its own app
// bundle (open -n) so macOS treats it as a separate application from the terminal.
// It prints "WINDOW_ID <id>" once its window is on screen, then:
//   --tone HZ          plays a continuous sine tone (amplitude 0.3)
//   --markers          every 2 s flashes white for 100 ms and beeps 1 kHz for 50 ms
//                      at the same moment (audio/video sync markers), starting at 1 s
//   --script ACTIONS   comma-separated NAME@SECONDS, e.g. minimize@3,restore@6,
//                      resize@8:420x620,fullscreen@9,close@11,quit@12 (fullscreen toggles
//                      macOS full screen; close destroys the window)
//   --quit-after S     terminate after S seconds (default 600)
//   --output-device UID  play through this CoreAudio device instead of the default output

final class Fixture: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var window: NSWindow?
    private let view = FlashView()
    private let engine = AVAudioEngine()
    private let audio = AudioState()
    private let arguments: [String: String]

    init(arguments: [String: String]) {
        self.arguments = arguments
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = arguments["--title"] ?? "Snapparazzi Fixture"
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        startAudio()
        // Keep playing when the output device changes (e.g. headphones switching modes).
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in self?.restartAudio() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("WINDOW_ID \(window.windowNumber)")
            fflush(stdout)
        }
        if arguments["--markers"] != nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.marker() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.marker()
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        for action in (arguments["--script"] ?? "").split(separator: ",") {
            let parts = action.split(separator: "@")
            guard parts.count == 2 else { continue }
            let name = String(parts[0])
            let detail = parts[1].split(separator: ":")
            guard let seconds = Double(detail[0]) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                self.perform(name, detail.count > 1 ? String(detail[1]) : nil)
            }
        }
        let quitAfter = Double(arguments["--quit-after"] ?? "600") ?? 600
        DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) { NSApp.terminate(nil) }
    }

    private func perform(_ name: String, _ detail: String?) {
        print("ACTION \(name) \(detail ?? "")")
        fflush(stdout)
        switch name {
        case "minimize": window?.miniaturize(nil)
        case "restore": window?.deminiaturize(nil)
        case "close":
            // Close and release, so the window server destroys the window (not just hides it).
            window?.close()
            window?.contentView = nil
            window = nil
        case "quit": NSApp.terminate(nil)
        case "fullscreen": window?.toggleFullScreen(nil)
        case "resize":
            let size = (detail ?? "400x600").split(separator: "x").compactMap { Double($0) }
            if size.count == 2 { window?.setContentSize(NSSize(width: size[0], height: size[1])) }
        default: break
        }
    }

    private func marker() {
        audio.beep()
        view.flash = true
        view.needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.view.flash = false
            self.view.needsDisplay = true
        }
    }

    private func restartAudio() {
        engine.stop()
        engine.reset()
        for node in engine.attachedNodes where node is AVAudioSourceNode { engine.detach(node) }
        startAudio()
    }

    private func startAudio() {
        // The source node declares its own 48 kHz format and the engine converts to the
        // device. (Without an explicit format it rendered at 44.1 kHz while the sine was
        // computed for 48 kHz, so 440 Hz came out as 404 Hz.)
        let rate = 48_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        audio.tone = Double(arguments["--tone"] ?? "0") ?? 0
        let state = audio
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for frame in 0..<Int(frameCount) {
                let value = state.next(rate: rate)
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        engine.attach(source)
        if let uid = arguments["--output-device"] { useOutputDevice(uid) }
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    // Routes only this app's audio (the system default output is left alone).
    private func useOutputDevice(_ uid: String) {
        var device = AudioObjectID(0)
        var cfUID = uid as CFString
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                  mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
        let found = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
        }
        guard found == noErr, device != 0, let unit = engine.outputNode.audioUnit else {
            print("OUTPUT_DEVICE not found: \(uid)")
            return
        }
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                             &device, UInt32(MemoryLayout<AudioObjectID>.size))
        print("OUTPUT_DEVICE \(uid)")
    }
}

final class AudioState: @unchecked Sendable {
    private let lock = NSLock()
    var tone = 0.0
    private var phase = 0.0
    private var beepPhase = 0.0
    private var beepRemaining = 0

    func beep() {
        lock.lock(); beepRemaining = -1; lock.unlock() // armed; sized on the render thread
    }

    func next(rate: Double) -> Float {
        var value = 0.0
        if tone > 0 {
            value += 0.3 * sin(phase)
            phase += 2 * Double.pi * tone / rate
        }
        lock.lock()
        if beepRemaining == -1 { beepRemaining = Int(rate * 0.05) }
        if beepRemaining > 0 {
            value += 0.5 * sin(beepPhase)
            beepPhase += 2 * Double.pi * 1000 / rate
            beepRemaining -= 1
        }
        lock.unlock()
        return Float(value)
    }
}

final class FlashView: NSView {
    var flash = false
    override func draw(_ dirtyRect: NSRect) {
        (flash ? NSColor.white : NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.3, alpha: 1)).setFill()
        bounds.fill()
    }
}

var options: [String: String] = [:]
var index = 1
let argv = CommandLine.arguments
while index < argv.count {
    let key = argv[index]
    if key == "--markers" { options[key] = "1"; index += 1; continue }
    if index + 1 < argv.count { options[key] = argv[index + 1] }
    index += 2
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let fixture = Fixture(arguments: options)
app.delegate = fixture
app.run()
