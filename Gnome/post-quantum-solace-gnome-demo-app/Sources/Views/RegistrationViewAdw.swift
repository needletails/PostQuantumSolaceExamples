import Adwaita
import PQSSession

struct RegistrationViewAdw: View {

	@State private var secretName: String = ""
	@State private var password: String = ""
	@State private var isRegistering: Bool = false
	@Binding private var isRegistered: Bool

	let store: PQSSessionCache
	let session: SessionManager

	init(store: PQSSessionCache, session: SessionManager, isRegistered: Binding<Bool>) {
		self.store = store
		self.session = session
		self._isRegistered = isRegistered
	}

	var view: Body {
		VStack(spacing: 16) {
			VStack(spacing: 8) {
				Text("Create Account").title2()
				Text("Enter your details to get started").dimLabel()
            }
            .padding(8, [.top])

			Form {
				EntryRow("Secret Name", text: $secretName)
				PasswordEntryRow("Password", text: $password)
			}

            HStack(spacing: 12) {
				Button("Register") {
					Task { 
					await register(name: secretName, password: password)
					}
				}
				.suggested()
                .insensitive(secretName.isEmpty || password.isEmpty || isRegistering)
                if isRegistering {
                    Spinner()
                }
			}
		}
		.padding(24)
	}

	private func register(name: String, password: String) async {
		do {
			isRegistering = true
			try await session.createSession(
				secretName: name.lowercased(),
				appPassword: password,
				store: store
			)
			logger.log(level: .info, message: "Registration completed successfully")
				isRegistering = false
				isRegistered = true
		} catch {
			logger.log(level: .error, message: "There was an error registering: \(error)")
			isRegistering = false
		}
	}
}


