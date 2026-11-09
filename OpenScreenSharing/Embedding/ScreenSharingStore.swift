#if EMBEDDED && os(iOS)
import Foundation
import Observation
import SwiftUI
import UIKit

/// Holds the screen sharing session of an app that embeds this one as ScreenSharingKit.
///
/// The session lives here rather than in a view, so the host can take its view away, as when someone switches to
/// another tab, and bring it back to the same session. While no view shows it, the session goes quiet the way it
/// does in the background: the computer stops sending pictures, and the connection stays open.
@available(iOS 17, *)
@MainActor
@Observable
public final class ScreenSharingStore {
    public static let shared = ScreenSharingStore()

    /// The session, connected or on its way, while there is one.
    private(set) var controller: SessionController?
    /// Whether a ScreenSharingView is on screen.
    @ObservationIgnored private var visibleViews = 0
    @ObservationIgnored let nearby: NearbyBrowser
    @ObservationIgnored let availabilityMonitor: AvailabilityMonitor
    /// A link that needs a new connection set up first, shown by ScreenSharingView.
    var setup: SetupRequest?
    var alert: AlertState?
    @ObservationIgnored private var lookup: Task<Void, Never>?

    private init() {
        Task.detached(priority: .userInitiated) { _ = DecoderCapabilities.current }
        _ = AppDatabase.shared
        nearby = NearbyBrowser()
        availabilityMonitor = AvailabilityMonitor(nearby: nearby)
    }

    /// Whether a session is up and showing the computer.
    public var isConnected: Bool {
        controller?.phase == .connected
    }

    /// Whether there's a session, connected or not yet.
    public var hasSession: Bool {
        controller != nil
    }

    /// Connects to the computer at `host`, or keeps the session already going to it.
    ///
    /// A computer connected to before is found by its address, along with the password it saved; others are saved
    /// once they connect.
    public func connect(host: String, port: Int? = nil, name: String? = nil) {
        let address = ComputerAddress(host: host, port: port ?? ComputerAddress.defaultPort)
        if let controller, controller.route.address == address, controller.route.remoteProtocol == .vnc,
            !controller.isClosing
        {
            switch controller.phase {
            case .disconnected, .failed: break
            default: return
            }
        }
        let computer =
            ComputerStore.shared.computer(at: address, remoteProtocol: .vnc, username: nil)
            ?? Computer(name: name ?? host, address: address)
        connect(SessionRoute(computer: computer))
    }

    /// Opens a vnc:// or rdp:// link. Returns false for anything else.
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard let link = RemoteLink(string: url.absoluteString) else { return false }
        lookup?.cancel()
        lookup = nil
        guard let serviceName = link.address.bonjourServiceName else {
            open(link, at: link.address)
            return true
        }
        if let address = nearby.computers.first(where: { $0.remoteProtocol == .vnc && $0.name == serviceName })?.address {
            open(link, at: address)
            return true
        }
        lookup = Task {
            do {
                let address = try await ServiceResolver.resolve(name: serviceName)
                try Task.checkCancellation()
                open(link, at: address)
            } catch is CancellationError {
            } catch {
                alert = AlertState(String(localized: "Couldn’t Open the Link"), error: error)
            }
        }
        return true
    }

    /// Ends the session.
    public func disconnect() {
        controller?.abort()
        controller = nil
    }

    func connect(_ route: SessionRoute) {
        controller?.abort()
        controller = SessionController(route: route)
    }

    /// Forgets a session its view closed.
    func sessionDidClose(_ closed: SessionController) {
        guard controller === closed else { return }
        controller = nil
    }

    private func open(_ link: RemoteLink, at address: ComputerAddress) {
        guard let computer = ComputerStore.shared.computer(at: address, remoteProtocol: link.remoteProtocol, username: link.username)
        else {
            var link = link
            link.address = address
            setup = SetupRequest(link: link)
            return
        }
        var route = SessionRoute(computer: computer)
        if let username = link.username {
            route.username = username
        }
        if let password = link.password {
            route.credentials = route.username.map { .account(username: $0, password: password) } ?? .vncPassword(password)
        }
        connect(route)
    }

    func viewDidAppear() {
        visibleViews += 1
        guard visibleViews == 1 else { return }
        controller?.sceneDidBecomeActive()
    }

    func viewDidDisappear() {
        visibleViews = max(visibleViews - 1, 0)
        guard visibleViews == 0 else { return }
        // Once the app itself is in the background, it has seen to the session already.
        guard UIApplication.shared.applicationState != .background else { return }
        controller?.sceneDidEnterBackground()
    }
}
#endif
