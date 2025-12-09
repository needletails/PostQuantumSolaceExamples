//
//  IRCConnection.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BinaryCodable
import PQSSession
import NeedleTailLogger
import ConnectionManagerKit
import NeedleTailIRC
import NeedleTailAsyncSequence
#if canImport(Network)
import Network
#endif

/**
 _IRCConnection_ Manages IRC Connections(Transport) via **ConnectionManagerKit**. Not **PostQuantumSolace** Specific.
 **/

public actor IRCConnection {
    
    public let id = UUID()
    // MARK: - Properties
    private let executor: IRCEventLoopExecutor
    public let sessionManager: SessionManager
    public let connectionManager: ConnectionManager<IRCPayload, IRCPayload>
    public let logger: NeedleTailLogger
    public let messageGenerator: IRCMessageGenerator
    public let builder: PacketBuilder
    public var writer: NIOAsyncChannelOutboundWriter<IRCPayload>?
    public var delegate: NetworkDelegate
    public nonisolated(unsafe) var handleNetworkEventsTask: Task<Void, Never>?
    public nonisolated(unsafe) var handleErrorEventsTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(
        sessionManager: SessionManager,
        connectionManager: ConnectionManager<IRCPayload, IRCPayload>,
        executor: IRCEventLoopExecutor,
        logger: NeedleTailLogger,
        delegate: NetworkDelegate
    ) {
        self.sessionManager = sessionManager
        self.connectionManager = connectionManager
        self.executor = executor
        self.logger = logger
        self.delegate = delegate
        self.messageGenerator = IRCMessageGenerator(executor: executor)
        self.builder = PacketBuilder(executor: executor)
    }
    
    // MARK: - Public Methods
    
    public func setViability(_ isViable: Bool) async {
        await setObservedIsViable(isViable)
        delegate.isViable = isViable
        logger.log(level: .info, message: "Connection viability changed: \(isViable)")
    }
    
    @MainActor
    public func setObservedIsViable(_ isViable: Bool) async {
        // Update UI state if needed
    }
    
    @MainActor
    public func setPathStatus(_ isActive: Bool) async {
        logger.log(level: .debug, message: "Network path active: \(isActive)")
    }
}

// MARK: - ChannelContextDelegate, ConnectionDelegate, NeedleTailWriterDelegate
extension IRCConnection: ChannelContextDelegate, ConnectionDelegate, NeedleTailWriterDelegate {
    
