//
//  ChatView.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import SwiftUI
import PQSSession


struct ChatView: View {
    @Environment(MessageReceiverManager.self) var receiver
    let contact: Contact
    let session: SessionManager
    @State private var messages: [EncryptedMessage] = []
    @State private var newMessage: String = ""
    
    var body: some View {
        VStack {
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
#if os(iOS)
        .navigationTitle(contact.secretName)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            messages = receiver.messages
        }
        .onChange(of: receiver.lastMessage) { _, newValue in
            guard let newValue else { return }
            messages.append(newValue)
        }
    }
    
    private func sendMessage() async throws {
        try await session.pqsSession.writeTextMessage(
            recipient: .nickname(contact.secretName),
            text: newMessage,
            metadata: ["should-persist": true])
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
                let props = try await encrypted.props(symmetricKey: PQSSession.shared.getDatabaseSymmetricKey())
                if let props = props, !props.message.text.isEmpty {
                    await props.senderSecretName == PQSSession.shared.sessionContext?.sessionUser.secretName ? (self.isMine = true) : (self.isMine = false)
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
