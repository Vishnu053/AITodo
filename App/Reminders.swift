import Foundation
import UserNotifications
import AIToDoCore

/// Local notifications scheduled by the system, so they fire even when the app is closed.
@MainActor
final class Reminders {
    private let center = UNUserNotificationCenter.current()
    /// iOS keeps at most 64 pending local notifications; stay under it.
    private let limit = 60

    func isAuthorized() async -> Bool {
        let s = await center.notificationSettings().authorizationStatus
        return s == .authorized || s == .provisional || s == .ephemeral
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func cancelAll() { center.removeAllPendingNotificationRequests() }

    /// Timed todos fire at their time; all-day todos at 9:00 on the day. Rebuilt on every change.
    func reschedule(_ todos: [Todo], now: Date, calendar: Calendar) async {
        center.removeAllPendingNotificationRequests()
        let upcoming: [(Todo, Date)] = todos.filter(\.isOpen).compactMap { t in
            guard let due = t.due else { return nil }
            let fire = t.allDay ? calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due) : due
            guard let fire, fire > now else { return nil }
            return (t, fire)
        }
        .sorted { $0.1 < $1.1 }
        for (t, fire) in upcoming.prefix(limit) {
            let content = UNMutableNotificationContent()
            content.title = t.title
            content.body = t.allDay ? "Due today" : Dates.formatDue(fire, allDay: false, now: fire, calendar: calendar)
            content.sound = .default
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: t.id.uuidString, content: content, trigger: trigger))
        }
    }
}
