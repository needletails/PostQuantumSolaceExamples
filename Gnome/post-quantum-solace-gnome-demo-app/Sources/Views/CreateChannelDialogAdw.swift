import Foundation
import Adwaita
import SampleCore

@MainActor
struct CreateChannelDialogAdw: @MainActor View {

    let session: SessionManager
    let receiver: MessageReceiverManager
    @Binding var visible: Bool

    @State private var channelName: String = ""
    @State private var selectedIds: Set<UUID> = []
    @State private var isCreating: Bool = false

    private let minGroupSize = 2
    private let maxGroupSize = 1000
    private let logger = NeedleTailLogger("CreateChannelDialogAdw")

    private var contacts: [Contact] {
        receiver.contacts
    }

    var view: Body {
        VStack(spacing: 12) {
            Text("Create Channel").title3()

            // Channel name entry
            EntryRow("Channel Name", text: $channelName)

            // Contacts selection list
            if contacts.isEmpty {
                Text("No contacts available").dimLabel()
            } else {
                List(contacts.map { IdentifiedContact(contact: $0) }) { item in
                    let isSelected = selectedIds.contains(item.contact.id)
                    Button(isSelected ? "[x] \(item.contact.secretName)" : "[ ] \(item.contact.secretName)") {
                        toggle(contact: item.contact)
                    }
                }
                .vexpand()
            }

            // Actions
            HStack(spacing: 8) {
                Button("Cancel") {
                    visible = false
                }
                Button(isCreating ? "Creating..." : "Create") {
                    logger.log(level: .info, message: "Create button tapped. channelName='\(channelName)', selectedIds=\(selectedIds.count)")
                    Task {
                        await createChannel()
                    }
                }
                .suggested()
                .insensitive(!canCreate || isCreating)
            }
            .halign(.end)
        }
        .padding(12)
    }

    private var canCreate: Bool {
        let count = selectedIds.count
        return !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               count >= minGroupSize &&
               count <= maxGroupSize
    }

    private func toggle(contact: Contact) {
        if selectedIds.contains(contact.id) {
            selectedIds.remove(contact.id)
        } else {
            // enforce max size
            guard selectedIds.count < maxGroupSize else { return }
            selectedIds.insert(contact.id)
        }
    }

    private func createChannel() async {
        logger.log(level: .debug, message: "createChannel entered: canCreate=\(canCreate), name='\(channelName)', selectedIds=\(selectedIds.count)")
        guard canCreate else {
            logger.log(level: .warning, message: "Aborting channel creation: canCreate == false")
            return
        }
        logger.log(level: .info, message: "Starting channel creation flow")
        isCreating = true

        do {
            let members = contacts
                .filter { selectedIds.contains($0.id) }
                .map { $0.secretName }
            logger.log(level: .debug, message: "Selected members for channel: \(members)")

            var finalName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalName.hasPrefix("#") {
                finalName = "#\(finalName)"
            }
            logger.log(level: .debug, message: "Final channel name: \(finalName)")

            guard let admin = await session.pqsSession.sessionContext?.sessionUser.secretName else {
                logger.log(level: .error, message: "Channel creation aborted: could not resolve admin secret name")
                isCreating = false
                return
            }

            guard let channel = NeedleTailChannel(finalName) else {
                logger.log(level: .error, message: "Channel creation aborted: invalid channel name '\(finalName)'")
                isCreating = false
                return
            }

            let packet = NeedleTailChannelPacket(
                name: channel,
                channelOperatorAdmin: admin,
                channelOperators: [admin],
                members: Set(members)
            )

            logger.log(level: .info, message: "Joining/creating channel '\(finalName)' with admin '\(admin)' and \(members.count) members")
            try await session.joinChannel(packet, createChannel: true)
            logger.log(level: .info, message: "Channel '\(finalName)' creation/join request sent successfully")

            await MainActor.run {
                isCreating = false
                channelName = ""
                selectedIds.removeAll()
                visible = false
            }
        } catch {
            await MainActor.run {
                isCreating = false
            }
            logger.log(level: .error, message: "Error creating channel: \(error)")
        }
    }
}

private struct IdentifiedContact: Identifiable {
    let contact: Contact
    var id: UUID { contact.id }
}

