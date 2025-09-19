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
import BSON
import NIO
@preconcurrency import Crypto

// MARK: - ConnectionManagerDelegate
extension SessionManager: ConnectionManagerDelegate {
    typealias Inbound = IRCPayload
    typealias Outbound = IRCPayload

    nonisolated func retrieveChannelHandlers() -> [any NIOCore.ChannelHandler] {
        logger.log(level: .info, message: "Retrieving channel handlers")
        return [ByteToMessageHandler(IRCPayloadDecoder()),
         MessageToByteHandler(IRCPayloadEncoder())]
    }

    func createNetworkConnection() async throws {
        if useWebSockets {

            guard let sessionContext = await pqsSession.sessionContext else {
               return
            }

            let mySecretName = sessionContext.sessionUser.secretName

            try await socket.connect(
            host: AppConfiguration.Server.host,
            port: 8080,
            route: "/api/auth/ws?secretName=\(mySecretName)",
            autoPingPongInterval: 5)

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

           try await taskLoop.run(10, sleep: .seconds(1)) { [weak self] in
               guard let self else { return false }
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
                tlsPreKeyed: getTLSPreKey()
            )
        }
    }
	struct PSKCredential {
		let key: String
		let hint: String
	}

    func getTLSPreKey() -> TLSPreKeyedConfiguration {
	let credentials = PSKCredential(key: "random-key", hint: "random-hint")

	let pskClientProvider: NIOPSKClientIdentityProvider = { _ in
		var psk = NIOSSLSecureBytes()

		guard let keyData = credentials.key.data(using: .utf8) else {
			fatalError("")
		}

		guard let hintData = credentials.key.data(using: .utf8) else {
			fatalError("")
		}

		let authenticationKey = SymmetricKey(data: keyData)
		let authenticationCode = HMAC<SHA256>.authenticationCode(for: hintData, using: authenticationKey)
		let authenticationData = authenticationCode.withUnsafeBytes { Data($0) }
		psk.append(authenticationData)
		return PSKClientIdentityResponse(key: psk, identity: "clientIdentity")
	}
	var tls = TLSConfiguration.makePreSharedKeyConfiguration()
	tls.cipherSuiteValues = [.TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA]
	tls.maximumTLSVersion = TLSVersion.tlsv13
	tls.pskClientProvider = pskClientProvider
	tls.pskHint = "random-hint"
	return TLSPreKeyedConfiguration(tlsConfiguration: tls)
    }

    func createInitialTransportClosure() -> @Sendable () async throws -> Void {
        { [weak self] in
            guard let self = self else { return }
            try await createNetworkConnection()
        }
    }

    func channelCreated(_ eventLoop: any NIOCore.EventLoop, cacheKey: String) async {
        logger.log(level: .info, message: "Channel created")
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

         await connectionManager.setDelegates(
            connectionDelegate: connection,
            contextDelegate: connection,
            cacheKey: AppConfiguration.Server.cacheKey
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
