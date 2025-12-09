// The Swift Programming Language
// https://docs.swift.org/swift-book

import Adwaita
import SampleCore

@main
struct PQSDemoApp: App {

    let app = AdwaitaApp(id: "com.needletails.PQSDemoApp")
    @State private var isRegistered: Bool = false
    private var receiver = MessageReceiverManager()
    @State private var showingAddContact: Bool = false
    /// Single shared SessionManager instance for the whole app.
    /// This avoids recreating the actor (and losing its IRC connection)
    /// every time the view hierarchy is rebuilt.
    let session: SessionManager
    let store = PQSSessionCache()

    init() {
        self.session = SessionManager(receiver: receiver, useWebSockets: false)
    }
    
    var scene: Scene {
        Window(id: "main") { window in
            RootContent(
                app: app,
                window: window,
                isRegistered: $isRegistered,
                receiver: receiver,
                session: session,
                store: store
            )
        }
        .defaultSize(width: 600, height: 450)
    }
}

extension PQSDemoApp {

    @MainActor
	struct RootContent: @preconcurrency View {
		var app: AdwaitaApp
		var window: AdwaitaWindow
		@Binding var isRegistered: Bool
		var receiver: MessageReceiverManager
		var session: SessionManager
		var store: PQSSessionCache
        @State private var showingAddContact: Bool = false
        @State private var showingCreateChannel: Bool = false

		var view: Body {
			VStack {
				RegistrationViewAdw(store: store, session: session, isRegistered: $isRegistered)
					.visible(!isRegistered)
				HomeViewAdw(
					app: app,
					window: window,
					isRegistered: $isRegistered,
					showingAddContact: $showingAddContact,
                    showingCreateChannel: $showingCreateChannel,
					receiver: receiver,
					session: session
				)
					.visible(isRegistered)
			}
			.topToolbar {
				ToolbarView(
                    app: app,
                    window: window,
                    isRegistered: $isRegistered,
                    showingAddContact: $showingAddContact,
                    showingCreateChannel: $showingCreateChannel
                ).view
			}
		}
	}
}

