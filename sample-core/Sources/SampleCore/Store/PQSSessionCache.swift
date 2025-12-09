import Foundation
import NeedleTailLogger
import NeedleTailCrypto
import PQSSession
import Crypto
import SessionModels
import DoubleRatchetKit
import ConnectionManagerKit

/**
 _PQSSessionCache_ conforms to **PQSSessionStore**. This protocol is how **PostQuantumSolace** makes the required Database Actions, it is up to the consumer to implement the Database for PQSSession to function properly. Please read the **PQSSessionStore** documnetation in order to understand how to use each protocol method.
 **/

public actor PQSSessionCache: PQSSessionStore {
    
    public let crypto = NeedleTailCrypto()
    
    // Enum to define potential errors related to the database operations.
    public enum Errors: Error {
        case couldntFindObject, saltError, sessionContextNotAvailable
    }
    
    // MARK: - In-Memory Storage
    
    // Local session context storage
    private var localSessionContext: Data?
    
    // Device salt storage
    private var deviceSalt: Data?
    
    // Session identities storage
    private var sessionIdentities: [UUID: SessionIdentity] = [:]
    
    // Contacts storage
    private var contacts: [UUID: ContactModel] = [:]
    
    // Communications storage
    private var communications: [UUID: BaseCommunication] = [:]
    
    // Messages storage
    private var messages: [UUID: EncryptedMessage] = [:]
    private var messagesBySharedId: [String: UUID] = [:]
    private var messagesByCommunicationId: [UUID: [UUID]] = [:]
    
    // Jobs storage
    private var jobs: [UUID: JobModel] = [:]
    
    // Media jobs (DataPackets) storage
    private var mediaJobs: [UUID: DataPacket] = [:]
    
    // Server locations storage
    private var serverLocations: [UUID: ServerLocation] = [:]
    
    public init() {}
    
    // MARK: - Local Session Context Methods
    
    public func createLocalSessionContext(_ data: Data) async throws {
        self.assertIsolated()
        localSessionContext = data
        
        //        try await crypto.keychain.save(item: data.base64EncodedString(), with: .init(service: "com.needletails.PQSDemo.context"))
    }
    
    public func fetchLocalSessionContext() async throws -> Data {
        self.assertIsolated()
        guard let data = localSessionContext else {
            throw Errors.couldntFindObject
            //            let base64String = await crypto.keychain.fetchItem(configuration: .init(service: "com.needletails.PQSDemo.context"))
            //            return Data(base64Encoded: base64String!)!
        }
        return data
    }
    
    public func updateLocalSessionContext(_ data: Data) async throws {
        self.assertIsolated()
        localSessionContext = data
    }
    
    public func deleteLocalSessionContext() async throws {
        self.assertIsolated()
        localSessionContext = nil
    }
    
    // MARK: - Device Salt Methods
    
    public func generateSalt(length: Int) -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0.prefix(length)) }
    }
    
    public func fetchLocalDeviceSalt(keyData: Data) async throws -> Data {
        self.assertIsolated()
        //        if let base64String = await crypto.keychain.fetchItem(configuration: .init(service: "com.needletails.PQSDemo.salt")) {
        //            return Data(base64Encoded: base64String)!
        //        }
        if let existingSalt = deviceSalt {
            return existingSalt
        }
        
        let saltData = generateSalt(length: 64)
        deviceSalt = saltData
        //        try await crypto.keychain.save(item: deviceSalt!.base64EncodedString(), with: .init(service: "com.needletails.PQSDemo.salt"))
        return saltData
    }
    
    public func deleteLocalDeviceSalt() async throws {
        self.assertIsolated()
        deviceSalt = nil
    }
    
    // MARK: - Session Identity Methods
    
    public func createSessionIdentity(_ session: SessionIdentity) async throws {
        self.assertIsolated()
        sessionIdentities[session.id] = session
    }
    
    public func fetchSessionIdentities() async throws -> [SessionIdentity] {
        self.assertIsolated()
        return Array(sessionIdentities.values)
    }
    
    public func updateSessionIdentity(_ session: SessionIdentity) async throws {
        self.assertIsolated()
        sessionIdentities[session.id] = session
    }
    
    public func deleteSessionIdentity(_ id: UUID) async throws {
        self.assertIsolated()
        sessionIdentities.removeValue(forKey: id)
    }
    
    // MARK: - Contact Methods
    
    public func fetchContacts() async throws -> [ContactModel] {
        self.assertIsolated()
        return Array(contacts.values)
    }
    
    public func createContact(_ contact: ContactModel) async throws {
        self.assertIsolated()
        contacts[contact.id] = contact
    }
    
    public func updateContact(_ contact: ContactModel) async throws {
        self.assertIsolated()
        contacts[contact.id] = contact
    }
    
    public func deleteContact(_ id: UUID) async throws {
        self.assertIsolated()
        contacts.removeValue(forKey: id)
    }
    
    // MARK: - Communication Methods
    
    public func fetchCommunications() async throws -> [BaseCommunication] {
        self.assertIsolated()
        return Array(communications.values)
    }
    
    public func createCommunication(_ communication: BaseCommunication) async throws {
        self.assertIsolated()
        communications[communication.id] = communication
    }
    
    public func updateCommunication(_ communication: BaseCommunication) async throws {
        self.assertIsolated()
        communications[communication.id] = communication
    }
    
    public func deleteCommunication(_ communication: BaseCommunication) async throws {
        self.assertIsolated()
        communications.removeValue(forKey: communication.id)
    }
    
    // MARK: - Message Methods
    
    public func fetchMessages(sharedCommunicationId: UUID) async throws -> [MessageRecord] {
        self.assertIsolated()
        
        // Filter messages by communicationId
        var messageRecords: [MessageRecord] = []
        if let messageIds = messagesByCommunicationId[sharedCommunicationId] {
            for messageId in messageIds {
                if let message = messages[messageId] {
                    messageRecords.append(MessageRecord(sharedCommunicationId: sharedCommunicationId, message: message))
                }
            }
        }
        
        return messageRecords
    }
    
    public func fetchMessage(id: UUID) async throws -> EncryptedMessage {
        self.assertIsolated()
        
        guard let message = messages[id] else {
            throw Errors.couldntFindObject
        }
        
        return message
    }
    
    public func fetchMessage(sharedId: String) async throws -> EncryptedMessage {
        self.assertIsolated()
        
        guard let messageId = messagesBySharedId[sharedId],
              let message = messages[messageId] else {
            throw Errors.couldntFindObject
        }
        
        return message
    }
    
    public func createMessage(_ message: EncryptedMessage, symmetricKey: SymmetricKey) async throws {
        self.assertIsolated()
        
        messages[message.id] = message
        messagesBySharedId[message.sharedId] = message.id
        
        // Add to communication index
        if messagesByCommunicationId[message.communicationId] == nil {
            messagesByCommunicationId[message.communicationId] = []
        }
        messagesByCommunicationId[message.communicationId]?.append(message.id)
    }
    
    public func updateMessage(_ message: EncryptedMessage, symmetricKey: SymmetricKey) async throws {
        self.assertIsolated()
        
        messages[message.id] = message
        messagesBySharedId[message.sharedId] = message.id
    }
    
    public func deleteMessage(_ message: EncryptedMessage) async throws {
        self.assertIsolated()
        
        messages.removeValue(forKey: message.id)
        messagesBySharedId.removeValue(forKey: message.sharedId)
        messagesByCommunicationId[message.communicationId]?.removeAll { $0 == message.id }
    }
    
    public func streamMessages(sharedIdentifier: UUID) async throws -> (AsyncThrowingStream<EncryptedMessage, Error>, AsyncThrowingStream<EncryptedMessage, Error>.Continuation?) {
        self.assertIsolated()
        
        var streamContinuation: AsyncThrowingStream<EncryptedMessage, Error>.Continuation?
        let stream = AsyncThrowingStream(EncryptedMessage.self, bufferingPolicy: .unbounded) { continuation in
            streamContinuation = continuation
            
            Task {
                await self.assertIsolated()
                
                // Filter by the communicationId on each message. Despite the
                // parameter name, this identifier is the communication's id
                // (matching `BaseCommunication.id`), which is how the Apple
                // ChatView fetches messages as well.
                for message in self.messages.values {
                    if message.communicationId == sharedIdentifier {
                        continuation.yield(message)
                    }
                }
                continuation.finish()
            }
        }
        
        return (stream, streamContinuation)
    }
    
    public func messageCount(sharedIdentifier: UUID) async throws -> Int {
        self.assertIsolated()
        
        // Count only messages whose communicationId matches this identifier.
        return messages.values.reduce(0) { partial, message in
            partial + (message.communicationId == sharedIdentifier ? 1 : 0)
        }
    }
    
    // MARK: - Job Methods
    
    public func fetchJobs() async throws -> [JobModel] {
        self.assertIsolated()
        return Array(jobs.values)
    }
    
    public func createJob(_ job: JobModel) async throws {
        self.assertIsolated()
        jobs[job.id] = job
    }
    
    public func updateJob(_ job: JobModel) async throws {
        self.assertIsolated()
        jobs[job.id] = job
    }
    
    public func deleteJob(_ job: JobModel) async throws {
        self.assertIsolated()
        jobs.removeValue(forKey: job.id)
    }
    
    // MARK: - Media Job Methods
    
    public func createMediaJob(_ packet: DataPacket) async throws {
        self.assertIsolated()
        mediaJobs[packet.id] = packet
    }
    
    public func fetchAllMediaJobs() async throws -> [DataPacket] {
        self.assertIsolated()
        return Array(mediaJobs.values)
    }
    
    public func fetchMediaJob(id: UUID) async throws -> DataPacket? {
        self.assertIsolated()
        
        guard let packet = mediaJobs[id] else {
            throw Errors.couldntFindObject
        }
        
        return packet
    }
    
    public func fetchMediaJobs(recipient: String, symmetricKey: SymmetricKey) async throws -> [DataPacket] {
        self.assertIsolated()
        
        // Simplified implementation - return all packets
        // In a real implementation, you'd decrypt and filter by recipient
        return Array(mediaJobs.values)
    }
    
    public func fetchMediaJob(synchronizationIdentifier: String, symmetricKey: SymmetricKey) async throws -> DataPacket? {
        self.assertIsolated()
        
        // Simplified implementation - return nil
        // In a real implementation, you'd decrypt and search by synchronizationIdentifier
        return nil
    }
    
    public func deleteMediaJob(_ id: UUID) async throws {
        self.assertIsolated()
        mediaJobs.removeValue(forKey: id)
    }
    
    // MARK: - Server Location Methods
    
    public func createServerLocation(_ id: UUID, data: Data) async throws {
        self.assertIsolated()
        let location = ServerLocation(id: id, data: data)
        serverLocations[id] = location
    }
    
    public func updateServerLocation(_ id: UUID, data: Data) async throws {
        self.assertIsolated()
        let location = ServerLocation(id: id, data: data)
        serverLocations[id] = location
    }
    
    public func findServerLocation(_ id: UUID) async throws -> ServerLocation? {
        self.assertIsolated()
        
        guard let location = serverLocations[id] else {
            throw Errors.couldntFindObject
        }
        
        return location
    }
    
    public func findServerLocations() async throws -> [ServerLocation] {
        self.assertIsolated()
        return Array(serverLocations.values)
    }
    
    public func deleteServerLocation(_ id: UUID) async throws {
        self.assertIsolated()
        serverLocations.removeValue(forKey: id)
    }
    
    public func deleteServerLocations() async throws {
        self.assertIsolated()
        serverLocations.removeAll()
    }
}

// MARK: - Helper Extensions

extension Array {
    public func asyncFilter(_ predicate: @escaping (Element) async throws -> Bool) async rethrows -> [Element] {
        var result: [Element] = []
        for element in self {
            if try await predicate(element) {
                result.append(element)
            }
        }
        return result
    }
    
    public func asyncFirst(where predicate: @escaping @Sendable (Element) async throws -> Bool) async rethrows -> Element? {
        for element in self {
            if try await predicate(element) {
                return element
            }
        }
        return nil
    }
}

public struct ServerLocation: Codable, Sendable {
    public let id: UUID
    public let data: Data
    
    public init(id: UUID, data: Data) {
        self.id = id
        self.data = data
    }
}
