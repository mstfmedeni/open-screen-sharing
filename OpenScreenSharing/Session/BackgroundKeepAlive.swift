#if os(iOS)
import Foundation
import UIKit

/// How long a session stays connected while the app is in the background.
enum BackgroundConnection: String, Codable, CaseIterable, Identifiable {
    /// As long as iOS lets the app finish what it's doing, usually about half a minute.
    case system
    case tenMinutes
    case thirtyMinutes
    case oneHour
    case always

    var id: Self { self }

    var title: String.LocalizationValue {
        switch self {
        case .system: "Briefly"
        case .tenMinutes: "10 Minutes"
        case .thirtyMinutes: "30 Minutes"
        case .oneHour: "1 Hour"
        case .always: "Until Disconnected"
        }
    }

    /// The time limit, or nil for none.
    var duration: TimeInterval? {
        switch self {
        case .system: 0
        case .tenMinutes: 10 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .always: nil
        }
    }
}

/// Keeps a session's app running in the background by playing silence, so its connection stays open for as long
/// as BackgroundConnection allows, rather than the half minute iOS gives otherwise. Silence mixes with other audio
/// and doesn't take over Now Playing. While in the background, the session receives no pictures, so it uses little
/// data.
final class BackgroundKeepAlive {
    private let audio = BackgroundAudio()
    private var expiry: Task<Void, Never>?
    nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []
    /// Asked on entering the background whether there's a session worth keeping.
    var isWanted: () -> Bool = { false }
    /// Called when the time allowed runs out, to let the session go the usual way.
    var onExpiry: () -> Void = {}

    var isActive: Bool { expiry != nil || audio.isPlaying }

    init() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appDidEnterBackground() }
            })
        observers.append(
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        MainActor.assumeIsolated { stop() }
    }

    private func appDidEnterBackground() {
        let setting = AppSettings.shared.backgroundConnection
        guard setting != .system, isWanted() else { return }
        audio.start()
        guard let duration = setting.duration else {
            expiry = Task {}
            return
        }
        expiry = Task { [weak self] in
            try? await Task.sleep(seconds: duration)
            guard !Task.isCancelled, let self else { return }
            self.stop()
            self.onExpiry()
        }
    }

    func stop() {
        expiry?.cancel()
        expiry = nil
        audio.stop()
    }
}
#endif
