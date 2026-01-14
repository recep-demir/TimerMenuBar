import SwiftUI
import Combine
import Foundation
import UserNotifications

@main
struct PrayerTimerApp: App {
    @StateObject private var timerManager = PrayerTimerManager()

    var body: some Scene {
        MenuBarExtra {
            Text("Sıradaki: \(timerManager.nextEventDisplayName)")
            Divider()
            
            ForEach(timerManager.displayNames, id: \.self) { displayName in
                let apiKey = timerManager.getApiKey(for: displayName)
                let time = timerManager.getFormattedTime(for: apiKey)
                let isCurrent = timerManager.currentEventApiKey == apiKey
                
                Menu {
                    Toggle("35 Dakika Önce Hatırlat", isOn: Binding(
                        get: { timerManager.settings[apiKey]?.preReminder ?? false },
                        set: { timerManager.updateSetting(for: apiKey, pre: $0) }
                    ))
                    Toggle("Vaktinde Hatırlat", isOn: Binding(
                        get: { timerManager.settings[apiKey]?.onTime ?? false },
                        set: { timerManager.updateSetting(for: apiKey, onTime: $0) }
                    ))
                } label: {
                    Text("\(displayName):  \(time)")
                        .fontWeight(isCurrent ? .bold : .regular)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
            }

            Divider()
            Button("Vakitleri Güncelle") { Task { await timerManager.fetchPrayerTimes() } }
            Button("Çıkış") { NSApplication.shared.terminate(nil) }
        } label: {
            // Saniyeler kalktığı için artık titreme yapmaz.
            // Yine de monospacedDigit kullanarak rakam geçişlerini sabitledik.
            HStack(spacing: 5) {
                Image(systemName: timerManager.currentIconName)
                    .imageScale(.medium)
                
                Text(timerManager.displayTextOnly)
                    .font(.system(size: 14, weight: .medium, design: .default).monospacedDigit())
            }
        }
    }
}

@MainActor
class PrayerTimerManager: ObservableObject {
    @Published var displayTextOnly: String = "..."
    @Published var currentIconName: String = "clock"
    @Published var nextEventDisplayName: String = ""
    @Published var currentEventApiKey: String = ""
    @Published var settings: [String: PrayerSetting] = [:]
    
    private let eventMapping = ["Fajr": "Imsak  ", "Sunrise": "Güneş ", "Dhuhr": "Öğle   ", "Asr": "İkindi   ", "Maghrib": "Akşam ", "Isha": "Yatsı    "]
    let displayNames = ["Imsak  ", "Güneş ", "Öğle   ", "İkindi   ", "Akşam ", "Yatsı    "]
    private let apiKeyOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    private let iconMap = ["Fajr": "moon.stars.fill", "Sunrise": "sunrise.fill", "Dhuhr": "sun.max.fill", "Asr": "sun.haze.fill", "Maghrib": "sunset.fill", "Isha": "sparkles"]
    
    private var timer: Timer?

    init() {
        loadSettings()
        requestNotificationPermission()
        Task { await fetchPrayerTimes() }
        
        // Saniyeleri göstermediğimiz için artık 10 saniyede bir kontrol etmesi yeterli.
        // Bu, pil ömrü için mükemmeldir.
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            Task { @MainActor in self.updateDisplay() }
        }
    }

    func getFormattedTime(for apiKey: String) -> String {
        let timings = UserDefaults.standard.dictionary(forKey: "timings") as? [String: String]
        return timings?[apiKey] ?? "--:--"
    }

    func getApiKey(for displayName: String) -> String {
        return eventMapping.first(where: { $1 == displayName })?.key ?? ""
    }

