import SwiftUI
import Combine
import Foundation
import UserNotifications
import CoreLocation
import ServiceManagement // YENİ: Başlangıçta çalıştırma için gerekli

// MARK: - Enums & Models
enum AppLanguage: String, CaseIterable, Identifiable {
    case tr = "Türkçe"
    case en = "English"
    case de = "Deutsch"
    var id: String { self.rawValue }
}

struct CalculationMethod: Identifiable, Hashable {
    let id: Int
    let name: String
}

// Çeviri Anahtarları
enum L10n: String {
    case settingsTitle, locationTitle, generalTitle, language, method, methodNote
    case searchPlaceholder, searchBtn, currentLoc, notFound, searching, found
    case updateBtn, quitBtn, loading
    case reminderPre, reminderOnTime
    case timeRemainingHours, timeRemainingMins, timeRemainingLeft
    case notificationPreBody, notificationNowBody
    case launchAtLogin // YENİ: Çeviri anahtarı eklendi
}

@main
struct PrayerTimerApp: App {
    @StateObject private var timerManager = PrayerTimerManager()
    
    var body: some Scene {
        MenuBarExtra {
            // --- 1. Bölüm: Bilgi ---
            VStack(alignment: .leading, spacing: 6) {
                Button(action: {}) {
                    Text(timerManager.cityDisplay)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(false)
                
                HStack(spacing: 5) {
                    Text("\(timerManager.gregorianDateString) - \(timerManager.hijriDateString)")
                }
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            
            Divider()
            
            // --- 2. Bölüm: Geri Sayım ---
            if !timerManager.nextEventDisplayName.isEmpty {
                Button(action: {}) {
                    Text("\(timerManager.nextEventDisplayName) \(timerManager.timeRemainingString)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(false)
            } else {
                Text(timerManager.t(.loading))
            }
            
            Divider()
            
            // --- 3. Bölüm: Vakit Listesi ---
            ForEach(timerManager.apiKeyOrder, id: \.self) { apiKey in
                let displayName = timerManager.getLocalizedTimeName(for: apiKey)
                let time = timerManager.getFormattedTime(for: apiKey)
                let iconName = timerManager.getIconName(for: apiKey)
                let isCurrent = timerManager.currentEventApiKey == apiKey
                
                Menu {
                    Toggle(timerManager.t(.reminderPre), isOn: Binding(
                        get: { timerManager.settings[apiKey]?.preReminder ?? false },
                        set: { timerManager.updateSetting(for: apiKey, pre: $0) }
                    ))
                    Toggle(timerManager.t(.reminderOnTime), isOn: Binding(
                        get: { timerManager.settings[apiKey]?.onTime ?? false },
                        set: { timerManager.updateSetting(for: apiKey, onTime: $0) }
                    ))
                } label: {
                    Label {
                        Text("\(displayName): \(time)")
                            .fontWeight(isCurrent ? .heavy : .regular)
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: iconName)
                    }
                }
            }

            Divider()
            
            // --- 4. Bölüm: Alt İşlemler ---
            Button(timerManager.t(.settingsTitle)) {
                openSettingsWindow()
            }
            
            Button(timerManager.t(.updateBtn)) {
                Task { await timerManager.refreshData() }
            }
            
            Button(timerManager.t(.quitBtn)) { NSApplication.shared.terminate(nil) }
            
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
    }
    
    func openSettingsWindow() {
        let title = timerManager.t(.settingsTitle)
        
        if let window = NSApp.windows.first(where: { $0.title == title || $0.title == "Settings" || $0.title == "Ayarlar" || $0.title == "Einstellungen" }) {
            window.title = title
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 350),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.center()
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(manager: timerManager))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Settings View
// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var manager: PrayerTimerManager
    @State private var searchInput: String = ""
    
    var body: some View {
        TabView {
            // TAB 1: GENEL (Düzenlendi)
            VStack(alignment: .leading, spacing: 25) { // 25 birim boşluk ve sola hizalama
                
                // 1. Başlangıçta Çalıştır
                Toggle(manager.t(.launchAtLogin), isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Launch at login error: \(error)")
                        }
                    }
                ))
                .font(.body)
                
                Divider() // Görsel ayrım için çizgi
                
                // 2. Ayarlar Grubu
                VStack(alignment: .leading, spacing: 15) {
                    
                    // Dil Seçimi
                    Picker(manager.t(.language), selection: $manager.selectedLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.rawValue).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 300) // Picker'ın çok uzamasını engellemek için
                    
                    // Hesaplama Yöntemi
                    VStack(alignment: .leading, spacing: 5) {
                        Picker(manager.t(.method), selection: $manager.selectedMethodId) {
                            ForEach(manager.availableMethods) { method in
                                Text(method.name).tag(method.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 380) // Metinler uzun olduğu için biraz daha geniş
                        
                        Text(manager.t(.methodNote))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 5) // Hafif içerden başlasın
                    }
                }
                
                Spacer() // Tüm içeriği yukarı itmek için en alta boşluk
            }
            .padding(30) // Kenarlardan içeri boşluk
            .tabItem {
                Label(manager.t(.generalTitle), systemImage: "gearshape")
            }
            
            // TAB 2: KONUM (Aynı kaldı)
            VStack(alignment: .leading, spacing: 15) {
                Text(manager.t(.locationTitle))
                    .font(.headline)
                
                HStack {
                    TextField(manager.t(.searchPlaceholder), text: $searchInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await manager.searchLocation(query: searchInput) } }
                    
                    Button(manager.t(.searchBtn)) {
                        Task { await manager.searchLocation(query: searchInput) }
                    }
                }
                
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
                
                Text("\(manager.t(.currentLoc)): \(manager.cityDisplay)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(30)
            .tabItem {
                Label(manager.t(.locationTitle), systemImage: "location")
            }
        }
        .frame(width: 480, height: 350) // Pencereyi biraz genişlettim ki method isimleri sığsın
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
    
    @Published var cityDisplay: String = "..."
    @Published var gregorianDateString: String = ""
    @Published var hijriDateString: String = ""
    
    @Published var searchStatusMessage: String = ""
    @Published var isLocationFound: Bool = false
    
    @Published var currentEventApiKey: String = ""
    @Published var settings: [String: PrayerSetting] = [:]
    
    @Published var selectedLanguage: AppLanguage = .tr {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "app_language")
            updateDisplay()
            scheduleAllNotifications()
        }
    }
    
    @Published var selectedMethodId: Int = 13 {
        didSet {
            UserDefaults.standard.set(selectedMethodId, forKey: "calc_method_id")
            Task { await refreshData() }
        }
    }
    
    private var lastFetchDate: Date = Date()
    let apiKeyOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
    
    private var timer: Timer?
    
    // --- ÇEVİRİ VERİLERİ ---
    private let translations: [AppLanguage: [L10n: String]] = [
        .tr: [
            .settingsTitle: "Ayarlar", .locationTitle: "Konum", .generalTitle: "Genel",
            .language: "Dil", .method: "Hesaplama Yöntemi",
            .methodNote: "Yöntem değiştiğinde vakitler otomatik güncellenir.",
            .searchPlaceholder: "Örn: Luzern veya Istanbul", .searchBtn: "Ara",
            .currentLoc: "Mevcut Konum", .notFound: "Bulunamadı", .searching: "Aranıyor...", .found: "Bulundu",
            .updateBtn: "Vakitleri Güncelle", .quitBtn: "Çıkış", .loading: "Yükleniyor...",
            .reminderPre: "35 Dakika Önce Hatırlat", .reminderOnTime: "Vaktinde Hatırlat",
            .timeRemainingHours: "sa", .timeRemainingMins: "dk", .timeRemainingLeft: "kaldı",
            .notificationPreBody: "Vakte 35 dk kaldı.", .notificationNowBody: "Vakit girdi.",
            .launchAtLogin: "Başlangıçta Çalıştır" // YENİ
        ],
        .en: [
            .settingsTitle: "Settings", .locationTitle: "Location", .generalTitle: "General",
            .language: "Language", .method: "Calculation Method",
            .methodNote: "Times will update automatically when method changes.",
            .searchPlaceholder: "Ex: Lucerne or New York", .searchBtn: "Search",
            .currentLoc: "Current Location", .notFound: "Not Found", .searching: "Searching...", .found: "Found",
            .updateBtn: "Refresh Times", .quitBtn: "Quit", .loading: "Loading...",
            .reminderPre: "Remind 35 Min Before", .reminderOnTime: "Remind On Time",
            .timeRemainingHours: "h", .timeRemainingMins: "m", .timeRemainingLeft: "left",
            .notificationPreBody: "35 min remaining.", .notificationNowBody: "Time is now.",
            .launchAtLogin: "Launch at Login" // YENİ
        ],
        .de: [
            .settingsTitle: "Einstellungen", .locationTitle: "Standort", .generalTitle: "Allgemein",
            .language: "Sprache", .method: "Berechnungsmethode",
            .methodNote: "Zeiten werden bei Änderung automatisch aktualisiert.",
            .searchPlaceholder: "Bsp: Luzern oder Berlin", .searchBtn: "Suchen",
            .currentLoc: "Aktueller Standort", .notFound: "Nicht gefunden", .searching: "Suchen...", .found: "Gefunden",
            .updateBtn: "Zeiten aktualisieren", .quitBtn: "Beenden", .loading: "Laden...",
            .reminderPre: "35 Min. vorher erinnern", .reminderOnTime: "Pünktlich erinnern",
            .timeRemainingHours: "Std", .timeRemainingMins: "Min", .timeRemainingLeft: "verbleibend",
            .notificationPreBody: "Noch 35 Min.", .notificationNowBody: "Die Zeit ist gekommen.",
            .launchAtLogin: "Beim Start öffnen" // YENİ
        ]
    ]
    
    // Vakit İsimleri Çevirisi
    private let timeNames: [AppLanguage: [String: String]] = [
        .tr: ["Fajr": "İmsak", "Sunrise": "Güneş", "Dhuhr": "Öğle", "Asr": "İkindi", "Maghrib": "Akşam", "Isha": "Yatsı"],
        .de: ["Fajr": "Imsak", "Sunrise": "Sonne", "Dhuhr": "Mittag", "Asr": "Nachmittag", "Maghrib": "Abend", "Isha": "Nacht"],
        .en: ["Fajr": "Fajr", "Sunrise": "Sunrise", "Dhuhr": "Dhuhr", "Asr": "Asr", "Maghrib": "Maghrib", "Isha": "Isha"]
    ]
    
    let availableMethods: [CalculationMethod] = [
        CalculationMethod(id: 13, name: "Diyanet İşleri Başkanlığı (Turkey)"),
        CalculationMethod(id: 3, name: "Muslim World League"),
        CalculationMethod(id: 2, name: "Islamic Society of North America"),
        CalculationMethod(id: 4, name: "Umm Al-Qura University, Makkah"),
        CalculationMethod(id: 12, name: "Union Organization islamic de France"),
        CalculationMethod(id: 20, name: "KEMENAG - Indonesia"),
        CalculationMethod(id: 15, name: "Moonsighting Committee Worldwide"),
        CalculationMethod(id: 0, name: "Jafari / Shia Ithna-Ashari"),
        CalculationMethod(id: 1, name: "Univ. of Islamic Sciences, Karachi"),
        CalculationMethod(id: 5, name: "Egyptian General Authority of Survey"),
        CalculationMethod(id: 7, name: "Institute of Geophysics, Tehran"),
        CalculationMethod(id: 8, name: "Gulf Region"),
        CalculationMethod(id: 9, name: "Kuwait"),
        CalculationMethod(id: 10, name: "Qatar"),
        CalculationMethod(id: 11, name: "Majlis Ugama Islam Singapura"),
        CalculationMethod(id: 14, name: "Spiritual Admin. of Muslims of Russia"),
        CalculationMethod(id: 16, name: "Dubai"),
        CalculationMethod(id: 17, name: "JAKIM - Malaysia"),
        CalculationMethod(id: 18, name: "Tunisia"),
        CalculationMethod(id: 19, name: "Algeria"),
        CalculationMethod(id: 21, name: "Morocco"),
        CalculationMethod(id: 22, name: "Comunidade Islamica de Lisboa"),
        CalculationMethod(id: 23, name: "Ministry of Awqaf, Jordan")
    ]
    
    private let iconMap = ["Fajr": "moon.stars.fill", "Sunrise": "sunrise.fill", "Dhuhr": "sun.max.fill", "Asr": "sun.haze.fill", "Maghrib": "sunset.fill", "Isha": "moon"]
    
    init() {
        if let savedLang = UserDefaults.standard.string(forKey: "app_language"), let lang = AppLanguage(rawValue: savedLang) {
            self.selectedLanguage = lang
        }
        
        let savedMethod = UserDefaults.standard.integer(forKey: "calc_method_id")
        self.selectedMethodId = (savedMethod == 0 && UserDefaults.standard.object(forKey: "calc_method_id") == nil) ? 13 : savedMethod
        
        loadSettings()
        loadStoredLocation(fetchFresh: false)
        updateDisplay()
        
        requestNotificationPermission()
        Task { await refreshData() }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.updateDisplay()
                if !Calendar.current.isDateInToday(self.lastFetchDate) {
                    self.lastFetchDate = Date()
                    await self.refreshData()
                }
            }
        }
    }
    
    func t(_ key: L10n) -> String {
        return translations[selectedLanguage]?[key] ?? ""
    }
    
    func getLocalizedTimeName(for apiKey: String) -> String {
        return timeNames[selectedLanguage]?[apiKey] ?? apiKey
    }

    func searchLocation(query: String) async {
        guard !query.isEmpty else { return }
        searchStatusMessage = t(.searching)
        isLocationFound = false
        
        let localGeocoder = CLGeocoder()
        do {
            let placemarks = try await localGeocoder.geocodeAddressString(query)
            if let place = placemarks.first, let location = place.location {
                let lat = location.coordinate.latitude
                let lng = location.coordinate.longitude
                let displayName = "\(place.locality ?? place.name ?? query), \(place.country ?? "")"
                
                self.cityDisplay = displayName
                self.searchStatusMessage = "\(t(.found)): \(displayName)"
                self.isLocationFound = true
                
                UserDefaults.standard.set(lat, forKey: "saved_lat")
                UserDefaults.standard.set(lng, forKey: "saved_lng")
                UserDefaults.standard.set(displayName, forKey: "saved_city_name")
                
                await fetchPrayerTimes(lat: lat, lng: lng)
            } else {
                searchStatusMessage = t(.notFound)
            }
        } catch {
            searchStatusMessage = t(.notFound)
        }
    }
    
    func refreshData() async {
        loadStoredLocation(fetchFresh: true)
        self.lastFetchDate = Date()
    }
    
    private func loadStoredLocation(fetchFresh: Bool) {
        let lat = UserDefaults.standard.double(forKey: "saved_lat")
        let lng = UserDefaults.standard.double(forKey: "saved_lng")
        let name = UserDefaults.standard.string(forKey: "saved_city_name") ?? "Seçilmedi"
        
        self.cityDisplay = name
        
        if lat != 0.0 || lng != 0.0 {
            if fetchFresh { Task { await fetchPrayerTimes(lat: lat, lng: lng) } }
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
        let urlString = "https://api.aladhan.com/v1/calendar?latitude=\(lat)&longitude=\(lng)&method=\(selectedMethodId)&month=\(month)&year=\(year)"
        
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
                self.lastFetchDate = Date()
            }
        } catch { print("API Error: \(error)") }
    }

    func updateDisplay() {
        guard let timings = UserDefaults.standard.dictionary(forKey: "timings") as? [String: String] else {
            self.cityDisplay = t(.loading)
            return
        }
        let now = Date()
        var targetDate: Date?
        var targetApiKey: String = ""
        
        for apiKey in apiKeyOrder {
            if let timeStr = timings[apiKey], let pDate = parseTime(timeStr) {
                let full = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: pDate),
                                                minute: Calendar.current.component(.minute, from: pDate),
                                                second: 0, of: now)!
                if full > now {
                    if targetDate == nil || full < targetDate! { targetDate = full; targetApiKey = apiKey }
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
            let nextName = getLocalizedTimeName(for: targetApiKey)
            let suffix = (selectedLanguage == .tr) ? getSuffix(for: nextName) : ""
            
            let h = diff / 3600
            let m = (diff % 3600) / 60
            
            self.nextEventDisplayName = "\(nextName)\(suffix)"
            
            let hStr = t(.timeRemainingHours)
            let mStr = t(.timeRemainingMins)
            let leftStr = t(.timeRemainingLeft)
            
            if h > 0 { self.timeRemainingString = "\(h) \(hStr) \(m) \(mStr) \(leftStr)" }
            else { self.timeRemainingString = "\(m) \(mStr) \(leftStr)" }
            
            if let targetIndex = apiKeyOrder.firstIndex(of: targetApiKey) {
                let currentIndex = (targetIndex - 1 + apiKeyOrder.count) % apiKeyOrder.count
                let currentKey = apiKeyOrder[currentIndex]
                self.currentEventApiKey = currentKey
                self.menuBarIcon = iconMap[currentKey] ?? "clock"
            }
            
            if diff <= 3600 {
                let minsLeft = (diff / 60) + 1
                self.menuBarText = "\(minsLeft) \(mStr)"
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
    
    private func getSuffix(for name: String) -> String {
        switch name {
        case "İmsak": return "a"; case "Güneş": return "e"; case "Öğle": return "ye"
        case "İkindi": return "ye"; case "Akşam": return "a"; case "Yatsı": return "ya"
        default: return ""
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
        
        for apiKey in apiKeyOrder {
            let displayName = getLocalizedTimeName(for: apiKey)
            
            guard let timeStr = timings[apiKey], let pDate = parseTime(timeStr), let setting = settings[apiKey] else { continue }
            let today = Calendar.current.startOfDay(for: Date())
            let fullDate = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: pDate),
                                                minute: Calendar.current.component(.minute, from: pDate),
                                                second: 0, of: today)!
            
            if setting.preReminder {
                let triggerDate = fullDate.addingTimeInterval(-TimeInterval(setting.preMinutes * 60))
                if triggerDate > Date() { sendNotification(id: "\(apiKey)_pre", title: displayName, body: t(.notificationPreBody), date: triggerDate) }
            }
            if setting.onTime && fullDate > Date() { sendNotification(id: "\(apiKey)_now", title: displayName, body: t(.notificationNowBody), date: fullDate) }
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
        else { for apiKey in apiKeyOrder { settings[apiKey] = PrayerSetting() } }
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
