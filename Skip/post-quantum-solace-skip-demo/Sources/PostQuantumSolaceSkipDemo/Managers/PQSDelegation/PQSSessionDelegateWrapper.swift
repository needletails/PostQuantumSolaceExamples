//
//  PQSSessionDelegateWrapper.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import Foundation
import PQSSession
import BSON
import NeedleTailLogger

/**
 _PQSSessionDelegateWrapper_ conforms to **PQSSessionDelegate**. This protocol is how **PostQuantumSolace** allows the consumer to hook into the sessions behavior and customize in according to the needs of the consumer. It is required to perform certain behaviors at certain times. For proper behaviour it should follow the example as close as possible. Many times metadata needs to be updated at very certain points before or after encryption, but before transport,This delegation offers certain methods that allows access to the message before or after or gives the consumers the eaxt timing of when certian logic should be performed. Please read the **PQSSessionDelegate** documnetation in order to understand how to use each protocol method.
 **/
public final class PQSSessionDelegateWrapper: PQSSessionDelegate, @unchecked Sendable {
    
    // MARK: - Properties
    internal unowned let messageReciever: MessageReceiverManager
    internal let pqsSession: PQSSession
    internal let logger: NeedleTailLogger
    
    // MARK: - Initialization
    
    internal init(
        pqsSession: PQSSession,
        messageReciever: MessageReceiverManager,
        logger: NeedleTailLogger
    ) {
        self.pqsSession = pqsSession
        self.messageReciever = messageReciever
        self.logger = logger
    }
    
    // MARK: - PQSSessionDelegate Implementation
    
    public func synchronizeCommunication(recipient: SessionModels.MessageRecipient, sharedIdentifier: String) async throws {
        logger.log(level: .info, message: "Synchronizing communication with recipient: \(recipient)")
        // Handle communication synchronization
        // This could involve establishing secure channels or exchanging metadata
        let transportInfo = TransportMetadata(
            messageFlag: .communicationSynchronization)
        let transportData = try BSONEncoder().encodeData(transportInfo)
        
        try await self.pqsSession.writeTextMessage(
            recipient: recipient,
            text: sharedIdentifier,
            transportInfo: transportData,
            metadata: [:])
    }
    
    public func requestFriendshipStateChange(
        recipient: SessionModels.MessageRecipient,
        blockData: Data?,
        metadata: BSON.Document,
        currentState: SessionModels.FriendshipMetadata.State
    ) async throws {
        logger.log(level: .info, message: "Requesting friendship state change for: \(recipient)")
        // Handle friendship state changes (block/unblock, add/remove friend)
        // This could involve updating contact lists and communication permissions
        let transportInfo = TransportMetadata(
            messageFlag: .friendshipStateRequest)
        let transportData = try BSONEncoder().encodeData(transportInfo)
        try await self.pqsSession.writeTextMessage(
            recipient: recipient,
            transportInfo: transportData,
            metadata: metadata)
    }
    
    public func deliveryStateChanged(recipient: MessageRecipient, metadata: BSON.Document) async throws {
        logger.log(level: .info, message: "Delivery state changed for: \(recipient)")
        // Handle message delivery state changes (sent, delivered, read)
        // This could involve updating UI indicators
    }
    
    public func contactCreated(recipient: MessageRecipient) async throws {
        logger.log(level: .info, message: "Contact created: \(recipient)")
        // Handle contact creation
        // This could involve adding to contact list and establishing secure communication
        let transportInfo = TransportMetadata(
            messageFlag: .contactCreated)
        let transportData = try BSONEncoder().encodeData(transportInfo)
        
        try await self.pqsSession.writeTextMessage(
            recipient: recipient,
            transportInfo: transportData,
            metadata: [:])
    }
    
    public func requestMetadata(recipient: MessageRecipient) async throws {
        logger.log(level: .info, message: "Requesting metadata for: \(recipient)")
        // Handle metadata requests
        // This could involve fetching user information, keys, or other metadata
    }
    
