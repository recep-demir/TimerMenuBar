import SwiftUI
import Combine
import Foundation
import UserNotifications
import CoreLocation

@main
struct PrayerTimerApp: App {
    @StateObject private var timerManager = PrayerTimerManager()
    
    var body: some Scene {
        MenuBarExtra {
            // --- 1. Bölüm: Bilgi Alanı (Parlak Ama Tepkisiz) ---
            VStack(alignment: .leading, spacing: 4) {
                // ŞEHİR
                Button(action: {}) {
                    Text(timerManager.cityDisplay)
                        .font(.headline)
                        // .primary rengini zorluyoruz
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain) // Buton arka planını kaldırır
                .disabled(true)      // Tıklanmayı engeller (Mouse tepki vermez)
                
                // TARİH (Miladi)
                Button(action: {}) {
                    Text(timerManager.gregorianDateString)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(true)

                // TARİH (Hicri)
                Button(action: {}) {
                    Text(timerManager.hijriDateString)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            
            Divider()
            
            // --- 2. Bölüm: Geri Sayım ---
            if !timerManager.nextEventDisplayName.isEmpty {
                Button(action: {}) {
                    Text("\(timerManager.nextEventDisplayName) \(timerManager.timeRemainingString)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(true)
            } else {
                Text("Veri Alınıyor...")
            }
            
            Divider()
            
            // --- 3. Bölüm: Vakit Listesi ---
            ForEach(timerManager.displayNames, id: \.self) { displayName in
                let apiKey = timerManager.getApiKey(for: displayName)
                let time = timerManager.getFormattedTime(for: apiKey)
                let iconName = timerManager.getIconName(for: apiKey)
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
                    // Burası interaktif kalmalı, o yüzden normal Label
                    Label {
                        Text("\(displayName): \(time)")
                            .fontWeight(isCurrent ? .heavy : .regular)
                            .foregroundStyle(isCurrent ? .primary : .primary)
                    } icon: {
                        Image(systemName: iconName)
                    }
                }
            }

            Divider()
            
            // --- 4. Bölüm: Alt İşlemler ---
            Button("Konum Değiştir") {
                openSettingsWindow()
            }
            
            Button("Vakitleri Güncelle") {
                Task { await timerManager.refreshData() }
            }
            
            Button("Çıkış") { NSApplication.shared.terminate(nil) }
            
        } label: {
            HStack(spacing: 5) {
                Image(systemName: timerManager.menuBarIcon)
                    .imageScale(.medium)
                
                if timerManager.shouldShowCountdown {
                    Text(timerManager.menuBarText)
                        .font(.system(size: 14, weight: .medium).monospacedDigit())
                }
            }
        }
        // .menuBarExtraStyle(.window) KODUNU KALDIRDIK (Standart Menüye Dönüş)
    }
    
    func openSettingsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Konum Ayarları"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(manager: timerManager))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var manager: PrayerTimerManager
    @State private var searchInput: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Şehir Arayın")
                .font(.headline)
            
            HStack {
                TextField("Örn: Luzern veya Fatih, Istanbul", text: $searchInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await manager.searchLocation(query: searchInput) }
                    }
                
                Button("Ara") {
                    Task { await manager.searchLocation(query: searchInput) }
                }
            }
            
            Divider()
            
            if !manager.searchStatusMessage.isEmpty {
                HStack {
                    Image(systemName: manager.isLocationFound ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(manager.isLocationFound ? .green : .orange)
                    Text(manager.searchStatusMessage)
                        .font(.callout)
                        .lineLimit(2)
                }
                .padding(5)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 320, height: 220)
    }
}

// MARK: - Manager
@MainActor
class PrayerTimerManager: ObservableObject {
    @Published var menuBarText: String = ""
    @Published var menuBarIcon: String = "clock"
    @Published var shouldShowCountdown: Bool = false
    
    @Published var nextEventDisplayName: String = ""
    @Published var timeRemainingString: String = ""
    
    @Published var cityDisplay: String = "Yükleniyor..."
    @Published var gregorianDateString: String = ""
    @Published var hijriDateString: String = ""
    
    @Published var searchStatusMessage: String = ""
    @Published var isLocationFound: Bool = false
    
    @Published var currentEventApiKey: String = ""
    @Published var settings: [String: PrayerSetting] = [:]
    
    private let eventMapping = ["Fajr": "İmsak", "Sunrise": "Güneş", "Dhuhr": "Öğle", "Asr": "İkindi", "Maghrib": "Akşam", "Isha": "Yatsı"]
    let displayNames = ["İmsak", "Güneş", "Öğle", "İkindi", "Akşam", "Yatsı"]
    private let apiKeyOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    
    // İKON: Yatsı = moon.phase.waning.crescent
    private let iconMap = [
        "Fajr": "moon.stars.fill",
        "Sunrise": "sunrise.fill",
        "Dhuhr": "sun.max.fill",
        "Asr": "sun.haze.fill",
        "Maghrib": "sunset.fill",
        "Isha": "moon.phase.waning.crescent"
    ]
    
    private var timer: Timer?
    
    init() {
        loadSettings()
        loadStoredLocation(fetchFresh: false)
        updateDisplay()
        
        requestNotificationPermission()
        Task { await refreshData() }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDisplay()
            }
        }
    }
    
    // MARK: - Location Logic
    
    func searchLocation(query: String) async {
        guard !query.isEmpty else { return }
        searchStatusMessage = "Konum aranıyor..."
        isLocationFound = false
        
        let localGeocoder = CLGeocoder()
        
        do {
            let placemarks = try await localGeocoder.geocodeAddressString(query)
            
            if let place = placemarks.first, let location = place.location {
                let lat = location.coordinate.latitude
                let lng = location.coordinate.longitude
                
                let cityName = place.locality ?? place.name ?? query
                let countryName = place.country ?? ""
                let displayName = "\(cityName), \(countryName)"
                
                self.cityDisplay = displayName
                self.searchStatusMessage = "Bulundu: \(displayName)"
                self.isLocationFound = true
                
                UserDefaults.standard.set(lat, forKey: "saved_lat")
                UserDefaults.standard.set(lng, forKey: "saved_lng")
                UserDefaults.standard.set(displayName, forKey: "saved_city_name")
                
                await fetchPrayerTimes(lat: lat, lng: lng)
                
            } else {
                searchStatusMessage = "Konum bulunamadı."
            }
        } catch {
            print("Geocoding Error: \(error.localizedDescription)")
            searchStatusMessage = "Hata: Konum bulunamadı."
        }
    }
    
    func refreshData() async {
        loadStoredLocation(fetchFresh: true)
    }
    
    private func loadStoredLocation(fetchFresh: Bool) {
        let lat = UserDefaults.standard.double(forKey: "saved_lat")
        let lng = UserDefaults.standard.double(forKey: "saved_lng")
        let name = UserDefaults.standard.string(forKey: "saved_city_name") ?? "Seçilmedi"
        
        self.cityDisplay = name
        
        if lat != 0.0 || lng != 0.0 {
            if fetchFresh {
                Task { await fetchPrayerTimes(lat: lat, lng: lng) }
            }
        } else {
            if fetchFresh {
                Task { await fetchPrayerTimes(lat: 47.0502, lng: 8.3093)
                       self.cityDisplay = "Lucerne, Switzerland" }
            }
        }
    }

    func fetchPrayerTimes(lat: Double, lng: Double) async {
        let date = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        let urlString = "https://api.aladhan.com/v1/calendar?latitude=\(lat)&longitude=\(lng)&method=13&month=\(month)&year=\(year)"
        
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(CalendarResponse.self, from: data)
            
            let day = calendar.component(.day, from: date)
            if let todayData = response.data.first(where: { Int($0.date.gregorian.day) == day }) {
                
                UserDefaults.standard.set(todayData.timings, forKey: "timings")
                
                self.gregorianDateString = todayData.date.readable
                self.hijriDateString = "\(todayData.date.hijri.day) \(todayData.date.hijri.month.en) \(todayData.date.hijri.year)"
                
                scheduleAllNotifications()
                updateDisplay()
            }
        } catch {
            print("API Error: \(error)")
        }
    }

