import SwiftUI
import OSLog

private final class AgentNotificationAppDelegate: NSObject, UIApplicationDelegate {
    func applicationDidBecomeActive(_ application: UIApplication) {
        AgentLiveActivityManager.shared.applicationDidBecomeActive()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
#if DEBUG
        AppExecutionHeartbeat.start()
#endif
        _ = AgentUserNotificationManager.shared
        return true
    }
}

@main
struct DeepSeekHarnessMobileApp: App {
    @UIApplicationDelegateAdaptor(AgentNotificationAppDelegate.self) private var notificationAppDelegate
    @StateObject private var hosts = MultiGatewayStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(ObjectIdentifier(hosts.activeStore))
                .environmentObject(hosts.activeStore)
                .environmentObject(hosts)
                .modifier(AppFontScope())
                // Terminal theme is dark-only by design: the palette, hairlines and
                // accent assume a near-black field.
                .preferredColorScheme(.dark)
                .task {
                    // Lets UI review builds run without the one-time system prompt
                    // covering the screen (set via SIMCTL_CHILD_MYDSH_SKIP_NOTIFICATION_PROMPT=1).
                    guard ProcessInfo.processInfo.environment["MYDSH_SKIP_NOTIFICATION_PROMPT"] != "1" else { return }
                    await AgentUserNotificationManager.shared.requestAuthorizationIfNeeded()
                }
                .alert("主机连接", isPresented: Binding(get: { hosts.error != nil }, set: { if !$0 { hosts.error = nil } })) {
                    Button("好", role: .cancel) { hosts.error = nil; hosts.cancelPairing() }
                } message: { Text(hosts.error ?? "") }
        }
    }
}

#if DEBUG
/// 独立诊断进程是否仍在执行，不依赖任务、连接或主线程，也不申请后台保活额度。
@MainActor
private enum AppExecutionHeartbeat {
    private static var timer: DispatchSourceTimer?

    static func start() {
        guard timer == nil else { return }
        let logger = Logger(subsystem: "ai.dsh.mobile.ios", category: "app-execution-heartbeat")
        let processID = ProcessInfo.processInfo.processIdentifier
        let launchID = UUID().uuidString
        let startedAt = ProcessInfo.processInfo.systemUptime
        let queue = DispatchQueue(label: "ai.dsh.mobile.ios.execution-heartbeat", qos: .utility)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(50))
        source.setEventHandler {
            let uptime = ProcessInfo.processInfo.systemUptime
            let elapsed = uptime - startedAt
            logger.notice("[AppExecutionHeartbeat] pid=\(processID) launchID=\(launchID, privacy: .public) elapsedSeconds=\(elapsed) uptimeSeconds=\(uptime)")
        }
        // 持有 timer，使无任务、切后台和连接断开时仍继续尝试输出。
        timer = source
        source.resume()
    }
}
#endif
