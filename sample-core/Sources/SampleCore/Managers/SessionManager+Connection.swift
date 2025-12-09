//
//  SessionManager+IRC.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/15/25.
//
import NeedleTailIRC
import ConnectionManagerKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BinaryCodable
import NIO
@preconcurrency import Crypto

// MARK: - ConnectionManagerDelegate
extension SessionManager: ConnectionManagerDelegate {
    public typealias Inbound = IRCPayload
    public typealias Outbound = IRCPayload
    
    public nonisolated func retrieveChannelHandlers() -> [any NIOCore.ChannelHandler] {
        logger.log(level: .info, message: "Retrieving channel handlers")
        return [ByteToMessageHandler(IRCPayloadDecoder()),
                MessageToByteHandler(IRCPayloadEncoder())]
    }
    
    public func createNetworkConnection() async throws {
        if useWebSockets {
            
            guard let sessionContext = await pqsSession.sessionContext else {
                logger.log(level: .error, message: "Cannot create network connection: session context not available")
                throw SessionManagerError.sessionNotInitialized
            }
            
            let mySecretName = sessionContext.sessionUser.secretName
            
            try await WebSocketClient.shared.connect(
                host: AppConfiguration.Server.host,
                port: 8081,
                route: "/api/auth/ws?secretName=\(mySecretName)",
                autoPingPongInterval: 5)
            
            if eventStreamTask == nil {
                eventStreamTask = Task {
                    guard let eventStream = await WebSocketClient.shared.socketReceiver.eventStream else {
                        logger.log(level: .error, message: "Event stream not available")
                        return
                    }
                    for try await event in eventStream {
                        switch event {
#if canImport(Network)
                        case .networkEvent(let networkEvent):
                            switch networkEvent {
                            case .viabilityChanged(let viabilityUpdate):
                                print("Viability Update: \(viabilityUpdate)")
                                pqsSession.isViable = viabilityUpdate.isViable
                                try await WebSocketClient.shared.sendPing(Data(), to: "/api/auth/ws?secretName=\(mySecretName)") // Kick of ping so we have a message stream
                            default:
                                break
                            }
                        default:
                            break
#else
                        case .channelActive:
                            pqsSession.isViable = true
                            try await WebSocketClient.shared.sendPing(Data(), to: "/api/auth/ws?secretName=\(mySecretName)") // Kick of ping so we have a message stream
                        default:
                            break
#endif
                        }
                    }
                }
            }
            
            try await taskLoop.run(10, sleep: .seconds(1)) { [weak self] in
                guard let self else { return false }
                if await WebSocketClient.shared.socketReceiver.messageStream != nil {
                    return false
                } else {
                    return true
                }
            }
            
            if messageStreamTask == nil {
                messageStreamTask = Task {
                    guard let messageStream = await WebSocketClient.shared.socketReceiver.messageStream else {
                        logger.log(level: .error, message: "Message stream not available")
                        return
                    }
                    for try await frame in messageStream {
                        switch frame {
                        case .binary(let data):
                            guard let data else { return }
                            let decoded = try BinaryDecoder().decode(MessagePacket.self, from: data)
                            if let message = decoded.message, let name = decoded.senderSecretName, let deviceId = decoded.sender {
                                try await pqsSession.receiveMessage(
                                    message: message,
                                    sender: name,
                                    deviceId: deviceId,
                                    messageId: decoded.id
                                )
                            }
                        default:
                            continue
                        }
                    }
                }
            }
        } else {
            await connectionManager.setDelegate(self)
            
            try await connectionManager.connect(
                to: [.init(
                    host: AppConfiguration.Server.host,
                    port: AppConfiguration.Server.port,
                    enableTLS: AppConfiguration.Server.enableTLS,
                    cacheKey: AppConfiguration.Server.cacheKey
                )],
                tlsPreKeyed: nil
            )
        }
    }
    
    public func createInitialTransportClosure() async -> @Sendable () async throws -> Void {
        { [weak self] in
            guard let self = self else { return }
            try await createNetworkConnection()
        }
    }
    
    public func channelCreated(_ eventLoop: any NIOCore.EventLoop, cacheKey: String) async {
        logger.log(level: .info, message: "Channel created")
        if useWebSockets {
            return
        }
        pqsSession.isViable = true
        guard let delegate else {
            logger.log(level: .error, message: "No delegate set for channel creation")
            return
        }
        
        let connection = IRCConnection(
            sessionManager: self,
            connectionManager: connectionManager,
            executor: .init(eventLoop: eventLoop, shouldExecuteAsTask: true),
            logger: logger,
            delegate: delegate
        )
        
        await connectionManager.setDelegates(
            connectionDelegate: connection,
            contextDelegate: connection,
            cacheKey: AppConfiguration.Server.cacheKey)
        
        await connection.connectionManager.setDelegates(
            connectionDelegate: connection,
            contextDelegate: connection,
            cacheKey: AppConfiguration.Server.cacheKey)
        
        if let transport = transport as? SessionTransportManager {
            await transport.setConnection(connection)
        }
        logger.log(level: .info, message: "IRC connection established")
        self.connection = connection
    }
    
    public func createCommunicationChannel(
        sender: String,
        welcomeMessage: String,
        packet: NeedleTailChannelPacket
    ) async throws {
        try await self.pqsSession.createCommunicationChannel(
            sender: sender,
            recipient: .channel(packet.name.stringValue),
            channelName: packet.name.stringValue,
            administrator: packet.channelOperatorAdmin,
            members: packet.members,
            operators: packet.channelOperators,
            welcomeMessage: welcomeMessage,
            transportInfo: nil)
    }
    
    public func joinChannel(_ channel: NeedleTailChannelPacket, createChannel: Bool = false) async throws {
        // Join the channel on the IRC server
        // The communication will be created after receiving the MODE response from the server
        try await connection?.joinChannel(channel, createChannel: createChannel)
    }
}