    // MARK: - Display Logic
    
    func updateDisplay() {
        guard let timings = UserDefaults.standard.dictionary(forKey: "timings") as? [String: String] else { return }
        let now = Date()
        
        var targetDate: Date?
        var targetApiKey: String = ""
        
        for apiKey in apiKeyOrder {
            if let timeStr = timings[apiKey], let pDate = parseTime(timeStr) {
                let full = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: pDate),
                                                minute: Calendar.current.component(.minute, from: pDate),
                                                second: 0, of: now)!
                
                if full > now {
                    if targetDate == nil || full < targetDate! {
                        targetDate = full
                        targetApiKey = apiKey
                    }
                }
            }
        }
        
        if targetDate == nil, let fajrTime = timings["Fajr"], let pDate = parseTime(fajrTime) {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
            targetDate = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: pDate),
                                               minute: Calendar.current.component(.minute, from: pDate),
                                               second: 0, of: tomorrow)
            targetApiKey = "Fajr"
        }
        
        if let finalTarget = targetDate {
            let diff = Int(finalTarget.timeIntervalSince(now))
            let nextName = eventMapping[targetApiKey] ?? ""
            let suffix = getSuffix(for: nextName)
            
            let hours = diff / 3600
            let minutes = (diff % 3600) / 60
            
            self.nextEventDisplayName = "\(nextName)\(suffix)"
            
            if hours > 0 {
                self.timeRemainingString = "\(hours) sa \(minutes) dk. kaldı"
            } else {
                self.timeRemainingString = "\(minutes) dk. kaldı"
            }
            
            if let targetIndex = apiKeyOrder.firstIndex(of: targetApiKey) {
                let currentIndex = (targetIndex - 1 + apiKeyOrder.count) % apiKeyOrder.count
                let currentKey = apiKeyOrder[currentIndex]
                
                self.currentEventApiKey = currentKey
                self.menuBarIcon = iconMap[currentKey] ?? "clock"
            }
            
            if diff <= 3600 {
                let minsLeft = (diff / 60) + 1
                self.menuBarText = "\(minsLeft) dk"
                self.shouldShowCountdown = true
            } else {
                self.menuBarText = ""
                self.shouldShowCountdown = false
            }
        }
    }
    
    private func parseTime(_ str: String) -> Date? {
        let cleanTime = String(str.prefix(5))
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.date(from: cleanTime)
    }
    
    func getFormattedTime(for apiKey: String) -> String {
        guard let timings = UserDefaults.standard.dictionary(forKey: "timings") as? [String: String],
              let rawTime = timings[apiKey] else { return "--:--" }
        return String(rawTime.prefix(5))
    }
    
    func getIconName(for apiKey: String) -> String { return iconMap[apiKey] ?? "clock" }
    
    func getApiKey(for displayName: String) -> String {
        return eventMapping.first(where: { $1 == displayName })?.key ?? ""
    }
    
    private func getSuffix(for name: String) -> String {
        switch name {
        case "İmsak": return "a"; case "Güneş": return "e"; case "Öğle": return "ye"
        case "İkindi": return "ye"; case "Akşam": return "a"; case "Yatsı": return "ya"
        default: return "'ya"
        }
    }
    
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
                if triggerDate > Date() { sendNotification(id: "\(apiKey)_pre", title: "\(displayName) Yaklaşıyor", body: "Vakte az kaldı.", date: triggerDate) }
            }
            if setting.onTime && fullDate > Date() { sendNotification(id: "\(apiKey)_now", title: "\(displayName) Vakti", body: "Vakit girdi.", date: fullDate) }
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

// MARK: - API Models
struct PrayerSetting: Codable { var preReminder: Bool = false; var onTime: Bool = false; var preMinutes: Int = 35 }
struct CalendarResponse: Codable { let data: [CalendarData] }
struct CalendarData: Codable { let timings: [String: String]; let date: DateInfo }
struct DateInfo: Codable { let readable: String; let gregorian: GregorianDate; let hijri: HijriDate }
struct GregorianDate: Codable { let day: String }
struct HijriDate: Codable { let day: String; let month: HijriMonth; let year: String }
struct HijriMonth: Codable { let en: String }
