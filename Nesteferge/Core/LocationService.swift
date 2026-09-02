import CoreLocation
import Foundation
import Observation

/// Location + heading provider.
///
/// Heading policy matches the web app: prefer the GPS course while actually
/// moving (it reflects travel direction), otherwise fall back to the magnetic
/// compass, which is the only useful signal when stationary at a quay.
@Observable
@MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    enum LocationFailure: LocalizedError, Equatable {
        case denied
        case restricted
        case unavailable
        case timeout

        var errorDescription: String? {
            switch self {
            case .denied:
                return String(localized: "location.denied", defaultValue: "Location permission denied. Enable it to find your ferry.")
            case .restricted:
                return String(localized: "location.restricted", defaultValue: "Location access is restricted on this device.")
            case .unavailable:
                return String(localized: "location.unavailable", defaultValue: "Couldn't determine your position. Try again with a clear view of the sky.")
            case .timeout:
                return String(localized: "location.timeout", defaultValue: "Locating timed out. Please try again.")
            }
        }
    }

    struct Fix: Equatable {
        let latitude: Double
        let longitude: Double
        /// Compass degrees, `0..<360`, or nil when no trustworthy heading exists.
        let heading: Double?
    }

    /// Speeds below this (m/s) make the GPS course meaningless.
    private static let minimumCourseSpeed: CLLocationSpeed = 0.5
    private static let fixTimeout: Duration = .seconds(15)

    private let manager = CLLocationManager()
    private var compassHeading: CLLocationDirection?
    private var pendingFix: CheckedContinuation<Fix, Error>?
    private var timeoutTask: Task<Void, Never>?

    private(set) var authorizationStatus: CLAuthorizationStatus

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Start compass updates. Cheap, and gives us a heading before the first fix.
    func startCompass() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stopCompass() {
        manager.stopUpdatingHeading()
    }

    /// Requests authorization if needed, then resolves a single fix.
    func requestFix() async throws -> Fix {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied:
            throw LocationFailure.denied
        case .restricted:
            throw LocationFailure.restricted
        default:
            break
        }

        startCompass()

        // Only one outstanding request at a time; a second caller supersedes the first.
        if let pendingFix {
            self.pendingFix = nil
            pendingFix.resume(throwing: CancellationError())
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingFix = continuation
            manager.requestLocation()
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.fixTimeout)
                guard !Task.isCancelled else { return }
                // Task inherits this method's main-actor isolation, so no hop needed.
                self?.failPendingFix(with: .timeout)
            }
        }
    }

    // MARK: - Continuation plumbing

    private func finishPendingFix(with fix: Fix) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation = pendingFix else { return }
        pendingFix = nil
        continuation.resume(returning: fix)
    }

    private func failPendingFix(with failure: LocationFailure) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation = pendingFix else { return }
        pendingFix = nil
        continuation.resume(throwing: failure)
    }

    private func heading(for location: CLLocation) -> Double? {
        if location.course >= 0, location.speed > Self.minimumCourseSpeed {
            return location.course
        }
        if let compassHeading, compassHeading >= 0 {
            return compassHeading
        }
        return nil
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .denied:
                self.failPendingFix(with: .denied)
            case .restricted:
                self.failPendingFix(with: .restricted)
            case .authorizedWhenInUse, .authorizedAlways:
                // Authorization can land after `requestLocation()` was ignored, so retry.
                if self.pendingFix != nil {
                    self.startCompass()
                    manager.requestLocation()
                }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            let fix = Fix(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                heading: self.heading(for: location)
            )
            self.finishPendingFix(with: fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.compassHeading = value >= 0 ? value : nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let failure: LocationFailure = (error as? CLError)?.code == .denied ? .denied : .unavailable
        Task { @MainActor in
            self.failPendingFix(with: failure)
        }
    }
}