    public func transportMessage(
        command: IRCCommand,
        tags: [IRCTag]? = nil
    ) async throws {
        guard let sessionUser = await PQSSession.shared.sessionContext?.sessionUser,
              let nickname = NeedleTailNick(name: sessionUser.secretName, deviceId: sessionUser.deviceId) else {
            logger.log(level: .error, message: "Failed to get session user or nickname")
            throw IRCConnectionError.sessionNotAvailable
        }
        
        let origin = try BinaryEncoder().encode(nickname).base64EncodedString()
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
    
    public enum ClientType: Codable {
        case server, client
    }
    
    public func deliverWriter<Outbound, Inbound>(context: ConnectionManagerKit.WriterContext<Inbound, Outbound>) async where Outbound : Sendable, Inbound : Sendable {
        self.writer = (context.writer as! NIOAsyncChannelOutboundWriter<IRCPayload>)

        do {
            // Send password
            let value = try BinaryEncoder().encode(ClientType.client).base64EncodedString()
            let passTag = IRCTag(key: "pass-tag", value: value)
            try await self.transportMessage(
                command: .otherCommand(Constants.pass.rawValue, [""]),
                tags: [passTag])
            
            // Send nickname registration
            let tempTag = IRCTag(key: "temporary-registration", value: "true")
            guard let sessionUser = await PQSSession.shared.sessionContext?.sessionUser else {
                logger.log(level: .error, message: "Session user not available for nickname registration")
                return
            }
            
            guard let nickname = NeedleTailNick(name: sessionUser.secretName, deviceId: sessionUser.deviceId) else {
                logger.log(level: .error, message: "Failed to create nickname from session user")
                return
            }
            
            try await transportMessage(
                command: .nick(nickname),
                tags: [tempTag])
            
            logger.log(level: .info, message: "IRC registration completed successfully")
            
        } catch {
            logger.log(level: .error, message: "Failed to complete IRC registration: \(error)")
        }
    }
    
    public func deliverInboundBuffer<Inbound, Outbound>(context: ConnectionManagerKit.StreamContext<Inbound, Outbound>) async where Inbound : Sendable, Outbound : Sendable {
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
        let tags = message.tags
        switch message.command {
        case .privMsg(let recipients, let payload):
            try await handlePrivateMessage(recipients: recipients, payload: payload, origin: originalMessage.origin)
        case .ping(let origin, let origin2):
            do {
                try await doPong(source: origin, secondarySource: origin2)
            } catch {
                logger.log(level: .error, message: "Failed to send pong: \(error)")
            }
        case .join(channels: let channels, keys: _):
            for channel in channels {
                self.logger.log(level: .info, message: "Received JOIN response for channel: \(channel.stringValue)")
                self.logger.log(level: .debug, message: "JOIN response tags: \(tags?.map { "\($0.key)=\($0.value)" } ?? [])")
                var associatedTags = tags
                
                // Process members-online tag if present
                if let tagValue = associatedTags?.first(where: { $0.key == "members-online" })?.value,
                   let data = Data(base64Encoded: tagValue) {
                    let _ = try BinaryDecoder().decode([NeedleTailNick].self, from: data)
                    // NOTIFY MEMBER JOIN CHANNEL
                }

                // Remove members-online tag but keep others (like channel-packet and create-channel)
                associatedTags?.removeAll(where: { $0.key == "members-online" })
                
                // Check if this is a channel creation (has create-channel tag)
                let isCreateChannel = associatedTags?.contains(where: { $0.key == "create-channel" && $0.value == "true" }) ?? false
                let hasChannelPacket = associatedTags?.contains(where: { $0.key == "channel-packet" }) ?? false
                
                self.logger.log(level: .info, message: "JOIN response analysis: isCreateChannel=\(isCreateChannel), hasChannelPacket=\(hasChannelPacket)")
                
                // Only send MODE request if this is a channel creation (has both create-channel tag and channel-packet)
                if isCreateChannel && hasChannelPacket {
                    self.logger.log(level: .info, message: "Channel creation detected, sending MODE request for: \(channel.stringValue)")
                    
                    guard let associatedTags, !associatedTags.isEmpty else {
                        self.logger.log(level: .warning, message: "No tags available for MODE request after JOIN")
                        throw IRCConnectionError.missingData
                    }
                    
                    // Send MODE request with the tags (channel-packet and create-channel will be forwarded)
                    try await modifyChannelModes(
                        channel: channel,
                        add: [.secret],
                        addParameters: nil,
                        remove: nil,
                        removeParameters: nil,
                        tags: associatedTags)
                    self.logger.log(level: .info, message: "MODE request sent for channel creation: \(channel.stringValue)")
                } else {
                    self.logger.log(level: .debug, message: "Not sending MODE request - not a channel creation (isCreateChannel=\(isCreateChannel), hasChannelPacket=\(hasChannelPacket))")
                }
            }
        case .part(let channels):
            if let partMessageTag = tags?.first(where: { $0.key == "part-message" })?.value {
                guard let partMessageTag = Data(base64Encoded: partMessageTag) else {
                    throw NeedleTailError.nilData
                }
                let partMessage = try BinaryDecoder().decode(PartMessage.self, from: partMessageTag)
//                Notify UI Part Message
                
                // Log the part action with channel information
                let channelNames = channels.map { $0.stringValue }.joined(separator: ", ")
                self.logger.log(level: .info, message: "User parted from channel(s): \(channelNames), destroyChannel: \(partMessage.destroyChannel)")
            } else if let tag = tags?.first?.value {
                // Fallback: Handle direct PartMessage tag (legacy format)
                guard let tag = Data(base64Encoded: tag) else {
                    throw NeedleTailError.nilData
                }
                let packet = try BinaryDecoder().decode(PartMessage.self, from: tag)
//                Notify UI Part Message
                let channelNames = channels.map { $0.stringValue }.joined(separator: ", ")
                self.logger.log(level: .info, message: "User parted from channel(s): \(channelNames) (legacy format), destroyChannel: \(packet.destroyChannel)")
            }
        case .channelMode(
            let channel,
            addMode: _,
            addParameters: _,
            removeMode: _,
            removeParameters: _):
            
            self.logger.log(level: .info, message: "Received MODE response for channel: \(channel.stringValue)")
            self.logger.log(level: .debug, message: "MODE response tags: \(tags?.map { "\($0.key)=\($0.value)" } ?? [])")
            
            // Check if this is a channel creation response from the server
            if let tagValue = tags?.first(where: { $0.key == "channel-packet" })?.value,
               let data = Data(base64Encoded: tagValue),
               let createTagValue = tags?.first(where: { $0.key == "create-channel" })?.value,
               createTagValue == "true" {
                do {
                    let packet = try BinaryDecoder().decode(NeedleTailChannelPacket.self, from: data)
                    guard let secretName = await sessionManager.pqsSession.sessionContext?.sessionUser.secretName else {
                        self.logger.log(level: .error, message: "Cannot create channel communication: session context not available")
                        return
                    }
                    
                    self.logger.log(level: .info, message: "Channel packet decoded: \(packet.name.stringValue), admin: \(packet.channelOperatorAdmin), my secretName: \(secretName)")
                    
                    // Only create communication if we're the admin (channel creator)
                    if packet.channelOperatorAdmin == secretName {
                        self.logger.log(level: .info, message: "Creating communication for channel: \(packet.name.stringValue)")
                        try await sessionManager.createCommunicationChannel(
                            sender: secretName,
                            welcomeMessage: "Welcome to \(packet.name.stringValue)!",
                            packet: packet)
                        self.logger.log(level: .info, message: "Successfully created communication for channel: \(packet.name.stringValue)")
                    } else {
                        self.logger.log(level: .warning, message: "Not creating communication - admin mismatch: packet admin=\(packet.channelOperatorAdmin), my secretName=\(secretName)")
                    }
                } catch {
                    self.logger.log(level: .error, message: "Failed to process channel creation response: \(error)")
                    if let decodingError = error as? DecodingError {
                        self.logger.log(level: .debug, message: "Decoding error details: \(decodingError)")
                    }
                }
            } else {
                self.logger.log(level: .debug, message: "MODE response is not a channel creation (missing tags or create-channel != true)")
                if tags == nil {
                    self.logger.log(level: .warning, message: "MODE response has no tags")
                } else {
                    let hasChannelPacket = tags?.contains(where: { $0.key == "channel-packet" }) ?? false
                    let hasCreateChannel = tags?.contains(where: { $0.key == "create-channel" && $0.value == "true" }) ?? false
                    self.logger.log(level: .debug, message: "Tag check: hasChannelPacket=\(hasChannelPacket), hasCreateChannel=\(hasCreateChannel)")
                }
            }
            
        default:
            logger.log(level: .debug, message: "Received IRC command: \(message.command)")
        }
    }
    
    private func doPong(source: String, secondarySource: String? = nil) async throws {
        do {
            try await Task.sleep(until: .now + .seconds(5), tolerance: .seconds(2), clock: .continuous)
            try await self.transportMessage(command: .pong(server: source, server2: secondarySource))
        } catch {}
        self.logger.log(level: .trace, message: "Send Pong")
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
        
        let packet = try BinaryDecoder().decode(MessagePacket.self, from: data)
        let sender = try await getSender(origin)
        
        for recipient in recipients {
            switch recipient {
            case .nick(_):
                try await processMessage(packet: packet, sender: sender)
            case .channel(_):
                try await processMessage(packet: packet, sender: sender)
            default:
                break
            }
        }
    }
    
    private func processMessage(packet: MessagePacket, sender: IRCUserIdentifier) async throws {
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
        return try BinaryDecoder().decode(IRCUserIdentifier.self, from: data)
    }
    
    // MARK: - ConnectionDelegate Methods
    
    public nonisolated func channelActive(_ stream: AsyncStream<Void>, id: String) {
#if os(Linux)
        Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                logger.log(level: .info, message: "Channel active: \(id), event \(event)")
                await setViability(true)
            }
        }
#endif
    }
    
    public nonisolated func channelInactive(_ stream: AsyncStream<Void>, id: String) {
#if os(Linux)
        Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                logger.log(level: .info, message: "Channel inactive: \(id), event \(event)")
                await setViability(false)
            }
        }