    public func editMessage(recipient: MessageRecipient, metadata: BSON.Document) async throws {
        logger.log(level: .info, message: "Editing message for: \(recipient)")
        // Handle message editing
        // This could involve updating message content and notifying recipients
    }
    
    public func shouldPersist(transportInfo: Data?) -> Bool {
        logger.log(level: .debug, message: "Checking if should persist transport info")
        // Determine if transport information should be persisted
        // For demo purposes, always persist
        return true
    }
    
    public func retrieveUserInfo(_ transportInfo: Data?) async -> (secretName: String, deviceId: String)? {
        logger.log(level: .debug, message: "Retrieving user info from transport")
        // Retrieve user information from transport data
        // For demo purposes, return nil (would need to parse transportInfo)
        return nil
    }
    
    public func updateEncryptableMessageMetadata(
        _ message: SessionModels.EncryptedMessage,
        transportInfo: Data?,
        identity: SessionIdentity,
        recipient: MessageRecipient
    ) async -> SessionModels.EncryptedMessage {
        logger.log(level: .debug, message: "Updating encryptable message metadata")
        // Update message metadata before encryption
        // Could add timestamps, delivery preferences, etc.
        return message
    }
    
    public func updateCryptoMessageMetadata(_ message: CryptoMessage, sharedMessageId: String) -> CryptoMessage {
        logger.log(level: .debug, message: "Updating crypto message metadata")
        // Update crypto message metadata
        // Could add encryption timestamps, key information, etc.
        return message
    }
    
    public func shouldFinishCommunicationSynchronization(_ transportInfo: Data?) -> Bool {
        logger.log(level: .debug, message: "Checking if should finish communication synchronization")
        // Determine if communication synchronization should be finished
        // For demo purposes, always continue synchronization
        guard let transportInfo else { return false }
        do {
            let transportMetadata = try BSONDecoder().decodeData(TransportMetadata.self, from: transportInfo)
            switch transportMetadata.messageFlag {
            case .communicationSynchronization:
                return true
            default:
                return false
            }
        } catch {
            return false
        }
    }
    
