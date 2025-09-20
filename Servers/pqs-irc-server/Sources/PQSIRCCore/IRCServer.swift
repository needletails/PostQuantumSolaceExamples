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

    public nonisolated func retrieveSSLHandler() -> NIOSSL.NIOSSLServerHandler? { nil }

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
