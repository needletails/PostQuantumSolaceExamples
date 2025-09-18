//
//  IRCServer.swift
//  PQSIRCServer (Library)
//
//  Extracted from previous main.swift to match Package.swift target layout.
//

import Foundation
import Network
import NIOCore
import NIOSSL
import NeedleTailIRC
import NeedleTailLogger
import ConnectionManagerKit

public actor IRCServer {
    let logger = NeedleTailLogger("[ com.pqs.server.irc ]")
    public let executor: NTSEventLoopExecutor
    public var origin: String?
    let listener = ConnectionListener<IRCPayload, IRCPayload>()
    var sessionManager: SessionManager?
    
    public init(executor: NTSEventLoopExecutor) {
        self.executor = executor
    }
    
    public func startListening(configuration: Configuration) async {
        await listen(configuration: configuration)
    }
    
    public func listen(configuration: Configuration) async {
        let configuration = try! await listener.resolveAddress(configuration)
        guard let address = configuration.address else { exit(0) }
        guard let origin = configuration.origin else { exit(0) }
        let sessionManager = SessionManager(origin: origin, logger: logger)
        self.origin = origin
        self.sessionManager = sessionManager
        
        try! await listener.listen(
            address: address,
            configuration: configuration,
            delegate: self,
            listenerDelegate: self)
        
    }
}

extension IRCServer: ConnectionDelegate {
    public func initializedChildChannel<Outbound, Inbound>(_ context: ConnectionManagerKit.ChannelContext<Inbound, Outbound>) async where Outbound : Sendable, Inbound : Sendable {
        guard let sessionManager = sessionManager else { return }
        let sessionHandler = await SessionHandler(
            id: UUID(),
            executor: NTSEventLoopExecutor(eventLoop: context.channel.channel.eventLoop, shouldExecuteAsTask: true),
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
    
    public nonisolated func handleError(_ stream: AsyncStream<NWError>, id: String) {
        
    }
    
    public func handleNetworkEvents(_ stream: AsyncStream<ConnectionManagerKit.NetworkEventMonitor.NetworkEvent>, id: String) async {
        
    }
}

extension IRCServer: ListenerDelegate {
    public func didBindTCPServer<Inbound, Outbound>(channel: NIOAsyncChannel<NIOAsyncChannel<Inbound, Outbound>, Never>) async where Inbound : Sendable, Outbound : Sendable {
        print("Did bind Server on \(String(describing: channel.channel.localAddress))")
    }
    
    public nonisolated func retrieveSSLHandler() -> NIOSSL.NIOSSLServerHandler? {
        nil
    }
    
    public nonisolated func retrieveChannelHandlers() -> [any NIOCore.ChannelHandler] {
        [ByteToMessageHandler(IRCPayloadDecoder()),
         MessageToByteHandler(IRCPayloadEncoder())]
    }
    
    
}


