//
//  PQSController.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import Foundation
import Hummingbird
import HummingbirdHTTP2
import HummingbirdRouter
import BSON
import CryptoKit

import AsyncAlgorithms
import ServiceLifecycle

enum Errors: Error {
    case invalidSignature, userNotFound, missingParameter, verificationFailed, invalidKeySize
}

public enum MessageFlag: String, Codable, Sendable {
    case publishUserConfiguration, friendshipStateRequest, communicationSynchronization, contactCreated, addContacts, privateMessage
}

public struct SignedRatchetMessage: Codable & Sendable {
    
    /// Optional signed representation of the configuration.
    public var signed: Signed?
    
    /// Coding keys for encoding and decoding the struct.
    public enum CodingKeys: String, CodingKey, Codable & Sendable {
        case signed = "a"
    }
    
    /// A struct representing the signed version of the user device configuration.
    public struct Signed: Codable & Sendable {
        
        /// The encoded encrypted data for the message
        let data: Data
        /// The generated signature.
        let signature: Data
        
        /// Coding keys for encoding and decoding the signed struct.
        enum CodingKeys: String, CodingKey, Codable & Sendable {
            case data = "a"
            case signature = "c"
        }
    }
}

public struct MessagePacket: Codable, Sendable, Equatable {

    public let id: String
    public let flag: MessageFlag
    public let userConfiguration: UserConfiguration?
    public let senderSecretName: String?
    public let sender: UUID?
    public let recipientSecretName: String?
    public let recipient: UUID?
    public let message: SignedRatchetMessage?

    public init(
        id: String,
        flag: MessageFlag,
        userConfiguration: UserConfiguration? = nil,
        senderSecretName: String? = nil,
        sender: UUID? = nil,
        recipientSecretName: String? = nil,
        recipient: UUID? = nil,
        message: SignedRatchetMessage? = nil,
    ) {
        self.id = id
        self.flag = flag
        self.userConfiguration = userConfiguration
        self.senderSecretName = senderSecretName
        self.sender = sender
        self.recipientSecretName = recipientSecretName
        self.recipient = recipient
        self.message = message
    }
    
    public static func == (lhs: MessagePacket, rhs: MessagePacket) -> Bool {
        return lhs.id == rhs.id
    }
}

struct PQSController {

    func addRoutes(to router: Router<BasicRequestContext>, store: PQSCache) {

        router.get("/api/auth/find-configuration/:secretName") { request, context in
            return try await self.findConfiguration(request: request, context: context, store: store)
        }
        
        router.get("/api/auth/one-time-keys/:secretName/:deviceId") { request, context in
            return try await fetchOneTimeCurveKeyIdentites(request: request, context: context, store: store)
        }
        
        router.post("/api/auth/one-time-keys/a/identities/:secretName/:deviceId") { request, context in
            return try await fetchOneTimeKyberKeyIdentites(request: request, context: context, store: store)
        }
        
        router.post("/api/auth/one-time-keys/b/identities/:secretName/:deviceId") { request, context in
            return try await fetchOneTimeKeys(request: request, context: context, store: store)
        }
    }
    
    func findConfiguration(request: Request, context: BasicRequestContext, store: PQSCache) async throws -> UserConfiguration {
        guard let secretName = context.parameters.get("secretName") else {
            throw Errors.missingParameter
        }
        do {
            guard let user = await store.findUser(secretName: secretName) else {
                throw HTTPError(.init(code: 998, reasonPhrase: "User not found"))
            }
            return user.configuration
        } catch {
            throw error
        }
    }
    
    func fetchOneTimeCurveKeyIdentites(request: Request, context: BasicRequestContext, store: PQSCache) async throws -> Data {
        guard let secretName = context.parameters.get("secretName"),
              let deviceId = context.parameters.get("deviceId")
        else {
            throw Errors.missingParameter
        }
        
        guard let user = await store.findUser(secretName: secretName) else { throw Errors.userNotFound }
        let keys = user.configuration.signedPublicOneTimeKeys.filter({ $0.deviceId.uuidString == deviceId }).compactMap({ $0.id })
        let data = try BSONEncoder().encode(keys).makeData()
        return data
    }
    
    func fetchOneTimeKyberKeyIdentites(request: Request, context: BasicRequestContext, store: PQSCache) async throws -> Data {
        guard let secretName = context.parameters.get("secretName"),
              let deviceId = context.parameters.get("deviceId")
        else {
            throw Errors.missingParameter
        }
        
        guard let user = await store.findUser(secretName: secretName) else { throw Errors.userNotFound }
        let keys = user.configuration.signedPublicKyberOneTimeKeys.filter({ $0.deviceId.uuidString == deviceId }).compactMap({ $0.id })
        let data = try BSONEncoder().encode(keys).makeData()
        return data
    }
    
    func fetchOneTimeKeys(request: Request, context: BasicRequestContext, store: PQSCache) async throws -> OneTimeKeys {
        guard let secretName = context.parameters.get("secretName"),
              let deviceId = context.parameters.get("deviceId")
        else {
            throw Errors.missingParameter
        }
        
        guard var user = await store.findUser(secretName: secretName) else { throw Errors.userNotFound }
        let curve = user.configuration.signedPublicOneTimeKeys.last(where: { $0.deviceId.uuidString == deviceId })
        let kyber = user.configuration.signedPublicKyberOneTimeKeys.last(where: { $0.deviceId.uuidString == deviceId })
        
        guard let verifiedDevice = try user.configuration.getVerifiedDevices().first(where: { $0.deviceId.uuidString == deviceId }) else {
            throw Errors.verificationFailed
        }
        let signingPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: verifiedDevice.signingPublicKey)
        
        
        user.configuration.signedPublicOneTimeKeys.removeAll(where: { $0.id == curve?.id })
        user.configuration.signedPublicKyberOneTimeKeys.removeAll(where: { $0.id == kyber?.id })
        
        user.updateConfiguration(user.configuration)
        
        await store.updateUser(user: user)
        
        
        let keys = OneTimeKeys(
            curve: try curve?.verified(using: signingPublicKey),
            kyber: try kyber?.kyberVerified(using: signingPublicKey))
        return keys
    }
}

extension UserConfiguration: ResponseGenerator {
    public func response(from request: HummingbirdCore.Request, context: some Hummingbird.RequestContext) throws -> HummingbirdCore.Response {
            let byteBuffer = try BSONEncoder().encode(self).makeByteBuffer()
            return Response(
                status: .ok,
                body: .init(byteBuffer: byteBuffer)
            )
        }
}

extension Data: @retroactive ResponseGenerator {
    public func response(from request: HummingbirdCore.Request, context: some Hummingbird.RequestContext) throws -> HummingbirdCore.Response {
        return Response(
            status: .ok,
            body: .init(byteBuffer: ByteBuffer(data: self))
        )
    }
}

extension OneTimeKeys: ResponseGenerator {
    public func response(from request: HummingbirdCore.Request, context: some Hummingbird.RequestContext) throws -> HummingbirdCore.Response {
        let byteBuffer = try BSONEncoder().encode(self).makeByteBuffer()
        return Response(
            status: .ok,
            body: .init(byteBuffer: byteBuffer)
        )
    }
}


