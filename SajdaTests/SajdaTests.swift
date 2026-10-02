import XCTest
import CoreLocation
@testable import Sajda

final class SajdaTests: XCTestCase {
    private let lookup = DiyanetLookup.shared
    private let timezone = TimeZone(identifier: "Europe/Istanbul")!

    func testProvinceListComesFromBundledJSON() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "TurkeyPrayerTimes", withExtension: "json"))
        let data = try JSONDecoder().decode([String: [String: DiyanetPrayerTimes]].self, from: Data(contentsOf: url))
        XCTAssertEqual(lookup.supportedProvinces.count, 81)
        XCTAssertEqual(Set(lookup.supportedProvinces.compactMap { lookup.findProvince(for: $0) }), Set(data.keys))
        XCTAssertEqual(lookup.provinces(matching: ""), lookup.supportedProvinces)
        for name in ["İstanbul", "Mardin", "Kayseri", "Afyonkarahisar", "Erzincan", "Osmaniye"] {
            XCTAssertTrue(lookup.supportedProvinces.contains(name), name)
        }
        for province in lookup.supportedProvinces {
            XCTAssertNotNil(lookup.getPrayerTimes(for: Date(), locationName: province, timezone: timezone), province)
        }
    }

    func testTurkishAndASCIIQueriesMatch() {
        for (ascii, turkish) in [("Istanbul", "İstanbul"), ("ISTANBUL", "istanbul"),
                                 ("Igdir", "Iğdır"), ("izmir", "İZMİR"),
                                 ("Sanliurfa", "Şanlıurfa"), ("Canakkale", "Çanakkale")] {
            XCTAssertEqual(lookup.provinces(matching: ascii), lookup.provinces(matching: turkish))
            XCTAssertEqual(lookup.getPrayerTimes(for: Date(), locationName: ascii, timezone: timezone),
                           lookup.getPrayerTimes(for: Date(), locationName: turkish, timezone: timezone))
        }
        XCTAssertEqual(lookup.provinces(matching: "  ist  "), ["İstanbul"])
        XCTAssertEqual(lookup.provinces(matching: "ığdır"), ["Iğdır"])
        XCTAssertTrue(lookup.provinces(matching: "London").isEmpty)
        for invalid in ["", " ", "ist", "London", "41,29"] {
            XCTAssertFalse(lookup.hasData(for: invalid), invalid)
        }
    }

    @MainActor
    func testFreshDefaultsAndOfflineProvincePersistence() throws {
        let defaults = UserDefaults.standard
        let keys = ["calculationMethodName", "isUsingManualLocation", "manualLocationData", "selectedProvince", "isNotificationsEnabled", "fajrCorrection", "dhuhrCorrection", "asrCorrection", "maghribCorrection", "ishaCorrection"]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = saved[key] ?? nil { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.set(false, forKey: "isNotificationsEnabled")

        let vm = PrayerTimeViewModel()
        XCTAssertEqual(vm.method.name, "Diyanet (Turkey)")
        vm.startLocationProcess()
        XCTAssertEqual(vm.locationStatusText, "İstanbul")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let today = calendar.startOfDay(for: Date())
        XCTAssertFalse(vm.needsPrayerTimeRefresh(at: today))
        XCTAssertTrue(vm.needsPrayerTimeRefresh(at: try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))))
        XCTAssertTrue(vm.isUsingProvinceLocation)
        XCTAssertEqual(vm.locationSearchResults.count, 81)
        vm.locationSearchQuery = "izmi"
        XCTAssertEqual(vm.locationSearchResults, ["İzmir"])
        vm.setManualProvince("Izmir")
        XCTAssertEqual(vm.locationStatusText, "İzmir")
        vm.setManualProvince("London")
        XCTAssertEqual(vm.locationStatusText, "İzmir")
        let restarted = PrayerTimeViewModel()
        restarted.startLocationProcess()
        XCTAssertEqual(restarted.locationStatusText, "İzmir")

        let scheduleReady = expectation(description: "Offline JSON prayer schedule")
        DispatchQueue.main.async {
            XCTAssertEqual(vm.todayTimes, self.lookup.getPrayerTimes(for: Date(), locationName: "İzmir", timezone: self.timezone))
            XCTAssertEqual(restarted.todayTimes.count, 6)
            let locationError = NSError(domain: kCLErrorDomain, code: CLError.locationUnknown.rawValue)
            vm.locationManager(CLLocationManager(), didFailWithError: locationError)
            XCTAssertEqual(vm.locationStatusText, "İzmir", "Automatic failures must not replace a manual province")
            XCTAssertEqual(vm.todayTimes.count, 6)
            vm.switchToAutomaticLocation()
            XCTAssertTrue(vm.todayTimes.isEmpty, "Do not show stale province times while resolving automatic location")
            XCTAssertEqual(vm.countdown, "--:--")
            vm.locationManager(CLLocationManager(), didFailWithError: locationError)
            XCTAssertTrue(vm.todayTimes.isEmpty)
            defaults.set(true, forKey: "isUsingManualLocation")
            defaults.set("London", forKey: "selectedProvince")
            restarted.startLocationProcess()
            XCTAssertEqual(restarted.locationStatusText, "Lütfen il seçin.")
            XCTAssertTrue(restarted.todayTimes.isEmpty, "Invalid saved provinces must not silently become İstanbul")
            scheduleReady.fulfill()
        }
        wait(for: [scheduleReady], timeout: 2)
    }
}
