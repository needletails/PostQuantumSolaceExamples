//
//  MessageReceiverManager.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import PQSSession
import NeedleTailLogger
import Observation


/**
 _MessageReceiverManager_ conforms to **EventReceiver**. This protocol is how **PostQuantumSolace** Notifies the consumer of Events performed by the session. Please read the **EventReceiver** documnetation in order to understand how to use each protocol method.
 **/

final class MessageReceiverManager: EventReceiver, @unchecked Sendable {
    
    var contacts: [Contact] = []
    var messages: [EncryptedMessage] = []
    var lastMessage: EncryptedMessage?

    var contactContinuation: AsyncStream<Contact>.Continuation?
    var messageContinuation: AsyncStream<EncryptedMessage>.Continuation?
    var contactStream: AsyncStream<Contact> {
        AsyncStream { continuation in
            contactContinuation = continuation
        }
    }
    var messageStream: AsyncStream<EncryptedMessage> {
        AsyncStream { continuation in
            messageContinuation = continuation
        }
    }

    // MARK: - EventReceiver Implementation
    
    public func receivedLocalNudge(_ message: CryptoMessage, sender: String, senderDeviceId: String) async {
        logger.log(level: .info, message: "Received local nudge from \(sender)")
        // Handle local nudge - could trigger UI updates or notifications
    }
    
    public func createdMessage(_ message: EncryptedMessage) async {
        logger.log(level: .info, message: "Message created: \(message.id)")
        // Handle message creation - could update UI or trigger notifications
        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
            lastMessage = message
            messageContinuation?.yield(message)
        }
    }
    
    public func updatedMessage(_ message: EncryptedMessage) async {
        logger.log(level: .info, message: "Message updated: \(message.id)")
        // Handle message update - could update UI
    }
    
    public func deletedMessage(_ message: EncryptedMessage) async {
        logger.log(level: .info, message: "Message deleted: \(message.id)")
        // Handle message deletion - could update UI
    }
    
    func requestOnlineNicks(contact: Contact) async throws {
        logger.log(level: .info, message: "Requesting online nicks for contact: \(contact.id)")
        // Implementation for requesting online nicks
        // This could involve querying the server for active users
    }
    
    public func createdContact(_ contact: Contact) async throws {
        logger.log(level: .info, message: "Contact created in receiver: \(contact.id)")
        // Handle contact creation - could update contact list UI
        contacts.append(contact)
       contactContinuation?.yield(contact)
       logger.log(level: .info, message: "Yieled Contact \(contactContinuation)")
    }
    
    public func synchronize(
        contact: Contact,
        requestFriendship: Bool
    ) async throws {
        logger.log(level: .info, message: "Synchronizing contact: \(contact.id), requestFriendship: \(requestFriendship)")
        if requestFriendship {
            //This only happens on the requesters end
            logger.log(level: .info, message: "Requesting friendship state change to 'requested' for contact: \(contact.secretName)")
            try await PQSSession.shared.requestFriendshipStateChange(
                state: .requested,
                contact: contact)
            logger.log(level: .info, message: "Friendship state change request sent for: \(contact.secretName)")
        } else {
            //Acknowledge that the contact was created, this only happens on the receiving end
            logger.log(level: .info, message: "Sending contact created acknowledgment to: \(contact.secretName)")
            try await PQSSession.shared.sendContactCreatedAcknowledgment(recipient: contact.secretName)
        }
    }
    
    func transportContactMetadata() async throws {
        logger.log(level: .info, message: "Transporting contact metadata")
        // Handle transporting contact metadata
        // This could involve sending contact information to other devices
    }
    
    public func removedContact(_ secretName: String) async throws {
        logger.log(level: .info, message: "Contact removed: \(secretName)")
        // Handle contact removal - could update contact list UI
        contacts.removeAll { $0.secretName == secretName }
    }
    
    public func updateContact(_ contact: Contact) async throws {
        logger.log(level: .info, message: "Contact updated: \(contact.id)")
        // Handle contact update - could update contact list UI
        if let idx = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[idx] = contact
        }
    }
    
    public func contactMetadata(changed for: Contact) async {
        logger.log(level: .info, message: "Contact metadata changed for: \(`for`.secretName)")
        // Handle contact metadata changes - could update UI
    }
    
    public func passDCCKey(_ key: SymmetricKey) async {
        logger.log(level: .info, message: "DCC key passed")
        // Handle DCC (Direct Client-to-Client) key exchange
        // This is typically used for file transfers or direct communication
    }
    
    public func updatedCommunication(_ model: BaseCommunication, members: Set<String>) async {
        logger.log(level: .info, message: "Communication updated with \(members.count) members")
        // Handle communication updates - could update chat UI
    }
}
