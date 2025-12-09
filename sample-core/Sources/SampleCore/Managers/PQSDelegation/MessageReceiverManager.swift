//
//  MessageReceiverManager.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import PQSSession
import NeedleTailLogger
import Observation
import Foundation


/**
 _MessageReceiverManager_ conforms to **EventReceiver**. This protocol is how **PostQuantumSolace** Notifies the consumer of Events performed by the session. Please read the **EventReceiver** documnetation in order to understand how to use each protocol method.
 **/

@MainActor
@Observable
public final class MessageReceiverManager: EventReceiver {
    
    public let logger = NeedleTailLogger("MessageReceiverManager")
    
    public var contacts: [Contact] = []
    public var channels: [BaseCommunication] = []
    public var messages: [EncryptedMessage] = []
    public var lastMessage: EncryptedMessage?
    
    // MARK: - AsyncStream Continuations

    public var contactContinuation: AsyncStream<OnChangeEvent<Contact>>.Continuation?
    public var messageContinuation: AsyncStream<OnChangeEvent<EncryptedMessage>>.Continuation?
    public var channelContinuation: AsyncStream<OnChangeEvent<BaseCommunication>>.Continuation?
    
    public init() {}

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
            messageContinuation?.yield(.newValue(message))
            lastMessage = message
        }
    }
    
    public func updatedMessage(_ message: EncryptedMessage) async {
        logger.log(level: .info, message: "Message updated: \(message.id)")
        // Update message in list if it exists
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            messageContinuation?.yield(.updated(message))
            // Update lastMessage if it's the same message
            if lastMessage?.id == message.id {
                lastMessage = message
            }
        }
    }
    
    public func deletedMessage(_ message: EncryptedMessage) async {
        logger.log(level: .info, message: "Message deleted: \(message.id)")
        // Remove message from list
        messages.removeAll { $0.id == message.id }
        messageContinuation?.yield(.removed(message))
        // Clear lastMessage if it's the deleted message
        if lastMessage?.id == message.id {
            lastMessage = nil
        }
    }
    
    public func requestOnlineNicks(contact: Contact) async throws {
        logger.log(level: .info, message: "Requesting online nicks for contact: \(contact.id)")
        // Implementation for requesting online nicks
        // This could involve querying the server for active users
    }
    
    public func createdContact(_ contact: Contact) async throws {
        logger.log(level: .info, message: "Contact created callback triggered for: \(contact.secretName) (id: \(contact.id))")
        // Check if contact already exists (by secretName or id)
        if let existingIndex = contacts.firstIndex(where: { $0.id == contact.id || $0.secretName == contact.secretName }) {
            logger.log(level: .info, message: "Contact already exists, updating: \(contact.secretName)")
            contacts[existingIndex] = contact
            contactContinuation?.yield(.updated(contact))
        } else {
            logger.log(level: .info, message: "Adding new contact to list: \(contact.secretName)")
            contacts.append(contact)
            contactContinuation?.yield(.newValue(contact))
        }
        logger.log(level: .info, message: "Contact list now has \(contacts.count) contacts")
    }
    
    public func removedCommunication(_ type: SessionModels.MessageRecipient) async throws {
        logger.log(level: .info, message: "Removing communication: \(type)")
        
        // Handle different communication types
        switch type {
        case .nickname(let name):
            // Remove contact from local contacts list
            contacts.removeAll { $0.secretName == name }
            
            // Try to find and delete contact from cache
            // Note: We need to find the contact by matching secretName, but ContactModel
            // may need to be converted to Contact to access secretName
            // For now, we'll just remove from local list as the cache deletion
            // should be handled by PQSSession when the communication is removed
            logger.log(level: .debug, message: "Removed contact from local list: \(name)")
            
        case .channel(let channelName):
            // Remove channel from local channels list
            let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
            var channelsToRemove: [UUID] = []
            
            for channel in channels {
                guard let props = await channel.props(symmetricKey: symmetricKey),
                      case .channel(let name) = props.communicationType,
                      name == channelName else {
                    continue
                }
                channelsToRemove.append(channel.id)
                channelContinuation?.yield(.removed(channel))
            }
            
            // Remove channels synchronously
            channels.removeAll { channelsToRemove.contains($0.id) }
            
            // Try to delete communication from cache
            guard let cache = await PQSSession.shared.cache else { return }
            let allCommunications = try await cache.fetchCommunications()
            for communication in allCommunications {
                guard let props = await communication.props(symmetricKey: symmetricKey),
                      case .channel(let name) = props.communicationType,
                      name == channelName else {
                    continue
                }
                try await cache.deleteCommunication(communication)
                break
            }
            
        default:
            break
        }
    }
    
    public func createdChannel(_ model: SessionModels.BaseCommunication) async {
        do {
            let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
            guard let props = await model.props(symmetricKey: symmetricKey) else {
                logger.log(level: .debug, message: "Could not get communication type from channel model")
                return
            }
            
            // Only add if it's actually a channel type
            switch props.communicationType {
            case .channel(let channelName):
                logger.log(level: .info, message: "Channel created: \(model.id)")
                // Check if channel already exists
                if !channels.contains(where: { $0.id == model.id }) {
                    channels.append(model)
                    logger.log(level: .info, message: "Added channel to list: \(channelName)")
                    channelContinuation?.yield(.newValue(model))
                } else {
                    logger.log(level: .debug, message: "Channel already in list: \(channelName)")
                }
            default:
                logger.log(level: .debug, message: "Created communication is not a channel type: \(props.communicationType)")
            }
        } catch {
            logger.log(level: .error, message: "Error processing created channel: \(error)")
            // If there's an error, try to reload channels from cache as fallback
            await loadChannels()
        }
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
    
    public func transportContactMetadata() async throws {
        logger.log(level: .info, message: "Transporting contact metadata")
        // Handle transporting contact metadata
        // This could involve sending contact information to other devices
    }
    
    public func removedContact(_ secretName: String) async throws {
        logger.log(level: .info, message: "Contact removed: \(secretName)")
        // Remove from local contacts list
        contacts.removeAll { $0.secretName == secretName }
        
        if let contact = contacts.first(where: { $0.secretName == secretName }) {
            contactContinuation?.yield(.removed(contact))
        }
    }
    
    public func updateContact(_ contact: Contact) async throws {
        logger.log(level: .info, message: "Contact updated callback triggered for: \(contact.secretName) (id: \(contact.id))")
        // Update contact in local list if it exists
        if let existingIndex = contacts.firstIndex(where: { $0.id == contact.id || $0.secretName == contact.secretName }) {
            logger.log(level: .info, message: "Updating existing contact in list: \(contact.secretName)")
            contacts[existingIndex] = contact
            contactContinuation?.yield(.updated(contact))
        } else {
            logger.log(level: .info, message: "Contact not found in list, adding: \(contact.secretName)")
            contacts.append(contact)
            contactContinuation?.yield(.newValue(contact))
        }
        logger.log(level: .info, message: "Contact list now has \(contacts.count) contacts")
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
        
        // Update channel if it exists in the list
        if let index = channels.firstIndex(where: { $0.id == model.id }) {
            channels[index] = model
            channelContinuation?.yield(.updated(model))
        }
    }
    
    // MARK: - Loading Methods
    
    /// Load all contacts from the database
    /// Note: Contacts are primarily populated via the createdContact callback.
    /// This method attempts to load from cache, but if ContactModel != Contact, 
    /// it will rely on the callback to populate the list.
    public func loadContacts() async {
        // For now, skip loading from cache since ContactModel structure is unclear
        // Contacts will be populated via createdContact callback when they're created
        // This is fine for the demo, though contacts won't persist across app restarts
        // until they're recreated via the callback
        logger.log(level: .info, message: "Contacts will be loaded via createdContact callback")
    }
    
    public func loadMessage(for contact: Contact) async {
        do {
            guard let cache = await PQSSession.shared.cache else {
                logger.log(level: .warning, message: "No cache available to load channels")
                return
            }

            let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
            
            let communications = try await cache.fetchCommunications()
            let matching = try await communications.asyncFirst { comm in
                if let props = try await comm.props(symmetricKey: symmetricKey) {
                    return props.communicationType == .nickname(contact.secretName)
                }
                return false
            }
            
            // We want the communication's *id* (the same identifier used by
            // Apple ChatView via `fetchMessages(sharedCommunicationId:)`),
            // not the props.sharedId. Messages in the cache are indexed by
            // `message.communicationId`, which matches `BaseCommunication.id`.
            guard let communication = matching else {
                return
            }
            let communicationId = communication.id
            
            let messages = try await cache.streamMessages(sharedIdentifier: communicationId)
            for try await message in await messages.0 {
                self.messages.append(message)
                self.messageContinuation?.yield(.newValue(message))
            }
        } catch {
            logger.log(level: .error, message: "There was an error loading messages \(error)")
        }
    }
    
    /// Load all channels from the database
    public func loadChannels() async {
        do {
            guard let cache = await PQSSession.shared.cache else {
                logger.log(level: .warning, message: "No cache available to load channels")
                return
            }
            
            let allCommunications = try await cache.fetchCommunications()
            let symmetricKey = try await PQSSession.shared.getDatabaseSymmetricKey()
            
            var channelList: [BaseCommunication] = []
            for communication in allCommunications {
                guard let props = await communication.props(symmetricKey: symmetricKey) else {
                    continue
                }
                
                // Only include channel communications
                if case .channel = props.communicationType {
                    channelList.append(communication)
                }
            }
            
            // Update channels list, preserving any that might have been added via callback
            let existingIds = Set(channels.map { $0.id })
            let newChannels = channelList.filter { !existingIds.contains($0.id) }
            channels.append(contentsOf: newChannels)
            
            // Also update any existing channels that might have changed
            for newChannel in channelList {
                if let index = channels.firstIndex(where: { $0.id == newChannel.id }) {
                    channels[index] = newChannel
                }
            }
            
            logger.log(level: .info, message: "Loaded \(channels.count) channels (added \(newChannels.count) new ones)")
        } catch {
            logger.log(level: .error, message: "Error loading channels: \(error)")
        }
    }
    
    // MARK: - Observation-backed Streams
    
    /// Async stream of contact list changes backed by explicit continuations.
    public func contactsStream() -> AsyncStream<OnChangeEvent<Contact>> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            self.contactContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                //TODO: CLEAN UP
            }
        }
    }
    
    
    /// Async stream of message list changes backed by explicit continuations.
    public func messagesStream() -> AsyncStream<OnChangeEvent<EncryptedMessage>> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            self.messageContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                //TODO: CLEAN UP
            }
        }
    }

    /// Async stream of channel list changes backed by explicit continuations.
    public func channelsStream() -> AsyncStream<OnChangeEvent<BaseCommunication>> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            self.channelContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                //TODO: CLEAN UP
            }
        }
    }
}

@MainActor
public enum OnChangeEvent<T>: Sendable {
    case newValue(T)
    case removed(T)
    case updated(T)
}
