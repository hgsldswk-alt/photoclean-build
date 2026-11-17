import Foundation
import UserNotifications

enum ReminderScheduler {
    static let identifier = "photoclean-monthly"
    static func setEnabled(_ enabled: Bool, pro: Bool, lastMonthCount: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled, pro else { return false }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = L.t("花两分钟，整理相册")
        content.body = L.f("上个月有 %@ 张照片，滑一遍，留下喜欢的。", String(lastMonthCount))
        content.sound = .default
        var date = DateComponents(); date.day = 1; date.hour = 20; date.minute = 0
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true)))
            return true
        } catch { return false }
    }
}
