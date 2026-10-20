import ActivityKit
import AVFoundation
import UIKit
import OSLog

@MainActor
protocol AgentLongRunningKeepAlive: AnyObject {
    var isKeepingAlive: Bool { get }
    var onPulse: (() -> Void)? { get set }

    func setAgentWorkActive(_ active: Bool)
    func applicationDidBecomeActive()
    func applicationDidEnterBackground()
    func prepareForTermination()
}

/// 在 Agent 工作期间用静音音频延长本地 WebSocket 获得执行时间的机会。
///
/// 上游同时使用后台定位与静音音频；本 App 不使用定位（用户要求，且状态栏
/// 的定位箭头会干扰实时活动），因此这里只保留静音音频这一条保活路径：
/// 所有资源只在确有 Agent 工作时创建，并在工作结束后立即释放。
@MainActor
final class AgentBackgroundKeepAliveManager: NSObject, AgentLongRunningKeepAlive {
    private static let logger = Logger(subsystem: "ai.dsh.mobile.ios", category: "agent-keepalive")

    private func traceKeepAlive(_ event: String) {
        Self.logger.notice("[AgentKeepAlive] event=\(event, privacy: .public) background=\(self.applicationIsInBackground) workActive=\(self.agentWorkIsActive) audio=\(self.silentAudioIsRunning) liveActivitiesEnabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)")
    }

    static let shared = AgentBackgroundKeepAliveManager()

    private let pulseInterval: TimeInterval = 25

    private var agentWorkIsActive = false
    private var applicationIsInBackground = false

    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?
    private var silentAudioBuffer: AVAudioPCMBuffer?
    private var audioSessionIsActive = false
    private var isStartingSilentAudio = false
    private var pulseTimer: Timer?

    var onPulse: (() -> Void)?

    var isKeepingAlive: Bool { silentAudioIsRunning }

    private var silentAudioIsRunning: Bool {
        audioEngine?.isRunning == true && audioPlayer?.isPlaying == true
    }

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleApplicationTermination),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setAgentWorkActive(_ active: Bool) {
        guard agentWorkIsActive != active else { return }
        agentWorkIsActive = active

        guard active else {
            stopAllResources()
            return
        }

        if applicationIsInBackground {
            startBackgroundResources()
        }
    }

    func applicationDidBecomeActive() {
        applicationIsInBackground = false
        stopSilentAudio()
        stopPulseTimer()
    }

    func applicationDidEnterBackground() {
        applicationIsInBackground = true
        traceKeepAlive("enter-background")
        guard agentWorkIsActive else { return }
        startBackgroundResources()
    }

    func prepareForTermination() {
        agentWorkIsActive = false
        stopAllResources()
    }

    private func startBackgroundResources() {
        startSilentAudio()
        startPulseTimer()
        pulse()
        traceKeepAlive("resources-started")
    }

    private func startSilentAudio() {
        traceKeepAlive("startSilentAudio")
        guard agentWorkIsActive, applicationIsInBackground else { return }
        guard !silentAudioIsRunning, !isStartingSilentAudio else { return }
        isStartingSilentAudio = true
        defer { self.isStartingSilentAudio = false }

        stopSilentAudio(deactivateSession: false)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            audioSessionIsActive = true

            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
                stopSilentAudio()
                return
            }
            let frameCount = AVAudioFrameCount(format.sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            buffer.frameLength = frameCount
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    channels[channel].initialize(repeating: 0, count: Int(frameCount))
                }
            }

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.volume = 0
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            engine.prepare()
            try engine.start()
            player.play()

            audioEngine = engine
            audioPlayer = player
            silentAudioBuffer = buffer
        } catch {
            stopSilentAudio()
#if DEBUG
            print("[AgentKeepAlive] 无法启动静音音频：\(error.localizedDescription)")
#endif
        }
    }

    private func stopSilentAudio(deactivateSession: Bool = true) {
        audioPlayer?.stop()
        audioEngine?.stop()
        if let player = audioPlayer, let engine = audioEngine {
            engine.detach(player)
        }
        audioPlayer = nil
        audioEngine = nil
        silentAudioBuffer = nil
        if deactivateSession, audioSessionIsActive {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            audioSessionIsActive = false
        }
    }

    private func startPulseTimer() {
        guard pulseTimer == nil else { return }
        let timer = Timer(timeInterval: pulseInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pulse() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
    }

    private func stopPulseTimer() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    private func pulse() {
        guard agentWorkIsActive, applicationIsInBackground else { return }
        if !silentAudioIsRunning { startSilentAudio() }
        onPulse?()
    }

    private func stopAllResources() {
        traceKeepAlive("stopAllResources")
        stopPulseTimer()
        stopSilentAudio()
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        traceKeepAlive("audio-interruption type=\((notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? UInt.max)")
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            stopSilentAudio(deactivateSession: false)
        } else if agentWorkIsActive, applicationIsInBackground {
            startSilentAudio()
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard agentWorkIsActive, applicationIsInBackground else { return }
        if !silentAudioIsRunning { startSilentAudio() }
    }

    @objc private func handleMediaServicesReset() {
        guard agentWorkIsActive, applicationIsInBackground else { return }
        stopSilentAudio(deactivateSession: false)
        startSilentAudio()
    }

    @objc private func handleApplicationTermination() {
        prepareForTermination()
    }
}
