import AVFoundation
import MediaPlayer
import WebKit

// MARK: - Audio Session Manager
/// Configures AVAudioSession and media controls for browser playback.
@MainActor
final class AudioSessionManager: NSObject, ObservableObject {
    static let shared = AudioSessionManager()

    private weak var playbackWebView: WKWebView?
    private var remoteCommandsConfigured = false
    private var interruptionObserver: NSObjectProtocol?

    private override init() {
        super.init()
        observeInterruptions()
    }

    func attach(webView: WKWebView?) {
        playbackWebView = webView
        setupRemoteCommandsIfNeeded()
    }

    func configureForBrowserPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .allowBluetooth, .allowAirPlay]
            )
            try session.setActive(true)
        } catch {
            print("[CyberBrowser] AudioSession error: \(error.localizedDescription)")
        }
    }

    func updateNowPlaying(title: String?, url: URL?, isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title?.isEmpty == false ? title : "CyberBrowser"
        info[MPMediaItemPropertyAlbumTitle] = url?.host ?? "Browser Playback"
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[CyberBrowser] Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { [weak self] in
                await MainActor.run {
                    guard
                        let self,
                        let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                        let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                    else {
                        return
                    }

                    switch type {
                    case .ended:
                        self.configureForBrowserPlayback()
                        self.resumePlayback()
                    default:
                        break
                    }
                }
            }
        }
    }

    private func setupRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { [weak self] in
                await MainActor.run {
                    self?.playMedia()
                }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { [weak self] in
                await MainActor.run {
                    self?.pauseMedia()
                }
            }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { [weak self] in
                await MainActor.run {
                    self?.toggleMediaPlayback()
                }
            }
            return .success
        }
    }

    private func playMedia() {
        evaluateMediaScript("""
        document.querySelectorAll('video, audio').forEach(function(media) {
            try { media.play(); } catch (e) {}
        });
        """)
    }

    private func pauseMedia() {
        evaluateMediaScript("""
        window.__cyberbrowser_allow_pause = true;
        document.querySelectorAll('video, audio').forEach(function(media) {
            try { media.pause(); } catch (e) {}
        });
        """)
    }

    private func toggleMediaPlayback() {
        evaluateMediaScript("""
        document.querySelectorAll('video, audio').forEach(function(media) {
            try {
                if (media.paused) {
                    media.play();
                } else {
                    window.__cyberbrowser_allow_pause = true;
                    media.pause();
                }
            } catch (e) {}
        });
        """)
    }

    private func resumePlayback() {
        evaluateMediaScript("""
        document.querySelectorAll('video, audio').forEach(function(media) {
            if (media.paused) {
                try { media.play(); } catch (e) {}
            }
        });
        """)
    }

    private func evaluateMediaScript(_ script: String) {
        playbackWebView?.evaluateJavaScript(script) { _, error in
            if let error {
                print("[CyberBrowser] Media command error: \(error.localizedDescription)")
            }
        }
    }
}
