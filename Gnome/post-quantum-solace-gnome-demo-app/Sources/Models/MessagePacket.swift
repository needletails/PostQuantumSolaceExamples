//
//  MessagePacket.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import NeedleTailIRC
import PQSSession

public enum MessageFlag: String, Codable, Sendable {
    case publishUserConfiguration, friendshipStateRequest, communicationSynchronization, contactCreated, addContacts, privateMessage
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

public struct TransportMetadata: Sendable, Codable {
    public var messageFlag: MessageFlag
    
    public init(
        messageFlag: MessageFlag,
    ) {
        self.messageFlag = messageFlag
    }
}
