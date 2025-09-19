//
//  SessionTransportManager.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PQSSession
import NeedleTailLogger
import BSON
import NeedleTailIRC

/**
 _SessionTransportManager_ conforms to **SessionTransport**. This protocol is how **PostQuantumSolace** makes the required Network Calls, it is up to the consumer to implement transport for PQSSession to function properly. Please read the **SessionTransport** documnetation in order to understand how to use each protocol method.
 **/

actor SessionTransportManager: SessionTransport {
    
    // MARK: - Properties
    let logger: NeedleTailLogger
    private var connection: IRCConnection?
    
    // MARK: - Initialization
    
    init(logger: NeedleTailLogger) {
        self.logger = logger
    }
    
    // MARK: - Public Methods
    
    func setConnection(_ connection: IRCConnection) async {
        self.connection = connection
        logger.log(level: .info, message: "IRC connection set for transport")
    }
    
    // MARK: - SessionTransport Implementation
    
    public func sendMessage(
        _ message: SignedRatchetMessage,
        metadata: SignedRatchetMessageMetadata
    ) async throws {
        logger.log(level: .info, message: "Sending signed ratchet message")
        
        guard let connection = connection else {
            logger.log(level: .error, message: "No IRC connection available for sending message")
            throw SessionTransportError.noConnection
        }
        
        guard let senderDeviceId = await PQSSession.shared.sessionContext?.sessionUser.deviceId else {
            throw NeedleTailError.deviceIdNil
        }
        
        // Convert message to IRC format and send
        let packet = MessagePacket(
            id: UUID().uuidString,
            flag: .privateMessage,
            sender: senderDeviceId,
            message: message)
        
        let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()

        // For now, send to all recipients as the metadata doesn't contain recipient info
        // This will be improved when recipient information is properly passed through the metadata
        try await connection.transportMessage(
            command: IRCCommand.privMsg([.nick(NeedleTailNick(name: metadata.secretName, deviceId: metadata.deviceId)!)], encodedString)
        )
        
        logger.log(level: .info, message: "Message sent successfully")
    }
    
    public func publishUserConfiguration(_ configuration: UserConfiguration, recipient identity: UUID) async throws {
        logger.log(level: .info, message: "Publishing user configuration")
        
        guard let name = await PQSSession.shared.sessionContext?.sessionUser.secretName else {
            throw SessionTransportError.sessionNotAvailable
        }
        
        guard let myDeviceIdentity = await PQSSession.shared.sessionContext?.sessionUser.deviceId else {
            throw SessionTransportError.deviceIdNotAvailable
        }
        
        let packet = MessagePacket(
            id: UUID().uuidString,
            flag: .publishUserConfiguration,
            userConfiguration: configuration,
            sender: myDeviceIdentity
        )
        
        let encodedString = try BSONEncoder().encode(packet).makeData().base64EncodedString()
        
        guard let validatedName = NeedleTailNick(name: name, deviceId: myDeviceIdentity) else {
            throw SessionTransportError.invalidNickname
        }
        
        try await connection?.transportMessage(
            command: IRCCommand.privMsg([.nick(validatedName)], encodedString)
        )
        
        logger.log(level: .info, message: "User configuration published successfully")
    }
    
    func findConfiguration(for secretName: String) async throws -> SessionModels.UserConfiguration {
        logger.log(level: .info, message: "Finding configuration for: \(secretName)")
        
        let response: Response<UserConfiguration> = try await URLSession.shared.request(
            httpHost: AppConfiguration.API.baseURL,
            url: "api/auth/find-configuration/\(secretName)",
            nickname: secretName,
            token: nil
        )
        
        guard let configuration = response.data else {
            if let httpResponse = response.urlResponse as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 997:
                    throw PQSSession.SessionErrors.missingAuthInfo
                case 998:
                    throw PQSSession.SessionErrors.userNotFound
                case 999:
                    throw PQSSession.SessionErrors.accessDenied
                default:
                    throw PQSSession.SessionErrors.cannotFindUserConfiguration
                }
            } else {
                throw PQSSession.SessionErrors.cannotFindUserConfiguration
            }
        }
        
        logger.log(level: .info, message: "Configuration found for: \(secretName)")
        return configuration
    }
    
    func fetchOneTimeKeys(for secretName: String, deviceId: String) async throws -> SessionModels.OneTimeKeys {
        logger.log(level: .info, message: "Fetching one-time keys for: \(secretName)/\(deviceId)")
        
        let response: Response<OneTimeKeys> = try await URLSession.shared.request(
            httpHost: AppConfiguration.API.baseURL,
            url: "api/auth/one-time-keys/\(secretName)/\(deviceId)",
            nickname: secretName,
            token: nil
        )
        
        guard let keys = response.data else {
            if let httpResponse = response.urlResponse as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 997:
                    throw PQSSession.SessionErrors.missingAuthInfo
                case 998:
                    throw PQSSession.SessionErrors.userNotFound
                case 999:
                    throw PQSSession.SessionErrors.accessDenied
                default:
                    throw PQSSession.SessionErrors.cannotFindOneTimeKey
                }
            } else {
                throw PQSSession.SessionErrors.cannotFindOneTimeKey
            }
        }
        
        logger.log(level: .info, message: "One-time keys fetched successfully")
        return keys
    }
    
    func fetchOneTimeKeyIdentities(for secretName: String, deviceId: String, type: SessionModels.KeysType) async throws -> [UUID] {
        logger.log(level: .info, message: "Fetching one-time key identities for: \(secretName)/\(deviceId)")
        
        let response: Response<Data> = try await URLSession.shared.request(
            httpHost: AppConfiguration.API.baseURL,
            url: "api/auth/one-time-keys/\(type == .curve ? "a" : "b")/identities/\(secretName)/\(deviceId)",
            nickname: secretName,
            token: nil
        )
        
        guard let data = response.data else {
            if let httpResponse = response.urlResponse as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 997:
                    throw PQSSession.SessionErrors.missingAuthInfo
                case 998:
                    throw PQSSession.SessionErrors.userNotFound
                case 999:
                    throw PQSSession.SessionErrors.accessDenied
                default:
                    throw PQSSession.SessionErrors.cannotFindOneTimeKey
                }
            } else {
                throw PQSSession.SessionErrors.cannotFindOneTimeKey
            }
        }
        
        let identities = try BSONDecoder().decodeData([UUID].self, from: data)
        logger.log(level: .info, message: "One-time key identities fetched: \(identities.count) keys")
        return identities
    }
    
    func updateOneTimeKeys(for secretName: String, deviceId: String, keys: [SessionModels.UserConfiguration.SignedOneTimePublicKey]) async throws {
        logger.log(level: .info, message: "Updating one-time keys for: \(secretName)/\(deviceId)")
        // Implementation would go here for updating keys
        logger.log(level: .info, message: "One-time keys updated successfully")
    }
    
    func updateOneTimePQKemKeys(for secretName: String, deviceId: String, keys: [SessionModels.UserConfiguration.SignedPQKemOneTimeKey]) async throws {
        logger.log(level: .info, message: "Updating PQKem one-time keys for: \(secretName)/\(deviceId)")
        // Implementation would go here for updating PQKem keys
        logger.log(level: .info, message: "PQKem one-time keys updated successfully")
    }
    
    func batchDeleteOneTimeKeys(for secretName: String, with id: String, type: SessionModels.KeysType) async throws {
        logger.log(level: .info, message: "Batch deleting one-time keys for: \(secretName)")
        // Implementation would go here for batch deletion
        logger.log(level: .info, message: "One-time keys batch deleted successfully")
    }
    
    func deleteOneTimeKeys(for secretName: String, with id: String, type: SessionModels.KeysType) async throws {
        logger.log(level: .info, message: "Deleting one-time keys for: \(secretName)")
        // Implementation would go here for deletion
        logger.log(level: .info, message: "One-time keys deleted successfully")
    }
    
    func publishRotatedKeys(for secretName: String, deviceId: String, rotated keys: SessionModels.RotatedPublicKeys) async throws {
        logger.log(level: .info, message: "Publishing rotated keys for: \(secretName)/\(deviceId)")
        // Implementation would go here for publishing rotated keys
        logger.log(level: .info, message: "Rotated keys published successfully")
    }
    
    func createUploadPacket(secretName: String, deviceId: UUID, recipient: SessionModels.MessageRecipient, metadata: BSON.Document) async throws {
        logger.log(level: .info, message: "Creating upload packet for: \(secretName)")
        // Implementation would go here for creating upload packets
        logger.log(level: .info, message: "Upload packet created successfully")
    }
}

// MARK: - Errors
extension SessionTransportManager {
    enum SessionTransportError: Error {
        case noConnection
        case sessionNotAvailable
        case deviceIdNotAvailable
        case invalidNickname
        case invalidRecipient
    }
}