#endif
    }
    
    public func reportChildChannel(error: any Error, id: String) async {
        logger.log(level: .error, message: "Child channel error [\(id)]: \(error)")
    }
    
    public func didShutdownChildChannel() async {
        logger.log(level: .info, message: "Child channel shutdown")
    }
    
#if os(Linux) || os(Android)
    public nonisolated func handleError(_ stream: AsyncStream<IOError>, id: String) {
        if handleErrorEventsTask == nil {
            handleErrorEventsTask = Task {
                for await error in stream {
                    logger.log(level: .error, message: "\(error)")
                }
            }
        }
    }
    
    public func handleNetworkEvents(_ stream: AsyncStream<NetworkEventMonitor.NIOEvent>, id: String) async {
        if handleNetworkEventsTask == nil {
            self.handleNetworkEventsTask = Task(executorPreference: self.executor) { [weak self] in
                guard let self else { return }
                await withDiscardingTaskGroup { group in
                    for await event in stream {
                        group.addTask(executorPreference: self.executor) {
                            switch event {
                            case .event(_):
                                break
                            }
                        }
                    }
                }
            }
        }
    }
#elseif canImport(Network)

    public nonisolated func handleError(_ stream: AsyncStream<NWError>, id: String) {
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

    public func handleNetworkEvents(_ stream: AsyncStream<ConnectionManagerKit.NetworkEventMonitor.NetworkEvent>, id: String) async {
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
    #endif
    
    public func initializedChildChannel<Outbound, Inbound>(_ context: ConnectionManagerKit.ChannelContext<Inbound, Outbound>) async where Outbound : Sendable, Inbound : Sendable {
        logger.log(level: .info, message: "Child channel initialized: \(context.id)")
    }

    public enum IRCConnectionError: Error {
        case sessionNotAvailable
        case writerNotAvailable
        case messageMissing
        case senderMissing
        case invalidOriginData
        case missingData
    }
    
    public func joinChannel(_ channel: NeedleTailChannelPacket, createChannel: Bool = false) async throws {
        var tags = [IRCTag]()
        let encodedString = try BinaryEncoder().encode(channel).base64EncodedString()
        let channelTag = IRCTag(key: "channel-packet", value: encodedString)
        tags.append(channelTag)
        if createChannel {
            tags.append(IRCTag(key: "create-channel", value: "true"))
        }
       
        //Keys are Passwords for Channels
        try await self.transportMessage(
            command: .join(channels: [channel.name], keys: nil),
            tags: tags)
    }
    
    /// Parts from a channel with a custom part message.
    /// - Parameters:
    ///   - channel: The channel to part from.
    ///   - partMessage: The part message to send when leaving the channel.
    public func partChannel(_ channel: NeedleTailChannel, partMessage: PartMessage) async throws {
        var tags: [IRCTag] = []
        
        // Send the PartMessage provided by the caller
        let encodedPartMessage = try BinaryEncoder().encode(partMessage).base64EncodedString()
        let partMessageTag = IRCTag(key: "part-message", value: encodedPartMessage)
        tags.append(partMessageTag)
        
        try await self.transportMessage(
            command: .part(channels: [channel]),
            tags: tags)
    }
    
    public func modifyChannelModes(
        channel: NeedleTailChannel,
        add permissionToAdd: IRCChannelPermissions? = nil,
        addParameters: [String]? = nil,
        remove permissionToRemove: IRCChannelPermissions? = nil,
        removeParameters: [String]? = nil,
        tags: [IRCTag] = []
    ) async throws {
        try await self.transportMessage(command: .channelMode(
            channel,
            addMode: permissionToAdd,
            addParameters: addParameters,
            removeMode: permissionToRemove,
            removeParameters: removeParameters),
                                        tags: tags)
    }
}
