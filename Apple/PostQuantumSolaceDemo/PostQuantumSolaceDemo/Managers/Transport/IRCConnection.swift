//
//  IRCConnection.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import Foundation
import BSON
import PQSSession
import Network
import NeedleTailLogger
import ConnectionManagerKit
import NeedleTailIRC
import NeedleTailAsyncSequence


/**
 _IRCConnection_ Manages IRC Connections(Transport) via **ConnectionManagerKit**. Not **PostQuantumSolace** Specific.
 **/

actor IRCConnection {
    let id = UUID()
    // MARK: - Properties
    private let executor: IRCEventLoopExecutor
    let connectionManager: ConnectionManager<IRCPayload, IRCPayload>
    let logger: NeedleTailLogger
    let messageGenerator: IRCMessageGenerator
    let builder: PacketBuilder
    var writer: NIOAsyncChannelOutboundWriter<IRCPayload>?
    var delegate: NetworkDelegate
    nonisolated(unsafe) var handleNetworkEventsTask: Task<Void, Never>?
    nonisolated(unsafe) var handleErrorEventsTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(
        connectionManager: ConnectionManager<IRCPayload, IRCPayload>,
        executor: IRCEventLoopExecutor,
        logger: NeedleTailLogger,
        delegate: NetworkDelegate
    ) {
        self.connectionManager = connectionManager
        self.executor = executor
        self.logger = logger
        self.delegate = delegate
        self.messageGenerator = IRCMessageGenerator(executor: executor)
        self.builder = PacketBuilder(executor: executor)
    }
    
    // MARK: - Public Methods
    
    func setViability(_ isViable: Bool) async {
        await setObservedIsViable(isViable)
        delegate.isViable = isViable
        logger.log(level: .info, message: "Connection viability changed: \(isViable)")
    }
    
    @MainActor
    func setObservedIsViable(_ isViable: Bool) async {
        // Update UI state if needed
    }
    
#if canImport(Network)
    @MainActor
    func setPathStatus(_ status: NWPath.Status) async {
        logger.log(level: .debug, message: "Network path status: \(status)")
    }
#else
    @MainActor
    func setPathStatus(_ isActive: Bool) async {
        logger.log(level: .debug, message: "Network path active: \(isActive)")
    }
#endif
}

// MARK: - ChannelContextDelegate, ConnectionDelegate, NeedleTailWriterDelegate
extension IRCConnection: ChannelContextDelegate, ConnectionDelegate, NeedleTailWriterDelegate {
    
    func transportMessage(
        command: IRCCommand,
        tags: [IRCTag]? = nil
    ) async throws {
        guard let sessionUser = await PQSSession.shared.sessionContext?.sessionUser,
              let nickname = NeedleTailNick(name: sessionUser.secretName, deviceId: sessionUser.deviceId) else {
            logger.log(level: .error, message: "Failed to get session user or nickname")
            throw IRCConnectionError.sessionNotAvailable
        }
        
        let origin = try BSONEncoder().encode(nickname).makeData().base64EncodedString()
        guard let writer = writer else {
            logger.log(level: .error, message: "Writer not available")
            throw IRCConnectionError.writerNotAvailable
        }
        
        try await self.transportMessage(
            messageGenerator,
            executor: executor,
            logger: logger,
            writer: writer,
            origin: origin,
            command: command,
            tags: tags,
            authPacket: nil
        )
    }
    
    func deliverWriter<Outbound, Inbound>(context: ConnectionManagerKit.WriterContext<Inbound, Outbound>) async where Outbound : Sendable, Inbound : Sendable {
        self.writer = (context.writer as! NIOAsyncChannelOutboundWriter<IRCPayload>)
        
        do {
            // Send password
            let passTag = IRCTag(key: "pass-tag", value: "client")
            try await self.transportMessage(
                command: .otherCommand(Constants.pass.rawValue, [""]),
                tags: [passTag]
            )
            
            // Send nickname registration
            let tempTag = IRCTag(key: "temporary-registration", value: "true")
            guard let sessionUser = await PQSSession.shared.sessionContext?.sessionUser else {
                logger.log(level: .error, message: "Session user not available for nickname registration")
                return
            }
            
            try await transportMessage(
                command: .nick(.init(name: sessionUser.secretName, deviceId: sessionUser.deviceId)!),
                tags: [tempTag]
            )
            
            logger.log(level: .info, message: "IRC registration completed successfully")
            
        } catch {
            logger.log(level: .error, message: "Failed to complete IRC registration: \(error)")
        }
    }
    
