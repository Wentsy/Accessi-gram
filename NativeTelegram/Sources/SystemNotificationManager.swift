import UIKit
import UserNotifications

/// APNs is the only supported way to receive reliable notifications while
/// iOS has suspended or terminated the app. Never emulate it with timers.
@MainActor
final class SystemNotificationManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = SystemNotificationManager()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                let service = TelegramService.shared
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    service.systemNotificationStatus = "已取得 iOS 通知權限"
                    UIApplication.shared.registerForRemoteNotifications()
                case .denied:
                    service.systemNotificationStatus = "通知已被拒絕，請到 iOS 設定開啟"
                case .notDetermined:
                    service.systemNotificationStatus = "尚未取得通知權限"
                @unknown default:
                    service.systemNotificationStatus = "通知權限狀態未知"
                }
            }
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            granted, error in
            Task { @MainActor in
                if let error {
                    TelegramService.shared.systemNotificationStatus = "通知授權失敗：\(error.localizedDescription)"
                } else if granted {
                    self.refreshAuthorizationStatus()
                } else {
                    TelegramService.shared.systemNotificationStatus = "尚未允許 iOS 通知"
                }
            }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        TelegramService.shared.registerPushToken(token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        TelegramService.shared.systemNotificationStatus =
            "APNs 註冊失敗：\(error.localizedDescription)。請確認 OC 已開啟 Push Notifications 簽署能力"
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // The app already vibrates for live TDLib updates. Avoid a second
        // system banner/sound every time the user is reading a chat.
        []
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let data = response.notification.request.content.userInfo
        let root = data.reduce(into: JSONObject()) { result, entry in
            if let key = entry.key as? String { result[key] = entry.value }
        }
        let custom = root.object("data").object("custom")
        let id = root.number("chat_id") != 0
            ? root.number("chat_id")
            : custom.number("chat_id")
        if id != 0 {
            TelegramService.shared.notificationChatID = id
        }
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let payload = userInfo.reduce(into: JSONObject()) { result, entry in
            if let key = entry.key as? String { result[key] = entry.value }
        }
        Task { @MainActor in
            TelegramService.shared.processPush(payload) { handled in
                completionHandler(handled ? .newData : .noData)
            }
        }
    }
}
