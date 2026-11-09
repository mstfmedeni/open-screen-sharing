#if EMBEDDED && os(iOS)
import SwiftUI

/// The screen sharing tab of an app that embeds this one: the session while there is one, and the computers to
/// connect to otherwise.
///
/// The view can come and go freely; the session stays with ScreenSharingStore.
@available(iOS 17, *)
public struct ScreenSharingView: View {
    @Bindable private var store = ScreenSharingStore.shared

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
            ConnectionSetupView(link: request.link) { route in
                store.connect(route)
            }
        }
        .onAppear { store.viewDidAppear() }
        .onDisappear { store.viewDidDisappear() }
    }
}

@available(iOS 17, *)
private struct ScreenSharingComputers: View {
    let store: ScreenSharingStore

    @Environment(\.scenePhase) private var scenePhase
    @State private var editing: Computer?
    @State private var showsSettings = false
    @State private var isWatching = false

    var body: some View {
        NavigationStack {
            ComputersView(
                connect: { route in store.connect(route) },
                openInNewWindow: nil,
                edit: { computer in editing = computer },
                newConnection: { store.setup = SetupRequest() }
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .environment(store.nearby)
        .environment(store.availabilityMonitor)
        .sheet(item: $editing) { computer in
            ComputerEditor(computer: computer)
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            CloseButton { showsSettings = false }
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
#endif
