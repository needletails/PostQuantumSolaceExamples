import Adwaita
import SampleCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


@MainActor
struct HomeViewAdw: @preconcurrency View {

    let app: AdwaitaApp
    let window: AdwaitaWindow
    @Binding var isRegistered: Bool
    @Binding var showingAddContact: Bool
    @Binding var showingCreateChannel: Bool
    let receiver: MessageReceiverManager
    let session: SessionManager
    @State private var selection: Selection = .none
    @State private var contacts: [Contact] = []
    @State private var channels: [BaseCommunication] = []
    @State private var channelNames: [UUID: String] = [:]
    @State private var wide = true
    @State private var contactsTask: Task<Void, Never>?
    @State private var channelsTask: Task<Void, Never>?
    @State private var contactsStreamInstalled: Bool = false
    @State private var messages: [EncryptedMessage] = []

    @State private var currentMessageTask: Task<Void, Never>?
    
    var view: Body {
        OverlaySplitView(visible: .constant(true)) {
            ScrollView {
                VStack(spacing: 8) {
                    // Channels section (selectable)
                    if !channels.isEmpty {
                        Text("Channels").dimLabel()
                        
                        List(
                            channels.map { IdentifiedChannel(channel: $0) },
                            selection: Binding(
                                get: {
                                    if case .channel(let id) = selection {
                                        return id
                                    } else {
                                        // Use a UUID that won't match any real channel to mean "no selection"
                                        return Selection.noSelectionId
                                    }
                                },
                                set: { newValue in
                                    if newValue == Selection.noSelectionId {
                                        // Clearing channel selection – also clear any active messages/stream
                                        if case .channel = selection {
                                            selection = .none
                                            messages.removeAll()
                                            currentMessageTask?.cancel()
                                            currentMessageTask = nil
                                        }
                                    } else {
                                        // Selecting a channel implicitly deselects any contact
                                        selection = .channel(newValue)
                                        messages.removeAll()
                                        currentMessageTask?.cancel()
                                        currentMessageTask = nil
                                    }
                                })
                        ) { item in
                            Text(channelNames[item.channel.id] ?? "Channel")
                                .padding(8)
                        }
                        .sidebarStyle()
                    }

                    // Contacts section (selectable)
                    if !contacts.isEmpty {
                        List(
                            contacts.map { IdentifiedContact(contact: $0) },
                            selection: Binding(
                                get: {
                                    if case .contact(let id) = selection {
                                        return id
                                    } else {
                                        return Selection.noSelectionId
                                    }
                                },
                                set: { newValue in
                                    if newValue == Selection.noSelectionId {
                                        // Clearing contact selection – clear messages/stream
                                        if case .contact = selection {
                                            selection = .none
                                            messages.removeAll()
                                            currentMessageTask?.cancel()
                                            currentMessageTask = nil
                                        }
                                    } else {
                                        // Selecting a contact implicitly deselects any channel
                                        selection = .contact(newValue)

                                        // Start (or restart) the message stream for this contact
                                        if let contact = contacts.first(where: { $0.id == newValue }) {
                                            startMessagesStream(for: contact)
                                        } else {
                                            // If the contact isn't in the current list yet, at least clear state
                                            messages.removeAll()
                                            currentMessageTask?.cancel()
                                            currentMessageTask = nil
                                        }
                                    }
                                })
                        ) { item in
                            Text(item.contact.secretName)
                                .padding(8)
                        }
                        .sidebarStyle()
                    } else {
                        Text("No Contacts").dimLabel()
                    }
                }
            }
            .hscrollbarPolicy(.never)
            .vexpand()
            .hexpand()
            .topToolbar {
                // Sidebar has no extra controls; the window toolbar is global
            }
        } content: {
            switch selection {
            case .channel(let id):
                if let channel = channels.first(where: { $0.id == id }) {
                    ChannelChatViewAdw(receiver: receiver, channel: channel, session: session)
                        .vexpand()
                        .hexpand()
                } else {
                    StatusPage(
                        "No Chat Selected",
                        icon: .default(icon: .applicationXExecutable),
                        description: "Select a contact or channel from the sidebar"
                    ) { }
                    .vexpand()
                    .hexpand()
                }
            case .contact(let id):
                if let contact = contacts.first(where: { $0.id == id }) {
                    ChatViewAdw(
                        receiver: receiver,
                        contact: contact,
                        session: session,
                        messages: $messages)
                        .vexpand()
                        .hexpand()
                } else {
                    StatusPage(
                        "No Chat Selected",
                        icon: .default(icon: .applicationXExecutable),
                        description: "Select a contact or channel from the sidebar"
                    ) { }
                    .vexpand()
                    .hexpand()
                }
            case .none:
                StatusPage(
                    "No Chat Selected",
                    icon: .default(icon: .applicationXExecutable),
                    description: "Select a contact or channel from the sidebar"
                ) { }
                .vexpand()
                .hexpand()
            }
        }
        .vexpand()
        .hexpand()
        .breakpoint(minWidth: 600, matches: $wide)
        .dialog(visible: $showingAddContact, title: "Add Contact") {
            AddContactDialogAdw(
                session: session,
                receiver: receiver,
                visible: $showingAddContact,
                contacts: $contacts
            )
        }
        .dialog(visible: $showingCreateChannel, title: "Create Channel") {
            CreateChannelDialogAdw(session: session, receiver: receiver, visible: $showingCreateChannel)
        }
        .onAppear {
            guard !contactsStreamInstalled else { return }
            contactsStreamInstalled = true
            // Ensure channels are loaded when the view appears
            Task {
                await receiver.loadChannels()
            }
            // Seed with any existing contacts
            contacts = receiver.contacts
            channels = receiver.channels
            // Listen for contact changes
            contactsTask = Task {
                for await event in receiver.contactsStream() {
                    await MainActor.run {
                        switch event {
                        case .newValue(let contact):
                            if !contacts.contains(where: { $0.id == contact.id }) {
                                contacts.append(contact)
                            }
                        case .updated(let updatedContact):
                            if let index = contacts.firstIndex(where: { $0.id == updatedContact.id }) {
                                contacts[index] = updatedContact
                            }
                        case .removed(let removedContact):
                            contacts.removeAll(where: { $0.id == removedContact.id })
                        }
                    }
                }
            }
            
            channelsTask = Task {
                for await event in receiver.channelsStream() {
                    await MainActor.run {
                        handleChannelEvent(event)
                    }
                }
            }

        }
    }
}

