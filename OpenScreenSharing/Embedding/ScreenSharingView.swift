#if EMBEDDED && os(iOS)
import Perception
import SwiftUI

/// The screen sharing tab of an app that embeds this one: the session while there is one, and the computers to
/// connect to otherwise.
///
/// The view can come and go freely; the session stays with ScreenSharingStore.
@available(iOS 17, *)
public struct ScreenSharingView: View {
    @SwiftUI.Bindable private var store = ScreenSharingStore.shared

    public init() {}

    public var body: some View {
        Group {
            if let controller = store.controller {
                SessionView(controller: controller, hasOwnWindow: false) {
                    store.sessionDidClose(controller)
                }
                .id(ObjectIdentifier(controller))
            } else {
                ScreenSharingComputers(store: store)
            }
        }
        .modifier(StorageNoticeAlert())
        .alert($store.alert)
        .sheet(item: $store.setup) { request in
            ConnectionSetupView(link: request.link, name: request.name, connect: request.savesOnly ? nil : { route in
                store.connect(route)
            })
        }
        .sheet(item: $store.editing) { computer in
            ComputerEditor(computer: computer)
        }
        .sheet(isPresented: $store.showsSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            CloseButton { store.showsSettings = false }
                        }
                    }
            }
        }
        .onAppear { store.viewDidAppear() }
        .onDisappear { store.viewDidDisappear() }
        // Outermost, so that sheets presented above get them too.
        .perceptibleEnvironment(store.nearby)
        .perceptibleEnvironment(store.availabilityMonitor)
    }
}

@available(iOS 17, *)
private struct ScreenSharingComputers: View {
    let store: ScreenSharingStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var isWatching = false

    var body: some View {
        NavigationStack {
            ComputersView(
                connect: { route in store.connect(route) },
                openInNewWindow: nil,
                edit: { computer in store.editing = computer },
                newConnection: { store.setup = SetupRequest() }
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.showSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .onAppear { setWatching(scenePhase != .background) }
        .onDisappear { setWatching(false) }
        .onChange(of: scenePhase) { setWatching(scenePhase != .background) }
    }

    private func setWatching(_ watching: Bool) {
        guard watching != isWatching else { return }
        isWatching = watching
        if watching {
            store.nearby.start()
            store.availabilityMonitor.start()
        } else {
            store.availabilityMonitor.stop()
            store.nearby.stop()
        }
    }
}
extension View {
    /// Puts an object where the app's views read it with `@Environment(Type.self)`.
    ///
    /// Those views target iOS 15, so they read with Perception's back-port; SwiftUI's own `environment(_:)`, picked
    /// for an Observable type in code that targets iOS 17, puts it where they don't look.
    fileprivate func perceptibleEnvironment<T: AnyObject & Perceptible>(_ object: T) -> some View {
        environment(object)
    }
}
#endif
