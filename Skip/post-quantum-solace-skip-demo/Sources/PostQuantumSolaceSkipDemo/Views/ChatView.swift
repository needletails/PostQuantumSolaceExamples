//
//  ChatView.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import SwiftUI
import SampleCore

struct ChatView: View {
    @Environment(MessageReceiverManager.self) var receiver
    let contact: Contact
    let session: SessionManager
    @State var messages: [EncryptedMessage] = []
    @State var newMessage: String = ""
    @State var communicationId: UUID?
    @State var isLoading: Bool = true
    @State var pendingMessages: [EncryptedMessage] = []
    
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
                                MessageBubble(encrypted: message)
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
        .navigationTitle(contact.secretName)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task(id: contact.id) {
            // Clear messages and reload when contact changes
            // Using task(id:) ensures this runs whenever contact.id changes
            await MainActor.run {
                messages = []
                pendingMessages = []
                communicationId = nil
                isLoading = true
            }
            await loadMessages()
        }
        .onChange(of: receiver.lastMessage) { _, newValue in
            guard let newValue else { return }
            
            // If communicationId is not set yet, buffer the message
            guard let commId = communicationId else {
                pendingMessages.append(newValue)
                return
            }
            
            // Only add message if it belongs to this contact's communication
            if newValue.communicationId == commId {
                // Check for duplicates before adding
                if !messages.contains(where: { $0.id == newValue.id }) {
                    messages.append(newValue)
                }
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
            
            // Find the communication for this contact
            guard let cache = await session.pqsSession.cache else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            let symmetricKey = try await session.pqsSession.getDatabaseSymmetricKey()
            guard let _ = await session.pqsSession.sessionContext?.sessionUser.secretName else {
                await MainActor.run {
                    isLoading = false
                }
                return
            }
            
            // Find communication for this contact (1:1 chat)
            let communication = try await session.pqsSession.findCommunicationType(
                cache: cache,
                communicationType: .nickname(contact.secretName),
                symmetricKey: symmetricKey
            )
            
            let commId = communication.id
            await MainActor.run {
                communicationId = commId
            }
            
            // Fetch messages for this communication
            let messageRecords = try await cache.fetchMessages(sharedCommunicationId: commId)
            var contactMessages = messageRecords.map { $0.message }
            
            // Apply any pending messages that match this communication
            let matchingPending = pendingMessages.filter { $0.communicationId == commId }
            for pending in matchingPending {
                if !contactMessages.contains(where: { $0.id == pending.id }) {
                    contactMessages.append(pending)
                }
            }
            pendingMessages.removeAll { $0.communicationId == commId }
            
            await MainActor.run {
                messages = contactMessages
                isLoading = false
            }
        } catch {
            // Communication might not exist yet - that's okay, just show empty
            await MainActor.run {
                messages = []
                isLoading = false
            }
        }
    }
    
    private func sendMessage() async throws {
        try await session.pqsSession.writeTextMessage(
            recipient: .nickname(contact.secretName),
            text: newMessage,
            metadata: try BinaryEncoder().encode(["should-persist": true]))
        newMessage = ""
    }
}

struct MessageBubble: View {
    let encrypted: EncryptedMessage
    @State var isMine = false
    @State var message: String = ""
    @State var date: Date = Date()
    @State var shouldShow: Bool = false
    @State var isLoading: Bool = true
    
    var body: some View {
        Group {
            if shouldShow {
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
                do {
                    let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
                    let props = await encrypted.props(symmetricKey: symmetricKey)
                    if let props = props, !props.message.text.isEmpty {
                        let mySecretName = await PQSSession.shared.sessionContext?.sessionUser.secretName
                        self.isMine = props.senderSecretName == mySecretName
                        self.message = props.message.text
                        self.date = props.sentDate
                        self.shouldShow = true
                    }
                } catch {
                    // Log error but don't crash - just show loading state
                    print("Error loading message props: \(error)")
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