    func deliverInboundBuffer<Inbound, Outbound>(context: ConnectionManagerKit.StreamContext<Inbound, Outbound>) async where Inbound : Sendable, Outbound : Sendable {
        do {
            guard let payload = context.inbound as? IRCPayload else {
                logger.log(level: .warning, message: "Received non-IRC payload")
                return
            }
            
            switch payload {
            case .irc(let message):
                guard let reassembledMessage = try await messageGenerator.messageReassembler(ircMessage: message) else {
                    return
                }
                
                try await handleReassembledMessage(reassembledMessage, originalMessage: message)
                
            default:
                logger.log(level: .debug, message: "Received non-IRC message type")
            }
        } catch {
            logger.log(level: .error, message: "Error processing inbound message: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func handleReassembledMessage(_ message: IRCMessage, originalMessage: IRCMessage) async throws {
        switch message.command {
        case .privMsg(let recipients, let payload):
            try await handlePrivateMessage(recipients: recipients, payload: payload, origin: originalMessage.origin)
        default:
            logger.log(level: .debug, message: "Received IRC command: \(message.command)")
        }
    }
    
    private func handlePrivateMessage(recipients: [IRCMessageRecipient], payload: String, origin: String?) async throws {
        guard let origin = origin else {
            logger.log(level: .warning, message: "Received message without origin")
            return
        }
        
        guard let data = Data(base64Encoded: payload) else {
            logger.log(level: .error, message: "Failed to decode message payload")
            return
        }
        
        let packet = try BSONDecoder().decode(MessagePacket.self, from: Document(data: data))
        let sender = try await getSender(origin)
        
        for recipient in recipients {
            switch recipient {
            case .nick(_):
                try await processNickMessage(packet: packet, sender: sender)
            default:
                break
            }
        }
    }
    
    private func processNickMessage(packet: MessagePacket, sender: IRCUserIdentifier) async throws {
        guard let message = packet.message else {
            throw IRCConnectionError.messageMissing
        }
        
        guard let deviceId = packet.sender else {
            throw IRCConnectionError.senderMissing
        }
        
        let senderNick = sender.nick
        
        try await PQSSession.shared.receiveMessage(
            message: message,
            sender: senderNick.name,
            deviceId: deviceId,
            messageId: packet.id
        )
        
        logger.log(level: .info, message: "Successfully processed message from \(senderNick.name)")
    }
    
    private func getSender(_ origin: String) async throws -> IRCUserIdentifier {
        guard let data = Data(base64Encoded: origin) else {
            throw IRCConnectionError.invalidOriginData
        }
        return try BSONDecoder().decode(IRCUserIdentifier.self, from: Document(data: data))
    }
    
    // MARK: - ConnectionDelegate Methods
    
    nonisolated func channelActive(_ stream: AsyncStream<Void>, id: String) {
        logger.log(level: .info, message: "Channel active: \(id)")
    }
    
    nonisolated func channelInactive(_ stream: AsyncStream<Void>, id: String) {
        logger.log(level: .info, message: "Channel inactive: \(id)")
    }
    
    func reportChildChannel(error: any Error, id: String) async {
        logger.log(level: .error, message: "Child channel error [\(id)]: \(error)")
    }
    
    func didShutdownChildChannel() async {
        logger.log(level: .info, message: "Child channel shutdown")
    }
    
    nonisolated func handleError(_ stream: AsyncStream<NWError>, id: String) {
        if handleErrorEventsTask == nil {
            handleErrorEventsTask = Task {
                for await event in stream {
                    switch event {
                    case .dns(let dnsError):
                        logger.log(level: .error, message: "Network error [\(dnsError)]")
                    case .posix(let code):
                        logger.log(level: .error, message: "Network error [\(code)]")
                    case .tls(let status):
                        logger.log(level: .error, message: "Network error [\(status)]")
                    default:
                        break
                    }
                }
            }
        }
    }
    
    func handleNetworkEvents(_ stream: AsyncStream<ConnectionManagerKit.NetworkEventMonitor.NetworkEvent>, id: String) async {
        if handleNetworkEventsTask == nil {
            self.handleNetworkEventsTask = Task(executorPreference: self.executor) { [weak self] in
                guard let self else { return }
                await withDiscardingTaskGroup { group in
                    for await event in stream {
                        group.addTask(executorPreference: self.executor) { [weak self] in
                            guard let self else { return }
                            switch event {
                            case .viabilityChanged(let viabilityUpdate):
                                await setViability(viabilityUpdate.isViable)
                            default:
                                self.logger.log(level: .trace, message: "Unknown network event type")
                            }
                        }
                    }
                }
            }
        }
    }
    
    func initializedChildChannel<Outbound, Inbound>(_ context: ConnectionManagerKit.ChannelContext<Inbound, Outbound>) async where Outbound : Sendable, Inbound : Sendable {
        logger.log(level: .info, message: "Child channel initialized: \(context.id)")
    }
}

// MARK: - Errors
extension IRCConnection {
    enum IRCConnectionError: Error {
        case sessionNotAvailable
        case writerNotAvailable
        case messageMissing
        case senderMissing
        case invalidOriginData
    }
}
