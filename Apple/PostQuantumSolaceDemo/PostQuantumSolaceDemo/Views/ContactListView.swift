//
//  ContactListView.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import SwiftUI
import SampleCore

extension Contact: @retroactive Identifiable {}
extension BaseCommunication: @retroactive Identifiable {}

struct ContactListView: View {
    let session: SessionManager
    @Environment(MessageReceiverManager.self) var receiver
    @State private var selectedContacts: Set<Contact> = []
    @State private var presentedSheetType: SheetType?
    @Binding var isRegistered: Bool
    
    enum SheetType: Identifiable {
        case addContact, createChannel, none
        
        var id: String {
            switch self {
            case .addContact: return "addContact"
            case .createChannel: return "createChannel"
            case .none: return "none"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if receiver.contacts.isEmpty && receiver.channels.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Contacts or Channels")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Text("Add your first contact or create a channel to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        // Channels Section
                        if !receiver.channels.isEmpty {
                            Section("Channels") {
                                ForEach(receiver.channels) { channel in
                                    ChannelRow(channel: channel, session: session)
                                }
                            }
                        }
                        
                        // Contacts Section
                        if !receiver.contacts.isEmpty {
                            Section("Contacts") {
                                ForEach(receiver.contacts) { contact in
                                    NavigationLink(destination: ChatView(contact: contact, session: session)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(contact.secretName)
                                                .font(.headline)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .task {
                await receiver.loadContacts()
                await receiver.loadChannels()
            }
            .onAppear {
                // Reload channels when view appears to catch any that were created
                Task {
                    await receiver.loadChannels()
                }
            }
            .navigationTitle("Contacts & Channels")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        presentedSheetType = .addContact
                    }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        presentedSheetType = .createChannel
                    }) {
                        Image(systemName: "person.3.fill")
                    }
                }
                ToolbarItem(placement: .navigation) {
                    Button(action: {
                        isRegistered = false
                    }) {
                        Text("Sign Out")
                    }
                }
            }
            .sheet(item: $presentedSheetType) { type in
                switch type {
                case .addContact:
                    AddContactView(
                        session: session,
                        contacts: Binding(
                            get: { receiver.contacts },
                            set: { _ in }
                        ))
                case .createChannel:
                    CreateChannelView(
                        session: session,
                        selectedContacts: $selectedContacts
                    )
                case .none:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Channel Row
struct ChannelRow: View {
    let channel: BaseCommunication
    let session: SessionManager
    @State private var channelName: String = "Loading..."
    @State private var isLoading: Bool = true
    
    var body: some View {
        NavigationLink(destination: ChannelChatView(channel: channel, session: session)) {
            HStack {
                Image(systemName: "number")
                    .foregroundColor(.blue)
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(channelName)
                        .font(.headline)
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .task {
            await loadChannelName()
        }
    }
    
    private func loadChannelName() async {
        do {
            let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
            guard let props = await channel.props(symmetricKey: symmetricKey),
                  case .channel(let name) = props.communicationType else {
                await MainActor.run {
                    channelName = "Unknown Channel"
                    isLoading = false
                }
                return
            }
            
            await MainActor.run {
                channelName = name
                isLoading = false
            }
        } catch {
            await MainActor.run {
                channelName = "Error"
                isLoading = false
            }
        }
    }
}

// MARK: - Channel Chat View
struct ChannelChatView: View {
    @Environment(MessageReceiverManager.self) var receiver
    let channel: BaseCommunication
    let session: SessionManager
    @State private var channelName: String = "Loading..."
    @State private var messages: [EncryptedMessage] = []
    @State private var newMessage: String = ""
    @State private var isLoading: Bool = true
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages, id: \.id) { message in
                                ChannelMessageBubble(encrypted: message, channelName: channelName)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastMessage = messages.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Message Input
                HStack {
                    TextField("Type a message...", text: $newMessage)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Send") {
                        Task {
                            try await sendMessage()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newMessage.isEmpty)
                }
                .padding()
            }
        }
#if os(iOS)
        .navigationTitle(channelName)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task(id: channel.id) {
            // Clear messages and reload when channel changes
            // Using task(id:) ensures this runs whenever channel.id changes
            await MainActor.run {
                messages = []
                channelName = "Loading..."
                isLoading = true
            }
            await loadChannelName()
            await loadMessages()
        }
        .onChange(of: receiver.lastMessage) { _, newValue in
            guard let newValue else { return }
            // Only add message if it belongs to this channel
            if newValue.communicationId == channel.id {
                // Check for duplicates before adding
                if !messages.contains(where: { $0.id == newValue.id }) {
                    messages.append(newValue)
                }
            }
        }
    }
    
    private func loadChannelName() async {
        do {
            let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
            guard let props = await channel.props(symmetricKey: symmetricKey),
                  case .channel(let name) = props.communicationType else {
                await MainActor.run {
                    channelName = "Unknown Channel"
                    isLoading = false
                }
                return
            }
            
            await MainActor.run {
                channelName = name
            }
        } catch {
            await MainActor.run {
                channelName = "Error"
                isLoading = false
            }
        }
    }
    
    private func loadMessages() async {
        do {
            // Clear messages first
            await MainActor.run {
                messages = []
                isLoading = true
            }
            
            guard let cache = await PQSSession.shared.cache else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            // Fetch messages for this channel's communication ID
            let messageRecords = try await cache.fetchMessages(sharedCommunicationId: channel.id)
            let channelMessages = messageRecords.map { $0.message }
            
            await MainActor.run {
                messages = channelMessages.sorted(by: { $0.sequenceNumber < $1.sequenceNumber })
                isLoading = false
            }
        } catch {
            await MainActor.run {
                messages = []
                isLoading = false
            }
        }
    }
    
    private func sendMessage() async throws {
        guard !channelName.isEmpty, channelName != "Loading...", channelName != "Unknown Channel" else {
            return
        }
        
        try await session.pqsSession.writeTextMessage(
            recipient: .channel(channelName),
            text: newMessage,
            metadata: try BinaryEncoder().encode(["should-persist": true]))
        newMessage = ""
    }
}

// MARK: - Channel Message Bubble
struct ChannelMessageBubble: View {
    let encrypted: EncryptedMessage
    let channelName: String
    @State var isMine = false
    @State var senderName: String = ""
    @State var message: String = ""
    @State var date: Date = Date()
    @State var shouldShow: Bool = false
    @State var isLoading: Bool = true
    
    var body: some View {
        Group {
            if shouldShow {
                VStack(alignment: .leading, spacing: 4) {
                    if !isMine {
                        Text(senderName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                    }
                    
                    HStack(alignment: .bottom) {
                        if isMine {
                            Spacer(minLength: 50)
                        }
                        
                        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                            Text(message)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(isMine ? Color.blue : Color.gray.opacity(0.2))
                                .foregroundColor(isMine ? .white : .primary)
                                .cornerRadius(16)
                                .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
                            
                            Text(formatTime(date))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                        }
                        
                        if !isMine {
                            Spacer(minLength: 50)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } else if isLoading {
                // Show a placeholder while loading
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(height: 40)
            }
        }
        .onAppear {
            Task {
                let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
                let props = await encrypted.props(symmetricKey: symmetricKey)
                if let props = props, !props.message.text.isEmpty {
                    let mySecretName = await PQSSession.shared.sessionContext?.sessionUser.secretName
                    self.isMine = props.senderSecretName == mySecretName
                    self.senderName = props.senderSecretName
                    self.message = props.message.text
                    self.date = props.sentDate
                    self.shouldShow = true
                }
                self.isLoading = false
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
