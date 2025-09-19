// The Swift Programming Language
// https://docs.swift.org/swift-book

import Adwaita
import PQSSession
import ConnectionManagerKit
import NeedleTailIRC

@main
struct PQSDemoApp: App {

    let app = AdwaitaApp(id: "com.needletails.PQSDemoApp")
    @State private var isRegistered: Bool = false
    @MainActor private var receiver = MessageReceiverManager()
    @State private var showingAddContact: Bool = false
    var session: SessionManager { SessionManager(receiver: receiver, useWebSockets: false) }
    let store = PQSSessionCache()

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
			.onAppear {
			Task {
				let connection = ConnectionManager<IRCPayload, IRCPayload>(logger: logger)
				try await connection.connect(
					to: [.init(
						host: AppConfiguration.Server.host,
						port: AppConfiguration.Server.port,
						enableTLS: AppConfiguration.Server.enableTLS,
						cacheKey: AppConfiguration.Server.cacheKey
					)],
					tlsPreKeyed: nil
				)
			}
			}
        }
        .defaultSize(width: 600, height: 450)
    }

}

extension PQSDemoApp {

	struct RootContent: View {
		var app: AdwaitaApp
		var window: AdwaitaWindow
		@Binding var isRegistered: Bool
		var receiver: MessageReceiverManager
		var session: SessionManager
		var store: PQSSessionCache
        @State private var showingAddContact: Bool = false

		var view: Body {
			VStack {
				RegistrationViewAdw(store: store, session: session, isRegistered: $isRegistered)
					.visible(!isRegistered)
				HomeViewAdw(
					app: app,
					window: window,
					isRegistered: $isRegistered,
					showingAddContact: $showingAddContact,
					receiver: receiver,
					session: session
				)
					.visible(isRegistered)
			}
			.topToolbar {
				ToolbarView(app: app, window: window, isRegistered: $isRegistered, showingAddContact: $showingAddContact).view
			}
		}
	}
}

