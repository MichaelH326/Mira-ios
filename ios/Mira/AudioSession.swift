import Foundation
import AVFoundation

/// The one place that configures the shared audio session.
///
/// Every engine used to set `.playAndRecord` with mode `.voiceChat`, which is
/// why Mira was quiet. That mode engages the voice-processing I/O unit: on a
/// phone it routes output at the *call* volume rather than the media volume,
/// and applies automatic gain control that pulls the level down further. It
/// buys echo cancellation, which matters when both ends talk at once — but
/// Mira is strictly turn-based. She speaks, then she listens. She is never
/// doing both, so the cancellation was doing nothing and the attenuation was
/// doing all of it.
///
/// So the session is switched per turn instead: plain `.playback` while she
/// speaks, which is as loud as iOS will play anything, and `.playAndRecord`
/// only while the microphone is actually open.
enum AudioSession {

    /// Configure for speaking. `.spokenAudio` is the mode built for this —
    /// it pauses rather than ducks other audio, which is right for a voice
    /// you are meant to listen to.
    static func beginPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio,
                                 options: [.duckOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Configure for listening. Mode `.default` rather than `.voiceChat` for
    /// the same reason: the processed input path costs level and gains
    /// nothing here, and `.measurement` would strip the gain the recognizer
    /// wants. The explicit speaker override is what stops iOS quietly
    /// choosing the earpiece once recording is live.
    static func beginRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        try? session.overrideOutputAudioPort(.speaker)
    }
}
