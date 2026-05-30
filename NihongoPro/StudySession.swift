import Foundation
import SwiftUI
import AudioToolbox

@MainActor
@Observable
final class StudySession: Identifiable {
    let id = UUID()

    var pomodoroDisplay: String = "25:00"
    var isOnBreak: Bool = false
    /// Flips to true once the work + break cycle has completed. `ContentView`
    /// observes this to tear the session down (clear the pill + overlay).
    var isFinished: Bool = false

    private var pomodoroEndDate: Date = .distantFuture
    private var timerTask: Task<Void, Never>?
    private let workDuration: TimeInterval = 25 * 60
    private let breakDuration: TimeInterval = 5 * 60
    /// `1005` is the longer, more attention-grabbing system "alarm" tone (vs. the
    /// brief tri-tone). Played several times in a row so the end of a work block is
    /// hard to miss. System-sound volume tracks the device's ringer/system volume —
    /// it can't be boosted programmatically.
    private static let chimeSoundID: SystemSoundID = 1005
    private static let chimeRepeats = 3

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
        // The 25-minute work block just finished — credit a completed study session.
        ActivityTracker.shared.recordStudySession()
        isOnBreak = true
        pomodoroEndDate = Date().addingTimeInterval(breakDuration)
        pomodoroDisplay = Self.formatTime(breakDuration)
        Self.playChime(remaining: Self.chimeRepeats)
    }

    /// The work + break cycle is done — stop the timer and signal `ContentView` to
    /// dismiss. A single 25/5 pomodoro no longer loops into a new work block.
    private func finishSession() {
        isOnBreak = false
        isFinished = true
        timerTask?.cancel()
        timerTask = nil
    }

    /// Plays the chime `remaining` times back-to-back, chaining on each play's
    /// completion so the tones don't overlap.
    private static func playChime(remaining: Int) {
        guard remaining > 0 else { return }
        AudioServicesPlaySystemSoundWithCompletion(chimeSoundID) {
            playChime(remaining: remaining - 1)
        }
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
                finishSession()
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
