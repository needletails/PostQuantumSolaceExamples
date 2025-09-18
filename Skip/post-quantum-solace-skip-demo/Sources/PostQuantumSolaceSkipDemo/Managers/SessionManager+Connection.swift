//
//  SessionManager+IRC.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/15/25.
//
import NeedleTailIRC
import ConnectionManagerKit
import Foundation
import BSON
// MARK: - ConnectionManagerDelegate
extension SessionManager: ConnectionManagerDelegate {
    typealias Inbound = IRCPayload
    typealias Outbound = IRCPayload
    
    nonisolated func retrieveChannelHandlers() -> [any NIOCore.ChannelHandler] {
        [ByteToMessageHandler(IRCPayloadDecoder()),
         MessageToByteHandler(IRCPayloadEncoder())]
    }
    
    func createNetworkConnection() async throws {
        if useWebSockets {
            
            guard let sessionContext = await pqsSession.sessionContext else {
               return
            }

            let mySecretName = sessionContext.sessionUser.secretName
            
            try await socket.connect(host: "needletails.local", port: 8080, route: "/api/auth/ws?secretName=\(mySecretName)", autoPingPongInterval: 5)
            if eventStreamTask == nil {
                eventStreamTask = Task {
                    for try await event in await socket.socketReceiver.eventStream! {
                        switch event {
#if canImport(Network)
                        case .networkEvent(let networkEvent):
                            switch networkEvent {
                            case .viabilityChanged(let viabilityUpdate):
                                print("Viability Update: \(viabilityUpdate)")
                                pqsSession.isViable = viabilityUpdate.isViable
                                try await socket.sendPing(Data(), to: "/api/auth/ws?secretName=\(mySecretName)") // Kick of ping so we have a message stream
                            default:
                                break
                            }
                        default:
                            break
#else
                        case .channelActive:
                            pqsSession.isViable = true
                            try await socket.sendPing(Data(), to: "/api/auth/ws?secretName=\(mySecretName)") // Kick of ping so we have a message stream
                        default:
                            break
#endif
                        }
                    }
                }
            }
            
           try await taskLoop.run(10, sleep: .seconds(1)) {
               if await socket.socketReceiver.messageStream != nil {
                    return false
                } else {
                    return true
                }
            }
            
            if messageStreamTask == nil {
                messageStreamTask = Task {
                    for try await frame in await socket.socketReceiver.messageStream! {
                        switch frame {
                        case .binary(let data):
                            guard let data else { return }
                            let decoded = try BSONDecoder().decode(MessagePacket.self, from: Document(data: data))
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
            
            // Wait before attempting connection
            try await Task.sleep(until: .now + .seconds(AppConfiguration.Server.initialDelay))
            
            try await connectionManager.connect(
                to: [.init(
                    host: AppConfiguration.Server.host,
                    port: AppConfiguration.Server.port,
                    enableTLS: AppConfiguration.Server.enableTLS,
                    cacheKey: AppConfiguration.Server.cacheKey
                )],
                maxReconnectionAttempts: AppConfiguration.Server.maxReconnectionAttempts,
                timeout: .seconds(Int64(AppConfiguration.Server.connectionTimeout)),
                tlsPreKeyed: nil
            )
        }
    }
    
    func createInitialTransportClosure() -> @Sendable () async throws -> Void {
        { [weak self] in
            guard let self = self else { return }
            try await createNetworkConnection()
        }
    }
    
    func channelCreated(_ eventLoop: any NIOCore.EventLoop, cacheKey: String) async {
        if useWebSockets {
            return
        }
        guard let delegate else {
            logger.log(level: .error, message: "No delegate set for channel creation")
            return
        }
        
        let connection = IRCConnection(
            connectionManager: connectionManager,
            executor: .init(eventLoop: eventLoop, shouldExecuteAsTask: true),
            logger: logger,
            delegate: delegate
        )
        
        await connection.connectionManager.setDelegates(
            connectionDelegate: connection,
            contextDelegate: connection,
            cacheKey: AppConfiguration.Server.cacheKey
        )
        
        if let transport = transport as? SessionTransportManager {
            await transport.setConnection(connection)
        }
        logger.log(level: .info, message: "IRC connection established")
    }
}
