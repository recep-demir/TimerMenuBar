# PrayerTimer for macOS

**PrayerTimer** is a lightweight, native macOS menu bar application designed to help you track Islamic prayer times seamlessly throughout your day. Built with SwiftUI, it provides real-time countdowns, location-based prayer timings, and notification reminders without interrupting your workflow.

## Features

* **Live Menu Bar Display:** View the remaining time to the next prayer directly in your menu bar (shows countdown when less than 60 minutes remain).
* **Dynamic Icons:** The menu bar icon automatically changes to reflect the current prayer (e.g., Sun for Dhuhr, Moon for Isha).
* **Location-Based Timings:** Search for any city globally. The app uses `CoreLocation` and the **Aladhan API** to fetch accurate timings.
* **Dual Calendar Support:** View both Gregorian and Hijri dates at a glance.
* **Smart Notifications:**
* **Pre-reminder:** Get notified 35 minutes before a prayer starts.
* **On-time:** Get notified exactly when it's time to pray.


* **Native Experience:** A clean, modern UI that respects macOS system themes (Light/Dark mode) and uses high-quality SF Symbols.

## 🛠 Tech Stack

* **Language:** Swift 6.0+
* **Framework:** SwiftUI
* **API:** [Aladhan Prayer Times API](https://aladhan.com/prayer-times-api)
* **Platform:** macOS 14.0+

## 📸 Screenshots

| Menu View | Location Settings |
| --- | --- |
|  |  |

## Installation

Since this is an open-source Swift project, you can build it directly from the source:

1. **Clone the repository:**
```bash
git clone https://github.com/username/PrayerTimer.git

```


2. **Open the project:**
Double-click `PrayerTimer.xcodeproj` to open it in Xcode.
3. **Select Target:**
Ensure the target is set to **My Mac**.
4. **Run:**
Press `Cmd + R` to build and run the application.

## How to Use

1. **Set Your Location:** Upon first launch, click on the menu bar icon, select **"Change Location"** (Konum Değiştir), and type your city (e.g., "Luzern" or "Istanbul").
2. **View Times:** Simply click the menu bar icon to see all prayer times for the day, along with the current date and Hijri calendar.
3. **Manage Notifications:** Expand any prayer time in the menu to toggle "Pre-reminder" or "On-time" notifications.
4. **Update Manually:** Use the **"Refresh"** button to fetch the latest data if you change locations or dates.

## ⚙️ Configuration

The app uses the **Turkey Diyanet (Method 13)** calculation method by default, which is widely accepted in Europe and Turkey. This can be modified in the `PrayerTimerManager.swift` file by changing the `method` parameter in the API URL.

## 🤝 Contributing

Contributions are welcome! If you have a feature request or found a bug, please open an issue or submit a pull request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](https://www.google.com/search?q=LICENSE) file for details.

## ✉️ Contact

Recep Demir - [recep.demir@powercoders.org](mailto:recep.demir@powercoders.org)

Project Link: [https://github.com/recep-demir/timermenubar](https://www.google.com/search?q=https://github.com/recep-demir/timermenubar)

---

### README dosyasını kullanırken dikkat etmen gerekenler:

* **Screenshot linkleri:** `https://via.placeholder.com` yazan yerlere uygulamanın ekran görüntülerini ekleyip linklerini güncellersen çok daha etkileyici durur.
* **GitHub Linki:** En alttaki iletişim ve link kısmını kendi bilgilerine göre teyit ettim, bir değişiklik istersen yapabilirsin.
