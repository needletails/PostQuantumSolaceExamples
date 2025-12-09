import Adwaita
import SampleCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct MessageBubbleAdw: View {

    let encrypted: EncryptedMessage
    @State private var isMine: Bool = false
    @State private var message: String = ""
    @State private var date: Date = .init()
    @State private var shouldShow: Bool = false
    @State private var isLoading: Bool = true

	init(encrypted: EncryptedMessage) { self.encrypted = encrypted }

	var view: Body {
        HStack {
            if shouldShow {
                if isMine {
                    // Sent message - align to right
                    VStack(spacing: 4) {
                        Text(message)
                            .padding(12)
                            .halign(.end)
                        Text(formatTime(date))
                            .halign(.end)
                    }
                    .halign(.end)
                    .hexpand()
                } else {
                    // Received message - align to left
                    VStack(spacing: 4) {
                        Text(message)
                            .padding(12)
                            .halign(.start)
                        Text(formatTime(date))
                            .halign(.start)
                    }
                    .halign(.start)
                    .hexpand()
                }
            } else if isLoading {
                Spinner()
            }
        }
        .padding(8)
        .onAppear {
            Task {
                await load()
            }
        }
	}

	private func load() async {
		let props = try? await encrypted.props(symmetricKey: PQSSession.shared.getDatabaseSymmetricKey())
		let currentUser = await PQSSession.shared.sessionContext?.sessionUser.secretName
		await MainActor.run {
			if let props = props, !props.message.text.isEmpty {
				self.isMine = (props.senderSecretName == currentUser)
				self.message = props.message.text
				self.date = props.sentDate
				self.shouldShow = true
			}
			self.isLoading = false
		}
	}

	private func formatTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.timeStyle = .short
		return formatter.string(from: date)
	}
}


