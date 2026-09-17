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
    /// The end-of-work chime sequence; deliberately not cancelled by `end()` so the
    /// tones finish even if the user dismisses the session mid-chime.
    private var chimeTask: Task<Void, Never>?
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
        playChimes()
    }

    /// The work + break cycle is done — stop the timer and signal `ContentView` to
    /// dismiss. A single 25/5 pomodoro no longer loops into a new work block.
    private func finishSession() {
        isOnBreak = false
        isFinished = true
        timerTask?.cancel()
        timerTask = nil
    }

    /// Plays the chime `chimeRepeats` times back-to-back. Each play is awaited to
    /// completion so the tones don't overlap; the C completion block only resumes a
    /// continuation, so nothing re-enters this main-actor class from a foreign thread.
    private func playChimes() {
        chimeTask?.cancel()
        chimeTask = Task {
            for _ in 0..<Self.chimeRepeats {
                if Task.isCancelled { return }
                await Self.playSystemSoundOnce(Self.chimeSoundID)
            }
        }
    }

    private static func playSystemSoundOnce(_ soundID: SystemSoundID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            AudioServicesPlaySystemSoundWithCompletion(soundID) {
                continuation.resume()
            }
        }
    }

    private func scheduleTick() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                // Wake just past the next whole-second boundary of the countdown, so
                // the mm:ss display changes exactly once per wake (it used to poll
                // every 500 ms for a value that changes once a second).
                let remaining = self.pomodoroEndDate.timeIntervalSinceNow
                let fraction = remaining - floor(remaining)
                try? await Task.sleep(for: .seconds(max(0.05, fraction + 0.01)))
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
        return Duration.seconds(total).formatted(.time(pattern: .minuteSecond))
    }
}