private struct IdentifiedContact: Identifiable, Equatable {
	let contact: Contact
	var id: UUID { contact.id }
}

private struct IdentifiedChannel: Identifiable, Equatable {
    let channel: BaseCommunication
    var id: UUID { channel.id }
}

// A single, explicit selection model so a contact and a channel
// cannot be "selected" at the same time.
enum Selection: Equatable {
    case none
    case contact(UUID)
    case channel(UUID)

    /// Sentinel UUID used to represent "no selection" for Adwaita's `List`
    /// which currently expects a non-optional selection binding.
    static let noSelectionId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

// MARK: - Helpers
extension HomeViewAdw {
    fileprivate func startMessagesStream(for contact: Contact) {
        messages.removeAll()
        receiver.messageContinuation?.finish()
        receiver.messages.removeAll()
        currentMessageTask?.cancel()
        currentMessageTask = nil

        currentMessageTask = Task {
            let stream = receiver.messagesStream()

            await receiver.loadMessage(for: contact)

            for await event in stream {
                await MainActor.run {
                    switch event {
                    case .newValue(let message):
                        self.messages.append(message)
                    case .removed(let removed):
                        self.messages.removeAll(where: { $0.id == removed.id })
                    case .updated(let updated):
                        if let index = self.messages.firstIndex(where: { $0.id == updated.id }) {
                            self.messages[index] = updated
                        }
                    }
                }
            }
        }
    }

    fileprivate func handleChannelEvent(_ event: OnChangeEvent<BaseCommunication>) {
        switch event {
        case .newValue(let channel):
            if !channels.contains(where: { $0.id == channel.id }) {
                channels.append(channel)
            }
            Task {
                let name = await resolveChannelName(for: channel)
                await MainActor.run {
                    channelNames[channel.id] = name
                }
            }
        case .updated(let updatedChannel):
            if let index = channels.firstIndex(where: { $0.id == updatedChannel.id }) {
                channels[index] = updatedChannel
            }
            Task {
                let name = await resolveChannelName(for: updatedChannel)
                await MainActor.run {
                    channelNames[updatedChannel.id] = name
                }
            }
        case .removed(let removedChannel):
            channels.removeAll(where: { $0.id == removedChannel.id })
            channelNames[removedChannel.id] = nil
        }
    }
    
    fileprivate func resolveChannelName(for channel: BaseCommunication) async -> String {
        do {
            let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
            guard let props = await channel.props(symmetricKey: symmetricKey),
                  case .channel(let name) = props.communicationType else {
                return "Unknown Channel"
            }
            return name
        } catch {
            return "Error"
        }
    }
}
