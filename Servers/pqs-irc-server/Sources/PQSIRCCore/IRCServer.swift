//
//  IRCServer.swift
//  PQSIRCServer (Library)
//
//  Extracted from previous main.swift to match Package.swift target layout.
//

import ConnectionManagerKit
import Foundation
import NIOCore
import NIOSSL
import NeedleTailIRC
import NeedleTailLogger
@preconcurrency import Crypto
#if canImport(Network)
import Network
#endif

public actor IRCServer {
    let logger = NeedleTailLogger("[ com.pqs.server.irc ]")
    public let executor: NTSEventLoopExecutor
    public var origin: String?
    let listener = ConnectionListener<IRCPayload, IRCPayload>()
    var sessionManager: SessionManager?

    public init(executor: NTSEventLoopExecutor) {
        self.executor = executor
    }

    public func startListening(serverGroup: MultiThreadedEventLoopGroup) async {
        await listen(serverGroup: serverGroup)
    }

    public func listen(serverGroup: MultiThreadedEventLoopGroup) async {
          let config = try! await listener.resolveAddress(
            .init(group: serverGroup, host: "0.0.0.0", port: 6667))


        let sessionManager = SessionManager(origin: config.origin!, logger: logger)
        self.origin = config.origin
        self.sessionManager = sessionManager

        try! await listener.listen(
            address: config.address!,
            configuration: config,
            delegate: self,
            listenerDelegate: self)

    }
}

extension IRCServer: ConnectionDelegate {
    public func initializedChildChannel<Outbound, Inbound>(
        _ context: ConnectionManagerKit.ChannelContext<Inbound, Outbound>
    ) async where Outbound: Sendable, Inbound: Sendable {
        guard let sessionManager = sessionManager else { return }
        let sessionHandler = await SessionHandler(
            id: UUID(),
            executor: NTSEventLoopExecutor(
                eventLoop: context.channel.channel.eventLoop, shouldExecuteAsTask: true),
            sessionIdentifer: context.id,
            serverName: "PQSServer",
            serverVersion: "1.0.0",
            sessionConfiguration: SessionHandler.SessionConfiguration(
                listener: listener,
                sessionManager: sessionManager
            ),
            logger: logger)
        await listener.setContextDelegate(sessionHandler, key: context.id)
    }

#if canImport(Network)
        public nonisolated func handleError(_ stream: AsyncStream<NWError>, id: String) {

        }

        public func handleNetworkEvents(
            _ stream: AsyncStream<ConnectionManagerKit.NetworkEventMonitor.NetworkEvent>, id: String
        ) async {

        }
#else

    public nonisolated func handleError(_ stream: AsyncStream<IOError>, id: String) {

    }

    public func handleNetworkEvents(_ stream: AsyncStream<NetworkEventMonitor.NIOEvent>, id: String) async {

    }
#endif
}

extension IRCServer: ListenerDelegate {
    public func didBindTCPServer<Inbound, Outbound>(
        channel: NIOAsyncChannel<NIOAsyncChannel<Inbound, Outbound>, Never>
    ) async where Inbound: Sendable, Outbound: Sendable {
        print("Did bind Server on \(String(describing: channel.channel.localAddress))")
    }

    public nonisolated func retrieveSSLHandler() -> NIOSSL.NIOSSLServerHandler? {
         // Define the PSK server provider
            let pskServerProvider: NIOPSKServerIdentityProvider = { [weak self] context in
                guard let self else {
                    print("Error: Self is nil, returning empty PSK.")
                    return PSKServerIdentityResponse(key: NIOSSLSecureBytes())
                }

                // Retrieve PSK credentials based on the client identity
                let clientIdentity = context.clientIdentity
                self.logger.log(
                    level: .info, message: "Received client identity: \(clientIdentity)")

                // Get the PSK credentials for the client
             let pskCredentials = PSKCredentials(key: "random-key", hint: "random-hint")

                // Log the retrieved PSK credentials
                self.logger.log(
                    level: .info,
                    message: "Retrieved PSK credentials for client identity: \(clientIdentity)")
                self.logger.log(level: .trace, message: "PSK Key configured (length: \(pskCredentials.key.count))")

                // Create the PSK from the retrieved credentials
                var psk = NIOSSLSecureBytes()

                guard let pskKeyData = pskCredentials.key.data(using: .utf8) else {
                    fatalError("Error: Unable to convert PSK key to Data.")
                }

                guard let hintData = pskCredentials.hint.data(using: .utf8) else {
                    fatalError("Error: Unable to convert PSK hint to Data.")
                }
                let authenticationKey = SymmetricKey(data: pskKeyData)

                let authenticationCode = HMAC<SHA256>.authenticationCode(
                    for: hintData, using: authenticationKey)

                let authenticationData = authenticationCode.withUnsafeBytes {
                    Data($0)
                }
                psk.append(authenticationData)
                self.logger.log(
                    level: .info,
                    message: "PSK successfully created for client identity: \(clientIdentity)")
                return PSKServerIdentityResponse(key: psk)
            }

            // Create a TLS configuration for PSK
            var tls = TLSConfiguration.makePreSharedKeyConfiguration()
            tls.cipherSuiteValues = [.TLS_ECDHE_PSK_WITH_AES_256_CBC_SHA]
            tls.maximumTLSVersion = .tlsv13

            // Log the PSK hint being used
            tls.pskHint = "random-hint"
            self.logger.log(level: .trace, message: "Using PSK hint (length: \("random-hint".count))")

            // Set the PSK server provider
            tls.pskServerProvider = pskServerProvider

            // Create the SSL context
            do {
                let sslContext = try NIOSSLContext(configuration: tls)
                self.logger.log(level: .debug, message: "Successfully created SSL context.")

                // Return the SSL server handler
                return NIOSSLServerHandler(context: sslContext)
            } catch {
                self.logger.log(level: .error, message: "Failed to create SSL context: \(error)")
                return nil
            }
    }

	struct PSKCredentials {
		let key: String
		let hint: String
	}

    public nonisolated func retrieveChannelHandlers() -> [any NIOCore.ChannelHandler] {
        [
            ByteToMessageHandler(IRCPayloadDecoder()),
            MessageToByteHandler(IRCPayloadEncoder()),
        ]
    }
}
