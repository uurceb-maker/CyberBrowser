import AVFoundation

// MARK: - Audio Session Manager
/// Configures AVAudioSession for background audio/video playback
class AudioSessionManager {
    static let shared = AudioSessionManager()
    
    private init() {}
    
    func configureBackgroundAudio() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .allowAirPlay]
            )
            try audioSession.setActive(true)
            print("[CyberBrowser] Background audio configured successfully")
        } catch {
            print("[CyberBrowser] Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[CyberBrowser] Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
}
