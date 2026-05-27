import Foundation
import SwiftUI
import AudioToolbox

@MainActor
@Observable
final class StudySession: Identifiable {
    let id = UUID()

    var pomodoroDisplay: String = "25:00"
    var isOnBreak: Bool = false

    private var pomodoroEndDate: Date = .distantFuture
    private var timerTask: Task<Void, Never>?
    private let workDuration: TimeInterval = 25 * 60
    private let breakDuration: TimeInterval = 5 * 60
    private static let chimeSoundID: SystemSoundID = 1057

    init() {
        startWorkInterval()
    }

    func end() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func startWorkInterval() {
        isOnBreak = false
        pomodoroEndDate = Date().addingTimeInterval(workDuration)
        pomodoroDisplay = Self.formatTime(workDuration)
        scheduleTick()
    }

    private func startBreakInterval() {
        isOnBreak = true
        pomodoroEndDate = Date().addingTimeInterval(breakDuration)
        pomodoroDisplay = Self.formatTime(breakDuration)
        AudioServicesPlaySystemSound(Self.chimeSoundID)
    }

    private func scheduleTick() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func tick() {
        let remaining = pomodoroEndDate.timeIntervalSinceNow
        if remaining <= 0 {
            if isOnBreak {
                startWorkInterval()
            } else {
                startBreakInterval()
            }
            return
        }
        pomodoroDisplay = Self.formatTime(remaining)
    }

    private static func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(ceil(interval)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
