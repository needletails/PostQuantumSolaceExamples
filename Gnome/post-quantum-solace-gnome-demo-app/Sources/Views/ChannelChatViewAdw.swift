import Adwaita
import SampleCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
struct ChannelChatViewAdw: @preconcurrency View {

    let receiver: MessageReceiverManager
    let channel: BaseCommunication
    let session: SessionManager
    @State private var channelName: String = ""
    @State private var newMessage: String = ""

    var view: Body {
        VStack {
            // Messages list driven directly from MessageReceiverManager
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(filteredMessages.map { IdentifiedMessage(message: $0) }) { item in
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
            Task {
                await loadChannelName()
            }
        }
    }

    /// Messages filtered for this channel's communication, provided by MessageReceiverManager.
    private var filteredMessages: [EncryptedMessage] {
        receiver.messages.filter { $0.communicationId == channel.id }
    }

    private func loadChannelName() async {
        do {
            let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
            guard let props = await channel.props(symmetricKey: symmetricKey),
                  case .channel(let name) = props.communicationType else {
                await MainActor.run {
                    channelName = "Unknown Channel"
                }
                return
            }

            await MainActor.run {
                channelName = name
            }
        } catch {
            await MainActor.run {
                channelName = "Error"
            }
        }
    }

    private func sendMessage() async throws {
        guard !channelName.isEmpty,
              channelName != "Unknown Channel",
              channelName != "Error" else {
            return
        }

        try await session.pqsSession.writeTextMessage(
            recipient: .channel(channelName),
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
