// MARK: - GANTI SELURUH FILE: PrayerTimeViewModel.swift

import Foundation
import Combine
import Adhan
import CoreLocation
import SwiftUI
import AppKit
import NavigationStack

class PrayerTimeViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var menuTitle: NSAttributedString = NSAttributedString(string: "Sajda Pro")
    @Published var todayTimes: [String: Date] = [:]
    @Published var nextPrayerName: String = ""
    @Published var countdown: String = "--:--"
    @Published var locationStatusText: String = "Preparing prayer schedule..."
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var locationSearchQuery: String = ""
    @Published var locationSearchResults: [String] = []
    @Published var locationInfoText: String = ""
    @Published var isPrayerImminent: Bool = false
    @Published var isRequestingLocation: Bool = false

    private let languageManager = LanguageManager()
    private var automaticLocationCache: (name: String, coordinates: CLLocationCoordinate2D)?
    private var tomorrowFajrTime: Date?

    @AppStorage("animationType") var animationType: AnimationType = .fade
    @AppStorage("useMinimalMenuBarText") var useMinimalMenuBarText: Bool = false { didSet { updateAndDisplayTimes() } }
    @AppStorage("showSunnahPrayers") var showSunnahPrayers: Bool = false { didSet { updatePrayerTimes() } }
    @AppStorage("useAccentColor") var useAccentColor: Bool = true
    @AppStorage("isNotificationsEnabled") var isNotificationsEnabled: Bool = true { didSet { updateNotifications() } }
    @AppStorage("useCompactLayout") var useCompactLayout: Bool = false
    @AppStorage("use24HourFormat") var use24HourFormat: Bool = false { didSet { updateAndDisplayTimes() } }
    @AppStorage("useHanafiMadhhab") var useHanafiMadhhab: Bool = false { didSet { updatePrayerTimes() } }
    @AppStorage("isUsingManualLocation") var isUsingManualLocation: Bool = true
    @AppStorage("fajrCorrection") var fajrCorrection: Double = 0 { didSet { updatePrayerTimes() } }
    @AppStorage("dhuhrCorrection") var dhuhrCorrection: Double = 0 { didSet { updatePrayerTimes() } }
    @AppStorage("asrCorrection") var asrCorrection: Double = 0 { didSet { updatePrayerTimes() } }
    @AppStorage("maghribCorrection") var maghribCorrection: Double = 0 { didSet { updatePrayerTimes() } }
    @AppStorage("ishaCorrection") var ishaCorrection: Double = 0 { didSet { updatePrayerTimes() } }
    @AppStorage("adhanSound") var adhanSound: AdhanSound = .defaultBeep { didSet { updateNotifications() } }
    @AppStorage("customAdhanSoundPath") var customAdhanSoundPath: String = "" { didSet { updateNotifications() } }

    @Published var menuBarTextMode: MenuBarTextMode {
        didSet {
            UserDefaults.standard.set(menuBarTextMode.rawValue, forKey: "menuBarTextMode")
            if menuBarTextMode == .hidden { useMinimalMenuBarText = false }
            updateMenuTitle()
        }
    }
    
    @Published var method: SajdaCalculationMethod { didSet { UserDefaults.standard.set(method.name, forKey: "calculationMethodName"); updatePrayerTimes() } }
    private var currentCoordinates: CLLocationCoordinate2D?
    private var cancellables = Set<AnyCancellable>()
    private let locMgr = CLLocationManager()
    private var timer: Timer?
    private var adhanPlayer: NSSound?
    private var locationTimeZone: TimeZone = .current
    private var locationDisplayTimer: Timer?
    private var lastCalculationDate: Date?


    override init() {
        let savedMethodName = UserDefaults.standard.string(forKey: "calculationMethodName") ?? "Diyanet (Turkey)"
        self.method = SajdaCalculationMethod.allCases.first { $0.name == savedMethodName } ?? SajdaCalculationMethod.allCases.first { $0.name == "Diyanet (Turkey)" }!
        let savedTextMode = UserDefaults.standard.string(forKey: "menuBarTextMode")
        self.menuBarTextMode = MenuBarTextMode(rawValue: savedTextMode ?? "") ?? .countdown
        self.authorizationStatus = locMgr.authorizationStatus
        super.init()
        locMgr.delegate = self
        startTimer()
        setupSearchPublisher()
    }
    
    func forwardAnimation() -> NavigationAnimation? {
        switch animationType {
        case .none: return nil
        case .fade: return .sajdaCrossfade
        case .slide: return .push
        }
    }
    
    func backwardAnimation() -> NavigationAnimation? {
        switch animationType {
        case .none: return nil
        case .fade: return .sajdaCrossfade
        case .slide: return .pop
        }
    }
    
    private func setupSearchPublisher() {
        $locationSearchQuery
            .removeDuplicates()
            .sink { [weak self] query in
                self?.locationSearchResults = DiyanetLookup.shared.provinces(matching: query)
            }
            .store(in: &cancellables)
    }
    
    func setManualProvince(_ name: String) {
        guard let province = DiyanetLookup.shared.findProvince(for: name) else { return }
        locationStatusText = province.capitalized(with: Locale(identifier: "tr_TR"))
        UserDefaults.standard.set(locationStatusText, forKey: "selectedProvince")
        isUsingManualLocation = true
        currentCoordinates = nil
        locationTimeZone = TimeZone(identifier: "Europe/Istanbul")!
        authorizationStatus = .authorized
        if method.name != "Diyanet (Turkey)" {
            method = SajdaCalculationMethod.allCases.first { $0.name == "Diyanet (Turkey)" }!
        }
        locationSearchQuery = ""
        updateAndDisplayTimes()
    }

    var isUsingProvinceLocation: Bool { isUsingManualLocation && currentCoordinates == nil }
    
    func startLocationProcess() {
        if isUsingManualLocation,
           let province = UserDefaults.standard.string(forKey: "selectedProvince") {
            if DiyanetLookup.shared.hasData(for: province) {
                setManualProvince(province)
            } else {
                clearPrayerTimes()
                locationStatusText = "Lütfen il seçin."
            }
        } else if isUsingManualLocation, let manualData = loadManualLocation() {
            currentCoordinates = manualData.coordinates
            locationStatusText = manualData.name
            let location = CLLocation(latitude: manualData.coordinates.latitude, longitude: manualData.coordinates.longitude)
            self.locationTimeZone = TimeZoneLocate.timeZoneWithLocation(location)
            self.authorizationStatus = .authorized
            DispatchQueue.main.async {
                self.updateAndDisplayTimes()
            }
        } else if isUsingManualLocation {
            setManualProvince("İstanbul")
        } else {
            self.locationTimeZone = .current
            handleAuthorizationStatus(status: locMgr.authorizationStatus)
        }
    }
    
    private func loadManualLocation() -> (name: String, coordinates: CLLocationCoordinate2D)? { guard let data = UserDefaults.standard.dictionary(forKey: "manualLocationData"), let name = data["name"] as? String, let lat = data["latitude"] as? CLLocationDegrees, let lon = data["longitude"] as? CLLocationDegrees else { return nil }; return (name, CLLocationCoordinate2D(latitude: lat, longitude: lon)) }
    func switchToAutomaticLocation() {
        isUsingManualLocation = false
        clearPrayerTimes()
        UserDefaults.standard.removeObject(forKey: "manualLocationData")
        if let cache = automaticLocationCache {
            currentCoordinates = cache.coordinates
            locationStatusText = cache.name
            locationTimeZone = TimeZoneLocate.timeZoneWithLocation(CLLocation(latitude: cache.coordinates.latitude, longitude: cache.coordinates.longitude))
            updateAndDisplayTimes()
        } else {
            handleAuthorizationStatus(status: locMgr.authorizationStatus)
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locs: [CLLocation]) { guard let location = locs.last else { return }; let geocoder = CLGeocoder(); geocoder.reverseGeocodeLocation(location) { (placemarks, _) in DispatchQueue.main.async { guard let locality = placemarks?.first?.locality else { self.isRequestingLocation = false; return }; self.automaticLocationCache = (name: locality, coordinates: location.coordinate); if !self.isUsingManualLocation { self.currentCoordinates = location.coordinate; self.locationStatusText = locality; self.locationTimeZone = placemarks?.first?.timeZone ?? TimeZoneLocate.timeZoneWithLocation(location); self.updateAndDisplayTimes() }; if self.isRequestingLocation { self.isRequestingLocation = false } } } }
    private func updateAndDisplayTimes() { updatePrayerTimes(); if isUsingManualLocation { startLocationDisplayTimer() } else { stopLocationDisplayTimer() } }
    
    func updatePrayerTimes() {
        lastCalculationDate = Date()
        
        var locationCalendar = Calendar(identifier: .gregorian); locationCalendar.timeZone = self.locationTimeZone
        let todayInLocation = locationCalendar.dateComponents([.year, .month, .day], from: Date())
        let tomorrowInLocation = locationCalendar.date(byAdding: .day, value: 1, to: Date())!
        let tomorrowDC = locationCalendar.dateComponents([.year, .month, .day], from: tomorrowInLocation)
        // Check if we should use Diyanet lookup for Turkish cities
        let isDiyanet = method.name == "Diyanet (Turkey)"
        let hasDiyanetData = DiyanetLookup.shared.hasData(for: locationStatusText)
        
        var allPrayerTimes: [(name: String, time: Date)]
        var correctedFajrTomorrow: Date
        
        if isDiyanet && hasDiyanetData,
           let diyanetTimes = DiyanetLookup.shared.getPrayerTimes(for: Date(), locationName: locationStatusText, timezone: self.locationTimeZone),
           let diyanetTomorrowTimes = DiyanetLookup.shared.getPrayerTimes(for: tomorrowInLocation, locationName: locationStatusText, timezone: self.locationTimeZone) {
            // Use official Diyanet lookup times for supported Turkish cities
            // Apply user's manual corrections on top of official times
            allPrayerTimes = [
                ("Fajr", diyanetTimes["Fajr"]!.addingTimeInterval(fajrCorrection * 60)),
                ("Sunrise", diyanetTimes["Sunrise"]!),
                ("Dhuhr", diyanetTimes["Dhuhr"]!.addingTimeInterval(dhuhrCorrection * 60)),
                ("Asr", diyanetTimes["Asr"]!.addingTimeInterval(asrCorrection * 60)),
                ("Maghrib", diyanetTimes["Maghrib"]!.addingTimeInterval(maghribCorrection * 60)),
                ("Isha", diyanetTimes["Isha"]!.addingTimeInterval(ishaCorrection * 60))
            ]
            correctedFajrTomorrow = diyanetTomorrowTimes["Fajr"]!.addingTimeInterval(fajrCorrection * 60)
        } else {
            guard let coord = currentCoordinates else {
                clearPrayerTimes()
                return
            }
            var params = method.params; params.madhab = self.useHanafiMadhhab ? .hanafi : .shafi
            guard let prayersToday = PrayerTimes(coordinates: Coordinates(latitude: coord.latitude, longitude: coord.longitude), date: todayInLocation, calculationParameters: params),
                  let prayersTomorrow = PrayerTimes(coordinates: Coordinates(latitude: coord.latitude, longitude: coord.longitude), date: tomorrowDC, calculationParameters: params) else { return }

            if isDiyanet {
                // Unsupported automatic locations use calculated times with Sunrise.
                let correctedFajr = prayersToday.fajr.addingTimeInterval(fajrCorrection * 60)
                let correctedDhuhr = prayersToday.dhuhr.addingTimeInterval(dhuhrCorrection * 60)
                let correctedAsr = prayersToday.asr.addingTimeInterval(asrCorrection * 60)
                let correctedMaghrib = prayersToday.maghrib.addingTimeInterval(maghribCorrection * 60)
                let correctedIsha = prayersToday.isha.addingTimeInterval(ishaCorrection * 60)
            
                allPrayerTimes = [
                    ("Fajr", correctedFajr),
                    ("Sunrise", prayersToday.sunrise),
                    ("Dhuhr", correctedDhuhr),
                    ("Asr", correctedAsr),
                    ("Maghrib", correctedMaghrib),
                    ("Isha", correctedIsha)
                ]
                correctedFajrTomorrow = prayersTomorrow.fajr.addingTimeInterval(fajrCorrection * 60)
            } else {
                // Use calculated times with manual corrections
                let correctedFajr = prayersToday.fajr.addingTimeInterval(fajrCorrection * 60)
                let correctedDhuhr = prayersToday.dhuhr.addingTimeInterval(dhuhrCorrection * 60)
                let correctedAsr = prayersToday.asr.addingTimeInterval(asrCorrection * 60)
                let correctedMaghrib = prayersToday.maghrib.addingTimeInterval(maghribCorrection * 60)
                let correctedIsha = prayersToday.isha.addingTimeInterval(ishaCorrection * 60)
            
                allPrayerTimes = [("Fajr", correctedFajr), ("Dhuhr", correctedDhuhr), ("Asr", correctedAsr), ("Maghrib", correctedMaghrib), ("Isha", correctedIsha)]

                if showSunnahPrayers {
                    correctedFajrTomorrow = prayersTomorrow.fajr.addingTimeInterval(fajrCorrection * 60)
                    let nightDuration = correctedFajrTomorrow.timeIntervalSince(correctedIsha)
                    let lastThirdOfNightStart = correctedIsha.addingTimeInterval(nightDuration * (2/3.0))
                    allPrayerTimes.append(("Tahajud", lastThirdOfNightStart))

                    let dhuhaTime = prayersToday.sunrise.addingTimeInterval(20 * 60)
                    allPrayerTimes.append(("Dhuha", dhuhaTime))
                }

                correctedFajrTomorrow = prayersTomorrow.fajr.addingTimeInterval(fajrCorrection * 60)
            }
        }
        
        DispatchQueue.main.async {
            self.todayTimes = Dictionary(uniqueKeysWithValues: allPrayerTimes.map { ($0.name, $0.time) })
            self.tomorrowFajrTime = correctedFajrTomorrow
            self.updateNextPrayer()
            self.updateNotifications()
        }
    }
    
    private func updateNextPrayer() {
        let now = Date()
        var potentialPrayers = todayTimes.map { (key: $0.key, value: $0.value) }
        if let fajrTomorrow = tomorrowFajrTime {
            potentialPrayers.append((key: "Fajr", value: fajrTomorrow))
        }
        let allSortedPrayers = potentialPrayers.sorted { $0.value < $1.value }
        let listToSearch: [(key: String, value: Date)]
        if showSunnahPrayers {
            listToSearch = allSortedPrayers
        } else {
            listToSearch = allSortedPrayers.filter { $0.key != "Tahajud" && $0.key != "Dhuha" }
        }
        
        if let nextPrayer = listToSearch.first(where: { $0.value > now }) {
            self.nextPrayerName = nextPrayer.key
        } else {
            if let firstPrayerOfNextCycle = listToSearch.first {
                self.nextPrayerName = firstPrayerOfNextCycle.key
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.updatePrayerTimes()
                }
            }
        }
        updateCountdown()
    }
    
    private func updateCountdown() {
        var nextPrayerDate: Date?
        if nextPrayerName == "Fajr" && todayTimes["Fajr"] ?? Date() < Date() {
            nextPrayerDate = tomorrowFajrTime
        } else {
            nextPrayerDate = todayTimes[nextPrayerName]
        }
        
        guard let nextDate = nextPrayerDate else {
            countdown = "--:--"; updateMenuTitle(); return
        }
        
        let diff = Int(nextDate.timeIntervalSince(Date()))
        isPrayerImminent = (diff <= 600 && diff > 0)
        
        if diff > 0 {
            let h = diff / 3600
            let m = (diff % 3600) / 60
            let numberFormatter = NumberFormatter()
            numberFormatter.locale = Locale(identifier: languageManager.language)
            let formattedM = numberFormatter.string(from: NSNumber(value: m + 1)) ?? "\(m + 1)"
            if h > 0 {
                let formattedH = numberFormatter.string(from: NSNumber(value: h)) ?? "\(h)"
                countdown = "\(formattedH)h \(formattedM)m"
            } else {
                countdown = "\(formattedM)m"
            }
        } else {
            countdown = "Now"
            if adhanSound == .custom, let soundPath = customAdhanSoundPath.removingPercentEncoding, let soundURL = URL(string: soundPath), FileManager.default.fileExists(atPath: soundURL.path) {
                adhanPlayer = NSSound(contentsOf: soundURL, byReference: true)
                adhanPlayer?.play()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.updateNextPrayer() }
        }
        updateMenuTitle()
    }
    
    func updateMenuTitle() { guard isPrayerDataAvailable else { self.menuTitle = NSAttributedString(string: "Sajda Pro"); return }; var textToShow = ""; let localizedPrayerName = NSLocalizedString(nextPrayerName, comment: ""); switch menuBarTextMode { case .hidden: textToShow = ""; case .countdown: if useMinimalMenuBarText { textToShow = "\(localizedPrayerName) -\(countdown)" } else { textToShow = String(format: NSLocalizedString("prayer_in_countdown", comment: ""), localizedPrayerName, countdown) }; case .exactTime: var nextPrayerDate: Date?; if nextPrayerName == "Fajr" && todayTimes["Fajr"] ?? Date() < Date() { nextPrayerDate = tomorrowFajrTime } else { nextPrayerDate = todayTimes[nextPrayerName] }; guard let nextDate = nextPrayerDate else { textToShow = "Sajda Pro"; break }; if useMinimalMenuBarText { textToShow = "\(localizedPrayerName) \(dateFormatter.string(from: nextDate))" } else { textToShow = String(format: NSLocalizedString("prayer_at_time", comment: ""), localizedPrayerName, dateFormatter.string(from: nextDate)) } }; let attributes: [NSAttributedString.Key: Any] = isPrayerImminent ? [.foregroundColor: NSColor.systemRed] : [:]; self.menuTitle = NSAttributedString(string: textToShow, attributes: attributes) }
    
    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = self.locationTimeZone
        formatter.locale = Locale(identifier: languageManager.language)
        if useMinimalMenuBarText {
            formatter.dateFormat = use24HourFormat ? "H.mm" : "h.mm"
        } else {
            formatter.dateFormat = use24HourFormat ? "HH:mm" : "h:mm a"
        }
        return formatter
    }
    
    private func startLocationDisplayTimer() { stopLocationDisplayTimer(); locationDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in guard let self = self else { return }; let timeFormatter = self.dateFormatter; timeFormatter.dateFormat = self.use24HourFormat ? "HH:mm:ss" : "h:mm:ss a"; let tzName = self.locationTimeZone.identifier; let currentTime = timeFormatter.string(from: Date()); self.locationInfoText = "Timezone: \(tzName) | Current Time: \(currentTime)" } }
    private func stopLocationDisplayTimer() { locationDisplayTimer?.invalidate(); locationDisplayTimer = nil; locationInfoText = "" }
    
    private func updateNotifications() {
        guard isNotificationsEnabled, !todayTimes.isEmpty else {
            NotificationManager.cancelNotifications()
            return
        }
        NotificationManager.requestPermission()
        var prayersToNotify = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        if showSunnahPrayers {
            if todayTimes.keys.contains("Tahajud") { prayersToNotify.append("Tahajud") }
            if todayTimes.keys.contains("Dhuha") { prayersToNotify.append("Dhuha") }
        }
        NotificationManager.scheduleNotifications(for: todayTimes, prayerOrder: prayersToNotify, adhanSound: self.adhanSound, customSoundPath: self.customAdhanSoundPath)
    }
    
    func selectCustomAdhanSound() { let openPanel = NSOpenPanel(); openPanel.canChooseFiles = true; openPanel.canChooseDirectories = false; openPanel.allowsMultipleSelection = false; openPanel.allowedContentTypes = [.audio]; if openPanel.runModal() == .OK { self.customAdhanSoundPath = openPanel.url?.absoluteString ?? "" } }
    var isPrayerDataAvailable: Bool { !todayTimes.isEmpty }
    
    func needsPrayerTimeRefresh(at date: Date) -> Bool {
        guard let lastDate = lastCalculationDate else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = locationTimeZone
        return !calendar.isDate(lastDate, inSameDayAs: date)
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.needsPrayerTimeRefresh(at: Date()) {
                self.updatePrayerTimes()
            } else {
                self.updateCountdown()
            }
        }
    }
    
    private func clearPrayerTimes() {
        currentCoordinates = nil
        todayTimes = [:]
        tomorrowFajrTime = nil
        nextPrayerName = ""
        isPrayerImminent = false
        updateCountdown()
        updateNotifications()
    }

    private func handleAuthorizationStatus(status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            if automaticLocationCache == nil { locationStatusText = "Fetching Location..." }
            locMgr.requestLocation()
        case .denied, .restricted:
            clearPrayerTimes()
            locationStatusText = "Location access denied."
            isRequestingLocation = false
        case .notDetermined:
            clearPrayerTimes()
            isRequestingLocation = false
            locationStatusText = "Location access needed"
        @unknown default:
            isRequestingLocation = false
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if !isUsingManualLocation { handleAuthorizationStatus(status: manager.authorizationStatus) } }
    
    // --- PERBAIKAN TYPO DI SINI ---
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard !isUsingManualLocation else { return }
        clearPrayerTimes()
        self.isRequestingLocation = false
        self.locationStatusText = "Unable to determine location."
    }
    
    func requestLocationPermission() { if authorizationStatus == .notDetermined { isRequestingLocation = true; DispatchQueue.main.async { self.locMgr.requestWhenInUseAuthorization() } } }
    func openLocationSettings() { guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }; NSWorkspace.shared.open(url) }
}
