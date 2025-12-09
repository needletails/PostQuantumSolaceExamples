import Adwaita
import SampleCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
struct ChatViewAdw: @preconcurrency View {

    let receiver: MessageReceiverManager
    let contact: Contact
    let session: SessionManager
    @State private var newMessage: String = ""
    @State private var communicationId: UUID?
    @Binding var messages: [EncryptedMessage]
    
    var view: Body {
        VStack {
            // Messages list driven directly from MessageReceiverManager
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

    }

    private func sendMessage() async throws {
        try await session.pqsSession.writeTextMessage(
            recipient: .nickname(contact.secretName),
            text: newMessage,
            metadata: try BinaryEncoder().encode(["should-persist": true])
        )
        newMessage = ""
    }
}

private struct IdentifiedMessage: Identifiable {
    let message: EncryptedMessage
    var id: UUID { message.id }
}
