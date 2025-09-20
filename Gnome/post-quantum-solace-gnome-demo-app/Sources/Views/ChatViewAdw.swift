import Adwaita
import PQSSession
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct ChatViewAdw: View {

	let receiver: MessageReceiverManager
	let contact: Contact
	let session: SessionManager
	@State private var messages: [EncryptedMessage] = []
	@State private var newMessage: String = ""
	@State private var listenerInstalled = false

	var view: Body {
		VStack {
			// Messages
			ScrollView {
				VStack(spacing: 8) {
					ForEach(messages.map { IdentifiedMessage(message: $0) }) { item in
						MessageBubbleAdw(encrypted: item.message)
					}
				}
				.padding(8)
			}
			.vexpand()
			.hexpand()
			
			// Separator
			Separator()

			// Composer
			HStack(spacing: 8) {
				Entry("Type a message…", text: $newMessage)
                    .hexpand()
				Button("Send") {
                    Task {
                        try? await sendMessage()
                    }
				}
				.suggested()
				.insensitive(newMessage.isEmpty)
			}
		}
		.padding(12)
		.onAppear {
            Task { @MainActor in 
                messages = receiver.messages
                if !listenerInstalled {
                    listenerInstalled = true
                    receiver.onNewMessage = { msg in
                        Task { @MainActor in 
                            messages.append(msg)
                        }
                    }
                }
            }
		}
        
		// Adwaita AnyView lacks .onChange; poll or react via receiver updates elsewhere
	}

	private func sendMessage() async throws {
		try await session.pqsSession.writeTextMessage(
			recipient: .nickname(contact.secretName),
			text: newMessage,
			metadata: ["should-persist": true]
		)
		newMessage = ""
	}
}

private struct IdentifiedMessage: Identifiable {
	let message: EncryptedMessage
	var id: UUID { message.id }
}


