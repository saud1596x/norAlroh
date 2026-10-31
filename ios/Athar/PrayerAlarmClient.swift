import Foundation
import AlarmKit
import ActivityKit
import SwiftUI

enum PrayerAuthorizationState: String { case notDetermined, authorized, denied, unavailable }

struct ScheduledPrayerAlarm {
    let id: UUID
    let fireDate: Date?
}

@MainActor protocol PrayerAlarmClient {
    var available: Bool { get }
    var fixedSoundAvailable: Bool { get }
    func authorizationStatus() -> PrayerAuthorizationState
    func requestAuthorization() async throws -> PrayerAuthorizationState
    func currentAlarms() throws -> [ScheduledPrayerAlarm]
    func schedule(id: UUID, event: FixedPrayerEvent) async throws
    func cancel(id: UUID) throws
}
extension PrayerAlarmClient { var fixedSoundAvailable: Bool { true } }

@available(iOS 26.0, *)
private struct NoorPrayerAlarmMetadata: AlarmMetadata {}

/// The iOS17 deployment target is unchanged. All AlarmKit calls are isolated
/// behind availability checks; older systems use ordinary UN notifications.
@MainActor final class SystemPrayerAlarmClient: PrayerAlarmClient {
    var available: Bool { if #available(iOS 26.0, *) { return true }; return false }
    var fixedSoundAvailable: Bool { PrayerAlertSound.isValid() }
    func authorizationStatus() -> PrayerAuthorizationState {
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .notDetermined: return .notDetermined
            case .authorized: return .authorized
            case .denied: return .denied
            @unknown default: return .unavailable
            }
        }
        return .unavailable
    }
    func requestAuthorization() async throws -> PrayerAuthorizationState {
        if #available(iOS 26.0, *) {
            _ = try await AlarmManager.shared.requestAuthorization()
            return authorizationStatus()
        }
        return .unavailable
    }
    func currentAlarms() throws -> [ScheduledPrayerAlarm] {
        if #available(iOS 26.0, *) {
            return try AlarmManager.shared.alarms.map { alarm in
                var date: Date?
                if case .fixed(let fixed)? = alarm.schedule { date = fixed }
                return .init(id: alarm.id, fireDate: date)
            }
        }
        return []
    }
    func schedule(id: UUID, event: FixedPrayerEvent) async throws {
        if #available(iOS 26.0, *) {
            // This initializer is supported by SDK26.0; the custom stop label
            // is deprecated starting26.1, where the system supplies the control.
            let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: event.title),
                stopButton: AlarmButton(text: "إيقاف", textColor: .white, systemImageName: "stop.fill"))
            let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                metadata: NoorPrayerAlarmMetadata(), tintColor: Color(red: 0.12, green: 0.34, blue: 0.27))
            // No countdown/paused UI or snooze. AlarmKit's stop control stops
            // this one-shot event; reconciliation never recreates removed IDs.
            let sound: AlertConfiguration.AlertSound = PrayerAlertSound.isValid()
                ? .named(PrayerAlertSound.filename) : .default
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(event.fireDate), attributes: attributes, sound: sound)
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        } else { throw CocoaError(.featureUnsupported) }
    }
    func cancel(id: UUID) throws {
        if #available(iOS 26.0, *) { try AlarmManager.shared.cancel(id: id) }
    }
}

struct PrayerAlarmRecord: Codable {
    enum State: String, Codable {
        case pending, scheduled, observedRemoved, cancelled, retryable, expired
    }
    let id: UUID
    var fireDate: Date
    var state: State
}