    public func processMessage(
        _ message: CryptoMessage,
        senderSecretName: String,
        senderDeviceId: UUID
    ) async -> Bool {
        logger.log(level: .info, message: "Processing message from: \(senderSecretName)")
        do {
            if let key = message.metadata["should-persist"], key as? Bool == true {
                return true // If we are persisting messages return true
            }
            guard let transportData = message.transportInfo else { return false }
            let transportMetadata = try BSONDecoder().decode(TransportMetadata.self, from: Document(data: transportData))
            guard let cache = await pqsSession.cache else { return false }
            switch transportMetadata.messageFlag {
            case .friendshipStateRequest:
                // Create/Update Contact and modify metadata
                var decodedMetadata = try BSONDecoder().decode(FriendshipMetadata.self, from: message.metadata["friendshipMetadata"] as? Document ?? [:])
                
                decodedMetadata.swapUserPerspectives()
                
                //Update our state based on the state of the sender and it's metadata.
                switch decodedMetadata.theirState {
                case .pending:
                    
                    decodedMetadata.resetToPendingState()
                    
                    let symmetricKey = try await pqsSession.getDatabaseSymmetricKey()
                    guard let sessionIdentity = try await pqsSession.cache?.fetchSessionIdentities().async.first(where: { await $0.props(symmetricKey: symmetricKey)?.deviceId == senderDeviceId }) else {
                        throw PQSSession.SessionErrors.missingSessionIdentity
                    }
                    try await pqsSession.cache?.deleteSessionIdentity(sessionIdentity.id)
                    await pqsSession.removeIdentity(with: senderSecretName)
                    
                case .requested:
                    decodedMetadata.setRequestedState()
                case .accepted:
                    decodedMetadata.setAcceptedState()
                case .blocked, .blockedByOther:
                    decodedMetadata.setBlockState(isBlocking: true)
                case .unblocked:
                    decodedMetadata.setAcceptedState()
                default:
                    break
                }
                
                let encodedMetadata = try BSONEncoder().encode(decodedMetadata)
                guard let mySecretName = await pqsSession.sessionContext?.sessionUser.secretName else { return false }
                
                self.logger.log(level: .info, message: "Requested friendship state change for \(mySecretName) to state \(decodedMetadata.theirState).")
                
                let isMe = senderSecretName == mySecretName
                
                //Create or update contact including new metadata
                _ = try await pqsSession.createContact(
                    secretName: isMe ? message.recipient.nicknameDescription : senderSecretName,
                    metadata: ["friendshipMetadata": encodedMetadata],
                    requestFriendship: false)
            case .communicationSynchronization:
                guard !message.text.isEmpty else { return false }
                self.logger.log(level: .debug, message: "Received Communication Synchronization Message")
                let symmetricKey = try await pqsSession.getDatabaseSymmetricKey()
                
                //This can happen on multidevice support when a sender is also sending a message to it's master/child device.
                guard let mySecretName = await pqsSession.sessionContext?.sessionUser.secretName else { return false }
                let isMe = senderSecretName == mySecretName
                
                var communicationModel: BaseCommunication?
                do {
                    //Need to flop sender/recipient
                    communicationModel = try await pqsSession.findCommunicationType(
                        cache: cache,
                        communicationType: .nickname(isMe ? message.recipient.nicknameDescription : senderSecretName),
                        symmetricKey: symmetricKey)
                } catch {
                    //Need to flop sender/recipient
                    communicationModel = try await pqsSession.createCommunicationModel(
                        recipients: [message.recipient.nicknameDescription, senderSecretName],
                        communicationType: .nickname(isMe ? mySecretName : senderSecretName),
                        metadata: message.metadata,
                        symmetricKey: symmetricKey
                    )
                    guard let communicationModel = communicationModel else { return false }
                    try await cache.createCommunication(communicationModel)
                }
                
                guard let communicationModel = communicationModel else { return false }
                self.logger.log(level: .debug, message: "Found Communication Model For Synchronization: \(communicationModel)")
                var props = await communicationModel.props(symmetricKey: symmetricKey)
                props?.sharedId = UUID(uuidString: message.text)
                _ = try await communicationModel.updateProps(symmetricKey: symmetricKey, props: props)
                try await cache.updateCommunication(communicationModel)
                if let members = props?.members {
                    await messageReciever.updatedCommunication(communicationModel, members: members)
                }
                self.logger.log(level: .debug, message: "Updated Communication Model For Synchronization with Shared Id: \(String(describing: props?.sharedId))")
                
                _ = try await pqsSession.refreshIdentities(secretName: senderSecretName, forceRefresh: true)
            case .contactCreated:
                guard let mySecretName = await pqsSession.sessionContext?.sessionUser.secretName else { return false }
                //This can happen on multidevice support when a sender is also sending a message to it's master/child device.
                let isMe = senderSecretName == mySecretName
                self.logger.log(level: .debug, message: "Received Contact Request Recipient Created Contact Message")
                try await pqsSession.sendCommunicationSynchronization(contact: isMe ? message.recipient.nicknameDescription : senderSecretName)
            case .addContacts:
                let contacts = try BSONDecoder().decode([SharedContactInfo].self, from: message.metadata)
                try await pqsSession.addContacts(contacts)
            default:
                guard let sessionContext = await pqsSession.sessionContext else { return false }
                let mySecretName = sessionContext.sessionUser.secretName
                let myDeviceId = sessionContext.sessionUser.deviceId.uuidString
                //This can happen on multidevice support when a sender is also sending a message to it's master/child device.
                let isMe = senderSecretName == mySecretName
                
                //Passthrough nothing special to do
                await messageReciever.receivedLocalNudge(
                    message,
                    sender: isMe ? mySecretName : senderSecretName,
                    senderDeviceId: isMe ? myDeviceId : senderDeviceId.uuidString)
            }
            return true
        } catch {
            return false
        }
        
    }
}
