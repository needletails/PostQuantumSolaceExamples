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

actor PQSSessionCache: PQSSessionStore {

    let crypto = NeedleTailCrypto()
    
    // Enum to define potential errors related to the database operations.
    enum Errors: Error {
        case couldntFindObject, saltError
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
    
    init() {}
    
    // MARK: - Local Session Context Methods
    
    func createLocalSessionContext(_ data: Data) async throws {
        self.assertIsolated()
        localSessionContext = data
        
//        try await crypto.keychain.save(item: data.base64EncodedString(), with: .init(service: "com.needletails.PQSDemo.context"))
    }
    
    func fetchLocalSessionContext() async throws -> Data {
        self.assertIsolated()
        guard let data = localSessionContext else {
            fatalError()
//            let base64String = await crypto.keychain.fetchItem(configuration: .init(service: "com.needletails.PQSDemo.context"))
//            return Data(base64Encoded: base64String!)!
        }
        return data
    }
    
    func updateLocalSessionContext(_ data: Data) async throws {
        self.assertIsolated()
        localSessionContext = data
    }
    
    func deleteLocalSessionContext() async throws {
        self.assertIsolated()
        localSessionContext = nil
    }
    
    // MARK: - Device Salt Methods
    
    func generateSalt(length: Int) -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0.prefix(length)) }
    }
    
    func fetchLocalDeviceSalt(keyData: Data) async throws -> Data {
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
    
    func deleteLocalDeviceSalt() async throws {
        self.assertIsolated()
        deviceSalt = nil
    }
    
    // MARK: - Session Identity Methods
    
    func createSessionIdentity(_ session: SessionIdentity) async throws {
        self.assertIsolated()
        sessionIdentities[session.id] = session
    }
    
    func fetchSessionIdentities() async throws -> [SessionIdentity] {
        self.assertIsolated()
        return Array(sessionIdentities.values)
    }
    
    func updateSessionIdentity(_ session: SessionIdentity) async throws {
        self.assertIsolated()
        sessionIdentities[session.id] = session
    }
    
    func deleteSessionIdentity(_ id: UUID) async throws {
        self.assertIsolated()
        sessionIdentities.removeValue(forKey: id)
    }
    
    // MARK: - Contact Methods
    
    func fetchContacts() async throws -> [ContactModel] {
        self.assertIsolated()
        return Array(contacts.values)
    }
    
    func createContact(_ contact: ContactModel) async throws {
        self.assertIsolated()
        contacts[contact.id] = contact
    }
    
    func updateContact(_ contact: ContactModel) async throws {
        self.assertIsolated()
        contacts[contact.id] = contact
    }
    
    func deleteContact(_ id: UUID) async throws {
        self.assertIsolated()
        contacts.removeValue(forKey: id)
    }
    
    // MARK: - Communication Methods
    
    func fetchCommunications() async throws -> [BaseCommunication] {
        self.assertIsolated()
        return Array(communications.values)
    }
    
    func createCommunication(_ communication: BaseCommunication) async throws {
        self.assertIsolated()
        communications[communication.id] = communication
    }
    
    func updateCommunication(_ communication: BaseCommunication) async throws {
        self.assertIsolated()
        communications[communication.id] = communication
    }
    
    func deleteCommunication(_ communication: BaseCommunication) async throws {
        self.assertIsolated()
        communications.removeValue(forKey: communication.id)
    }
    
    // MARK: - Message Methods
    
    func fetchMessages(sharedCommunicationId: UUID) async throws -> [MessageRecord] {
        self.assertIsolated()
        
        var messageRecords: [MessageRecord] = []
        for (_, message) in messages {
            // Note: This is a simplified implementation. In a real scenario, you'd need to
            // decrypt the message to get the sharedCommunicationId or store it separately
            messageRecords.append(MessageRecord(sharedCommunicationId: sharedCommunicationId, message: message))
        }
        
        return messageRecords
    }
    
    func fetchMessage(id: UUID) async throws -> EncryptedMessage {
        self.assertIsolated()
        
        guard let message = messages[id] else {
            throw Errors.couldntFindObject
        }
        
        return message
    }
    
    func fetchMessage(sharedId: String) async throws -> EncryptedMessage {
        self.assertIsolated()
        
        guard let messageId = messagesBySharedId[sharedId],
              let message = messages[messageId] else {
            throw Errors.couldntFindObject
        }
        
        return message
    }
    
    func createMessage(_ message: EncryptedMessage, symmetricKey: SymmetricKey) async throws {
        self.assertIsolated()
        
        messages[message.id] = message
        messagesBySharedId[message.sharedId] = message.id
        
        // Add to communication index
        if messagesByCommunicationId[message.communicationId] == nil {
            messagesByCommunicationId[message.communicationId] = []
        }
        messagesByCommunicationId[message.communicationId]?.append(message.id)
    }
    
    func updateMessage(_ message: EncryptedMessage, symmetricKey: SymmetricKey) async throws {
        self.assertIsolated()
        
        messages[message.id] = message
        messagesBySharedId[message.sharedId] = message.id
    }
    
    func deleteMessage(_ message: EncryptedMessage) async throws {
        self.assertIsolated()
        
        messages.removeValue(forKey: message.id)
        messagesBySharedId.removeValue(forKey: message.sharedId)
        messagesByCommunicationId[message.communicationId]?.removeAll { $0 == message.id }
    }
    
    func streamMessages(sharedIdentifier: UUID) async throws -> (AsyncThrowingStream<EncryptedMessage, Error>, AsyncThrowingStream<EncryptedMessage, Error>.Continuation?) {
        self.assertIsolated()
        
        var streamContinuation: AsyncThrowingStream<EncryptedMessage, Error>.Continuation?
        let stream = AsyncThrowingStream(EncryptedMessage.self, bufferingPolicy: .unbounded) { continuation in
            streamContinuation = continuation
            
            Task { @MainActor in
                    // Simplified implementation - stream all messages
                    // In a real implementation, you'd filter by sharedIdentifier
                    for message in await self.messages.values {
                        continuation.yield(message)
                    }
                    continuation.finish()
            }
        }
        
        return (stream, streamContinuation)
    }
    
    func messageCount(sharedIdentifier: UUID) async throws -> Int {
        self.assertIsolated()
        
        // Simplified implementation - return total count
        // In a real implementation, you'd count messages for the specific sharedIdentifier
        return messages.count
    }
    
    // MARK: - Job Methods
    
    func fetchJobs() async throws -> [JobModel] {
        self.assertIsolated()
        return Array(jobs.values)
    }
    
    func createJob(_ job: JobModel) async throws {
        self.assertIsolated()
        jobs[job.id] = job
    }
    
    func updateJob(_ job: JobModel) async throws {
        self.assertIsolated()
        jobs[job.id] = job
    }
    
    func deleteJob(_ job: JobModel) async throws {
        self.assertIsolated()
        jobs.removeValue(forKey: job.id)
    }
    
    // MARK: - Media Job Methods
    
    func createMediaJob(_ packet: DataPacket) async throws {
        self.assertIsolated()
        mediaJobs[packet.id] = packet
    }
    
    func fetchAllMediaJobs() async throws -> [DataPacket] {
        self.assertIsolated()
        return Array(mediaJobs.values)
    }
    
    func fetchMediaJob(id: UUID) async throws -> DataPacket? {
        self.assertIsolated()
        
        guard let packet = mediaJobs[id] else {
            throw Errors.couldntFindObject
        }
        
        return packet
    }
    
    func fetchMediaJobs(recipient: String, symmetricKey: SymmetricKey) async throws -> [DataPacket] {
        self.assertIsolated()
        
        // Simplified implementation - return all packets
        // In a real implementation, you'd decrypt and filter by recipient
        return Array(mediaJobs.values)
    }
    
    func fetchMediaJob(synchronizationIdentifier: String, symmetricKey: SymmetricKey) async throws -> DataPacket? {
        self.assertIsolated()
        
        // Simplified implementation - return nil
        // In a real implementation, you'd decrypt and search by synchronizationIdentifier
        return nil
    }
    
    func deleteMediaJob(_ id: UUID) async throws {
        self.assertIsolated()
        mediaJobs.removeValue(forKey: id)
    }
    
    // MARK: - Server Location Methods
    
    func createServerLocation(_ id: UUID, data: Data) async throws {
        self.assertIsolated()
        let location = ServerLocation(id: id, data: data)
        serverLocations[id] = location
    }
    
    func updateServerLocation(_ id: UUID, data: Data) async throws {
        self.assertIsolated()
        let location = ServerLocation(id: id, data: data)
        serverLocations[id] = location
    }
    
    func findServerLocation(_ id: UUID) async throws -> ServerLocation? {
        self.assertIsolated()
        
        guard let location = serverLocations[id] else {
            throw Errors.couldntFindObject
        }
        
        return location
    }
    
    func findServerLocations() async throws -> [ServerLocation] {
        self.assertIsolated()
        return Array(serverLocations.values)
    }
    
    func deleteServerLocation(_ id: UUID) async throws {
        self.assertIsolated()
        serverLocations.removeValue(forKey: id)
    }
    
    func deleteServerLocations() async throws {
        self.assertIsolated()
        serverLocations.removeAll()
    }
}

// MARK: - Helper Extensions

extension Array {
    func asyncFilter(_ predicate: @escaping (Element) async throws -> Bool) async rethrows -> [Element] {
        var result: [Element] = []
        for element in self {
            if try await predicate(element) {
                result.append(element)
            }
        }
        return result
    }
    
    func asyncFirst(where predicate: @escaping (Element) async throws -> Bool) async rethrows -> Element? {
        for element in self {
            if try await predicate(element) {
                return element
            }
        }
        return nil
    }
}

struct ServerLocation: Codable, Sendable {
    let id: UUID
    let data: Data
}