    func fetchPrayerTimes() async {
        let urlString = "https://api.aladhan.com/v1/timingsByCity?city=Lucerne&country=Switzerland&method=13"
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(PrayerResponse.self, from: data)
            UserDefaults.standard.set(response.data.timings, forKey: "timings")
            scheduleAllNotifications()
            updateDisplay()
        } catch { print("API Error") }
    }

    func updateDisplay() {
        guard let timings = UserDefaults.standard.dictionary(forKey: "timings") as? [String: String] else { return }
        let now = Date()
        
        var targetDate: Date?; var targetApiKey: String = ""; var targetTimeString: String = ""
        var activeKey = "Isha"; var lastPassedTime: Date?

        for apiKey in apiKeyOrder {
            if let timeStr = timings[apiKey], let pDate = parseTime(timeStr) {
                let full = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: pDate),
                                                minute: Calendar.current.component(.minute, from: pDate),
                                                second: 0, of: now)!
                if full > now {
                    if targetDate == nil || full < targetDate! {
                        targetDate = full; targetApiKey = apiKey; targetTimeString = timeStr
                    }
                }
                if full <= now {
                    if lastPassedTime == nil || full > lastPassedTime! {
                        lastPassedTime = full; activeKey = apiKey
                    }
                }
            }
        }
        
        // Yarınki İmsak kontrolü
        if targetDate == nil, let fajrTime = timings["Fajr"], let pDate = parseTime(fajrTime) {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
            targetDate = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: pDate),
                                               minute: Calendar.current.component(.minute, from: pDate),
                                               second: 0, of: tomorrow)
            targetApiKey = "Fajr"; targetTimeString = fajrTime
        }

        self.currentEventApiKey = activeKey
        
        if let finalTarget = targetDate {
            let diff = Int(finalTarget.timeIntervalSince(now))
            self.nextEventDisplayName = eventMapping[targetApiKey]?.trimmingCharacters(in: .whitespaces) ?? ""
            self.currentIconName = iconMap[targetApiKey] ?? "clock"
            
            if diff <= 3600 {
                // Saniyeleri attık, sadece kalan dakikayı gösteriyoruz.
                // 02:00, 01:00 formatı için:
                let mins = (diff / 60) + 1
                self.displayTextOnly = String(format: "%02d:00", mins)
            } else {
                self.displayTextOnly = targetTimeString
            }
        }
    }

    private func parseTime(_ str: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.date(from: str)
    }

    // Bildirim ve Ayar Fonksiyonları (Aynı kalıyor)
    func updateSetting(for apiKey: String, pre: Bool? = nil, onTime: Bool? = nil) {
        var current = settings[apiKey] ?? PrayerSetting()
        if let pre = pre { current.preReminder = pre }; if let onTime = onTime { current.onTime = onTime }
        settings[apiKey] = current; saveSettings(); scheduleAllNotifications()
    }

    private func scheduleAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        guard let timings = UserDefaults.standard.dictionary(forKey: "timings") as? [String: String] else { return }
        for (apiKey, displayName) in eventMapping {
            guard let timeStr = timings[apiKey], let pDate = parseTime(timeStr), let setting = settings[apiKey] else { continue }
            let today = Calendar.current.startOfDay(for: Date())
            let fullDate = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: pDate),
                                               minute: Calendar.current.component(.minute, from: pDate),
                                               second: 0, of: today)!
            if setting.preReminder {
                let triggerDate = fullDate.addingTimeInterval(-TimeInterval(setting.preMinutes * 60))
                if triggerDate > Date() { sendNotification(id: "\(apiKey)_pre", title: "\(displayName.trimmingCharacters(in: .whitespaces)) Yaklaşıyor", body: "Vakte az kaldı.", date: triggerDate) }
            }
            if setting.onTime && fullDate > Date() { sendNotification(id: "\(apiKey)_now", title: "\(displayName.trimmingCharacters(in: .whitespaces)) Vakti", body: "Vakit girdi.", date: fullDate) }
        }
    }

    private func sendNotification(id: String, title: String, body: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func requestNotificationPermission() { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
    private func saveSettings() { if let encoded = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(encoded, forKey: "prayer_settings") } }
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "prayer_settings"), let decoded = try? JSONDecoder().decode([String: PrayerSetting].self, from: data) { settings = decoded }
        else { for apiKey in eventMapping.keys { settings[apiKey] = PrayerSetting() } }
    }
}

// MARK: - Models
struct PrayerSetting: Codable { var preReminder: Bool = false; var onTime: Bool = false; var preMinutes: Int = 35 }
struct PrayerResponse: Codable, Sendable { let data: PrayerData }
struct PrayerData: Codable, Sendable { let timings: [String: String] }
