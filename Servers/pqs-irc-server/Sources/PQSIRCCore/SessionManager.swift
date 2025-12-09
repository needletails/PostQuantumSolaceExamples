//
//  SessionManager.swift (Library target)
//

import Foundation
import NIOCore
import NeedleTailIRC
import NeedleTailLogger
import ConnectionManagerKit
import BinaryCodable
@preconcurrency import Crypto
import AsyncHTTPClient

actor SessionManager {
    
    enum SessionError: Error {
        case sessionNotFound
    }
    
    // MARK: - Core Properties
    
    let origin: String
    let logger: NeedleTailLogger
    let created = Date()
    private let cache = SessionCache()
    
    init(origin: String, logger: NeedleTailLogger) {
        self.origin = origin
        self.logger = logger
    }
    
    func cacheSession(for nick: NeedleTailNick, handler: SessionHandler) async {
        await cache.cacheSession(nick: nick, handler: handler)
    }
    
    func getSession(for nick: NeedleTailNick) async throws -> SessionHandler {
        if let targetSession = await cache.findSession(nick: nick),
           await targetSession.hasActiveWriter() {
            return targetSession
        }
        throw SessionError.sessionNotFound
    }
    
    func getSessions() async -> [SessionHandler] {
        await cache.findUserSessions()
    }
    
    func registerSession(_ session: SessionHandler, needletailNick: NeedleTailNick) async throws {
        
        // Unregister existing session if necessary
        try await unregisterExistingSession(for: needletailNick, currentSession: session)
        
        logger.log(level: .info, message: "Registering Nick: \(needletailNick)")
        await cache.cacheSession(nick: needletailNick, handler: session)
    }
    
    public func unregisterSession(_ session: SessionHandler) async throws {
        guard let nick = await session.sessionInfo.nick else { return }
        
        try await cache.removeSession(nick: nick)
        logger.log(level: .info, message: "Unregistered Nick: \(nick)")
    }
    
    private func unregisterExistingSession(for needletailNick: NeedleTailNick, currentSession: SessionHandler) async throws {
        for session in await cache.findUserSessions() {
            if let existingNick = await session.sessionInfo.nick, existingNick.name == needletailNick.name {
                try await unregisterSession(session)
            }
        }
    }
}


actor SessionCache {
    
    private var sessions = [NeedleTailNick: SessionHandler]()
    
    var userCount: Int {
        sessions.count
    }
    
    func cacheSession(nick: NeedleTailNick, handler: SessionHandler) async {
        sessions[nick] = handler
    }
    
    /// Finds and returns the session handler associated with the given nickname.
    func findSession(nick: NeedleTailNick) async -> SessionHandler? {
        return sessions[nick]
    }
    /// Finds and returns the session handlers for all users
    func findUserSessions() async -> [SessionHandler] {
        Array(sessions.values)
    }
    
    func updateSession(nick: NeedleTailNick, handler: SessionHandler) async throws {
        guard sessions[nick] != nil else {
            throw SessionManager.SessionError.sessionNotFound
        }
        sessions[nick] = handler
    }
    
    func removeSession(nick: NeedleTailNick) async throws {
        guard sessions.removeValue(forKey: nick) != nil else {
            throw SessionManager.SessionError.sessionNotFound
        }
    }
}


actor SessionHandler: NeedleTailWriterDelegate, Identifiable, Hashable {
    
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }
    nonisolated let id: UUID
    let executor: NTSEventLoopExecutor
    let logger: NeedleTailLogger
    var sessionConfiguration: SessionConfiguration
    let messageGenerator: IRCMessageGenerator
    var clientSessionIsAuthenticated: Bool = false
    private(set) var writer: NIOAsyncChannelOutboundWriter<IRCPayload>?
    var sessionInfo: SessionInfo = SessionInfo()
    var messageInfo: MessageInfo = MessageInfo()
    
    struct SessionConfiguration: Sendable {
        let listener: ConnectionListener<IRCPayload, IRCPayload>
        let sessionManager: SessionManager
        private(set) var mode = IRCUserModeFlags()
        private(set) var capabilities: Set<String> = ["multi-prefix"]
        mutating func setMode(_ mode: IRCUserModeFlags) {
            self.mode = mode
        }
        mutating func setCapabilities(_ capabilities: Set<String>) {
            self.capabilities = capabilities
        }
    }
    
    struct SessionInfo: Sendable {
        
        private(set) var state: SessionState = .initial
        private(set) var password: String?
        private(set) var nick: NeedleTailNick?
        private(set) var userId: IRCUserIdentifier?
        private(set) var userInfo: IRCUserDetails?
        
        mutating func setState(_ state: SessionState) {
            self.state = state
        }
        mutating func setPassword(_ password: String) {
            self.password = password
        }
        mutating func setNick(_ nick: NeedleTailNick) {
            self.nick = nick
        }
        mutating func setUserId(_ userId: IRCUserIdentifier?) {
            self.userId = userId
        }
        mutating func setUserInfo(_ userInfo: IRCUserDetails) {
            self.userInfo = userInfo
        }
    }
    
    struct MessageInfo: Sendable {
        private(set) var origin: String?
        private(set) var target: String = ""
        
        mutating func setOrigin(_ origin: String) {
            self.origin = origin
        }
        
        mutating func setTarget(_ target: String) {
            self.target = target
        }
    }
    
    enum SessionState: Equatable, Sendable {
        case initial
        case registerNick
        case registerUserInfo
        case registered
        
        static func == (lhs: SessionState, rhs: SessionState) -> Bool {
            switch (lhs, rhs) {
            case (.initial, .initial), (.registered, .registered), (.registerNick, .registerNick),
                (.registerUserInfo, .registerUserInfo):
                return true
            default:
                return false
            }
        }
    }
    
    enum SessionHandlerError: Error {
        case invalidState(String)
        case missingUserConfiguration
        case missingWriter
        case missingSender
    }
    
    init(
        id: UUID = UUID(),
        executor: NTSEventLoopExecutor,
        sessionIdentifer: String,
        serverName: String,
        serverVersion: String,
        sessionConfiguration: SessionConfiguration,
        sessionInfo: SessionInfo = .init(),
        messageInfo: MessageInfo = .init(),
        logger: NeedleTailLogger
    ) async {
        self.id = id
        self.executor = executor
        self.sessionConfiguration = sessionConfiguration
        self.sessionInfo = sessionInfo
        self.messageInfo = messageInfo
        self.logger = logger
        self.messageGenerator = IRCMessageGenerator(executor: executor)
        logger.log(level: .info, message: "Intitialized Session Handler")
    }
    
    func setWriter(writer: NIOAsyncChannelOutboundWriter<IRCPayload>) async {
        self.writer = writer
    }
    
    func hasActiveWriter() async -> Bool {
        return writer != nil
    }
    
    func unregisterCurrentSesssion() async throws {
        try await sessionConfiguration.sessionManager.unregisterSession(self)
    }
    
    deinit {
        clientSessionIsAuthenticated = false
    }
    
    func processMessage(_ message: IRCMessage) async {
        let tags = message.tags
        switch message.command {
        case .pong(let origin, let origin2):
            do {
                try await doPing(source: origin, secondarySource: origin2)
            } catch {
                self.logger.log(level: .error, message: "Failed to process PONG: \(error)")
            }
        case .privMsg(let recipients, let payload):
            do {
                let sender = try await self.getSender(message)
                try await doMessage(
                    senderID: sender,
                    recipients: recipients,
                    message: payload,
                    associatedTags: tags
                )
            } catch {
                self.logger.log(level: .error, message: "Failed to process PRIVMSG: \(error)")
                if let decodingError = error as? DecodingError {
                    self.logger.log(level: .debug, message: "Decoding error details: \(decodingError)")
                }
            }
        case .nick(let nickName):
            do {
                let sender = try await self.getSender(message)
                try await doNick(senderID: sender, nick: nickName, associatedTags: tags)
            } catch {
                self.logger.log(level: .error, message: "Failed to process NICK: \(error)")
                if let decodingError = error as? DecodingError {
                    self.logger.log(level: .debug, message: "Decoding error details: \(decodingError)")
                }
            }
            
        case .user(let info):
            do {
                try await doUserInfo(info: info, associatedTags: tags)
            } catch {
                self.logger.log(level: .error, message: "Failed to process USER: \(error)")
            }
        case .join(let channels, let keys):
            guard let nick = sessionInfo.nick else { return }
            // Process each channel in the join request
            for channel in channels {
                do {
                    try await processJoinRequest(
                        channel: channel,
                        key: keys?.first,
                        sessionNick: nick,
                        associatedTags: tags)
                } catch {
                    self.logger.log(level: .error, message: "Failed to process JOIN for channel \(channel.stringValue): \(error)")
                }
            }
        case .part(let channels):
            do {
                try await doPart(channels, associatedTags: tags)
            } catch {
                self.logger.log(level: .error, message: "Failed to process PART: \(error)")
            }
        case .channelMode(
            let channelName,
            let addMode,
            let addParameters,
            let removeMode,
            let removeParameters):
            
            do {
                try await doMode(
                    channel: channelName,
                    addMode: addMode,
                    addParameters: addParameters,
                    removeMode: removeMode,
                    removeParameters: removeParameters,
                    associatedTags: tags)
            } catch {
                logger.log(level: .error, message: "Error processing MODE command: \(error)")
            }
        default:
            break
        }
    }
    
    func processJoinRequest(
        channel: NeedleTailChannel,
        key: String?,
        sessionNick: NeedleTailNick,
        associatedTags: [IRCTag]?
    ) async throws {
        let channelName = channel.stringValue
        logger.log(level: .info, message: "Processing JOIN request for channel: \(channelName) by \(sessionNick.name)")
        
        // Extract channel packet from tags if present (for channel creation)
        if let channelPacketTag = associatedTags?.first(where: { $0.key == "channel-packet" }),
           let data = Data(base64Encoded: channelPacketTag.value) {
            do {
                _ = try BinaryDecoder().decode(NeedleTailChannelPacket.self, from: data)
                let isCreate = associatedTags?.contains(where: { $0.key == "create-channel" && $0.value == "true" }) ?? false
                
                if isCreate {
                    logger.log(level: .info, message: "Channel creation requested: \(channelName)")
                    // Channel creation logic would go here
                }
            } catch {
                logger.log(level: .error, message: "Failed to decode channel packet: \(error)")
            }
        }
        
        // Simple join processing - just log for now
        logger.log(level: .info, message: "User \(sessionNick.name) joined channel \(channelName)")
        
        // Send JOIN response back to the client with tags forwarded
        // This is the server's acknowledgment that the user has joined the channel
        // The tags (channel-packet and create-channel) will be forwarded back to the client
        let joinResponse = IRCMessage(
            origin: messageInfo.origin,
            command: .join(channels: [channel], keys: nil),
            tags: associatedTags
        )
        await sendMessage(joinResponse)
        logger.log(level: .info, message: "Sent JOIN response for channel: \(channelName) with tags: \(associatedTags?.map { "\($0.key)=\($0.value)" } ?? [])")
    }
    
    func doPart(
        _ channels: [NeedleTailChannel],
        associatedTags: [IRCTag]?
    ) async throws {
        guard let nick = sessionInfo.nick else { return }
        
        // Extract part message from tags
        var destroyChannel = false
        if let partMessageTag = associatedTags?.first(where: { $0.key == "part-message" }),
           let data = Data(base64Encoded: partMessageTag.value) {
            do {
                let partMessage = try BinaryDecoder().decode(PartMessage.self, from: data)
                destroyChannel = partMessage.destroyChannel
            } catch {
                logger.log(level: .error, message: "Failed to decode part message: \(error)")
            }
        }
        
        // Process each channel
        for channel in channels {
            let channelName = channel.stringValue
            logger.log(level: .info, message: "User \(nick.name) parted from channel: \(channelName), destroyChannel: \(destroyChannel)")
        }
    }
    
    func doMode(
        channel: NeedleTailChannel,
        addMode: IRCChannelPermissions?,
        addParameters: [String]?,
        removeMode: IRCChannelPermissions?,
        removeParameters: [String]?,
        associatedTags: [IRCTag]? = nil
    ) async throws {
        let channelName = channel.stringValue
        logger.log(level: .info, message: "Processing MODE command for channel: \(channelName)")
        
        // Check if this is a channel creation via MODE
        if let channelPacketTag = associatedTags?.first(where: { $0.key == "channel-packet" }),
           let data = Data(base64Encoded: channelPacketTag.value),
           let createTag = associatedTags?.first(where: { $0.key == "create-channel" }),
           createTag.value == "true" {
            do {
                let packet = try BinaryDecoder().decode(NeedleTailChannelPacket.self, from: data)
                guard let nick = sessionInfo.nick else { return }
                
                // Verify the user is the admin
                if packet.channelOperatorAdmin == nick.name {
                    logger.log(level: .info, message: "Channel created via MODE: \(channelName) by \(nick.name)")
                    // Channel creation logic would go here
                    
                    // Send MODE response back to the client with tags forwarded
                    // This confirms the channel creation to the client
                    let modeResponse = IRCMessage(
                        origin: messageInfo.origin,
                        command: IRCCommand.channelMode(
                            channel,
                            addMode: addMode,
                            addParameters: addParameters,
                            removeMode: removeMode,
                            removeParameters: removeParameters),
                        tags: associatedTags
                    )
                    await sendMessage(modeResponse)
                    logger.log(level: .info, message: "Sent MODE response for channel creation: \(channelName) with tags: \(associatedTags?.map { "\($0.key)=\($0.value)" } ?? [])")
                } else {
                    logger.log(level: .warning, message: "Unauthorized channel creation attempt: \(channelName) by \(nick.name)")
                }
            } catch {
                logger.log(level: .error, message: "Failed to decode channel packet in MODE: \(error)")
            }
        } else {
            // Regular mode change
            logger.log(level: .debug, message: "Mode change for channel \(channelName): add=\(String(describing: addMode)), remove=\(String(describing: removeMode))")
            
            // Notify all sessions in the channel about the mode change
            let allSessions = await sessionConfiguration.sessionManager.getSessions()
            for session in allSessions {
                await session.sendMessage(
                    IRCMessage(
                        origin: messageInfo.origin,
                        command: IRCCommand.channelMode(
                            channel,
                            addMode: addMode,
                            addParameters: addParameters,
                            removeMode: removeMode,
                            removeParameters: removeParameters),
                        tags: associatedTags)
                )
            }
        }
    }
    
    func doMessage(
        senderID: IRCUserIdentifier?,
        recipients: [IRCMessageRecipient],
        message: String,
        associatedTags: [IRCTag]?
    ) async throws {
        guard let senderID = senderID else {
            self.logger.log(level: .error, message: "Missing senderID for message; dropping message")
            throw SessionHandlerError.missingSender
        }
        guard !message.isEmpty else {
            self.logger.log(level: .warning, message: "Received empty message payload, skipping")
            return
        }
        guard let data = Data(base64Encoded: message) else {
            self.logger.log(level: .error, message: "Failed to decode base64 message payload")
            throw NeedleTailError.nilData
        }
        guard !data.isEmpty else {
            self.logger.log(level: .warning, message: "Decoded message data is empty, skipping")
            return
        }
        let messagePacket = try BinaryDecoder().decode(MessagePacket.self, from: data)
        for recipient in recipients {
            switch recipient {
            case .all:
                break
            case .nick(let nick):
                switch messagePacket.flag {
                case .publishUserConfiguration:
                    guard let configuration = messagePacket.userConfiguration else {
                        self.logger.log(level: .error, message: "Missing userConfiguration for publishUserConfiguration flag")
                        throw SessionHandlerError.missingUserConfiguration
                    }
                    
                    let user = User(
                        username: nick.name,
                        configuration: configuration)
                    
                    var request = HTTPClientRequest(url: "http://localhost:8081/api/store/create-user")
                    request.method = .POST
                    request.body = .bytes(try JSONEncoder().encode(user))
                    let response = try await HTTPClient.shared.execute(request, timeout: .seconds(30))
                    if response.status == .ok {
                        print("Created User", nick)
                        try await sessionConfiguration.sessionManager.registerSession(self, needletailNick: nick)
                    } else {
                        print("Failed To Create User")
                    }
                    
                case .privateMessage, .addContacts, .communicationSynchronization, .contactCreated, .friendshipStateRequest:
                    let deviceIdDescription = nick.deviceId?.uuidString ?? "nil"
                    self.logger.log(level: .info, message: "Searching for session for \(nick.name) with deviceId \(deviceIdDescription) (flag: \(messagePacket.flag))")
                    // First try to match by exact nick (name + deviceId) for precise targeting
                    var targetSession: SessionHandler?
                    if let exactSession = try? await sessionConfiguration.sessionManager.getSession(for: nick) {
                        targetSession = exactSession
                        self.logger.log(level: .info, message: "Found exact session match for \(nick.name) with deviceId \(deviceIdDescription)")
                    } else {
                        // Fall back to name-only matching for backwards compatibility or when deviceId doesn't match
                        // This allows delivery to any active session for that user if the specific device isn't online
                        targetSession = await sessionConfiguration.sessionManager.getSessions().async.first(where: { handler in
                            let handlerNickName = await handler.sessionInfo.nick?.name
                            let hasWriter = await handler.hasActiveWriter()
                            return handlerNickName == nick.name && hasWriter
                        })
                        if targetSession != nil {
                            self.logger.log(level: .info, message: "Found session by name only for \(nick.name) (deviceId \(deviceIdDescription) not matched, using any available session)")
                        }
                    }
                    
                    if let session = targetSession {
                        let sender = IRCUserIdentifier(nick: senderID.nick)
                        let delivered = try await doSendMessage(messagePacket,
                                                                sender: sender,
                                                                recipient: IRCMessageRecipient.nick(nick),
                                                                targetSession: session)
                        if delivered {
                            self.logger.log(level: .info, message: "Message delivered to \(nick.name) (flag: \(messagePacket.flag))")
                        } else {
                            self.logger.log(level: .warning, message: "Failed to deliver message to \(nick.name) (flag: \(messagePacket.flag)) because recipient has no active writer; treating as offline.")
                        }
                    } else {
                        // Log when recipient is not online
                        self.logger.log(level: .warning, message: "Recipient \(nick.name) with deviceId \(deviceIdDescription) is not online or not registered. Message not delivered (flag: \(messagePacket.flag)).")
                        print("WARNING: Recipient \(nick.name) is not online. Message not delivered (flag: \(messagePacket.flag)).")
                    }
                }
            case .channel(let channelName):
                self.logger.log(level: .info, message: "\(#function) - Channel: \(channelName), flag: \(messagePacket.flag)")
                // For channel messages, if recipient is specified, try to match by exact deviceId first
                // Otherwise, this might be a broadcast message that needs special handling
                if let recipientNick = messagePacket.recipient {
                    // First try to match by exact nick (name + deviceId) for precise targeting
                    var targetSession: SessionHandler?
                    if let exactSession = try? await sessionConfiguration.sessionManager.getSession(for: recipientNick) {
                        targetSession = exactSession
                        let recipientDeviceIdDescription = recipientNick.deviceId?.uuidString ?? "nil"
                        self.logger.log(level: .info, message: "Found exact channel session match for \(recipientNick.name) with deviceId \(recipientDeviceIdDescription)")
                    } else {
                        // Fall back to name-only matching for backwards compatibility
                        targetSession = await sessionConfiguration.sessionManager.getSessions().async.first(where: { handler in
                            let handlerNickName = await handler.sessionInfo.nick?.name
                            let hasWriter = await handler.hasActiveWriter()
                            return handlerNickName == recipientNick.name && hasWriter
                        })
                        if targetSession != nil {
                            let recipientDeviceIdDescription = recipientNick.deviceId?.uuidString ?? "nil"
                            self.logger.log(level: .info, message: "Found channel session by name only for \(recipientNick.name) (deviceId \(recipientDeviceIdDescription) not matched)")
                        }
                    }
                    
                    if let session = targetSession {
                        self.logger.log(level: .info, message: "Found Channel Session for \(recipientNick.name)")
                        let sender = IRCUserIdentifier(nick: senderID.nick)
                        let delivered = try await doSendMessage(messagePacket,
                                                                sender: sender,
                                                                recipient: IRCMessageRecipient.channel(channelName),
                                                                targetSession: session)
                        if delivered {
                            self.logger.log(level: .info, message: "Channel message delivered to \(recipientNick.name)")
                        } else {
                            self.logger.log(level: .warning, message: "Failed to deliver channel message to \(recipientNick.name) because recipient has no active writer; treating as offline.")
                        }
                    } else {
                        let recipientDeviceIdDescription = recipientNick.deviceId?.uuidString ?? "nil"
                        self.logger.log(level: .warning, message: "Channel recipient \(recipientNick.name) with deviceId \(recipientDeviceIdDescription) is not online. Message not delivered.")
                    }
                } else {
                    self.logger.log(level: .warning, message: "Channel message has no recipient specified. Cannot route message.")
                }
            }
        }
    }
    
    func doSendMessage(_
                       messagePacket: MessagePacket,
                       sender: IRCUserIdentifier,
                       recipient: IRCMessageRecipient,
                       targetSession: SessionHandler
    ) async throws -> Bool {
        self.logger.log(level: .info, message: "Sender: \(sender) is sending message to Recipient: \(recipient)")
        let senderString = try BinaryEncoder().encode(sender).base64EncodedString()
        let packetString = try BinaryEncoder().encode(messagePacket).base64EncodedString()
        let message = IRCMessage(
            origin: senderString,
            command: .privMsg([recipient], packetString))
        return await targetSession.sendMessage(message)
    }
    
    func doNick(
        senderID: IRCUserIdentifier?,
        nick: NeedleTailNick,
        associatedTags: [IRCTag]?
    ) async throws {
        sessionInfo.setState(.initial)
        
        sessionInfo.setNick(nick)
        sessionInfo.setState(.registerNick)
        sessionInfo.setUserId(senderID)
        
        if let sender = senderID {
            messageInfo.setOrigin(try BinaryEncoder().encode(sender).base64EncodedString())
        }
        
        try await sessionConfiguration.sessionManager.registerSession(self, needletailNick: nick)
    }
    
    func doUserInfo(info: IRCUserDetails, associatedTags: [IRCTag]?) async throws {
        self.logger.log(level: .info, message: "Do User Info: \(info)")
        guard sessionInfo.state == SessionState.registerNick else {
            self.logger.log(level: .warning, message: "Received USER command in invalid state \(sessionInfo.state); ignoring")
            throw SessionHandlerError.invalidState("USER command received in state \(sessionInfo.state)")
        }
        
        sessionInfo.setState(.registerUserInfo)
        
        self.logger.log(level: .info, message: "Registering User Info")
        sessionInfo.setUserInfo(info)
        guard let info = sessionInfo.userInfo else {
            self.logger.log(level: .error, message: "User info unexpectedly nil after setting; ignoring USER")
            throw SessionHandlerError.invalidState("Missing userInfo after setting")
        }
        guard let nick = sessionInfo.nick else {
            self.logger.log(level: .error, message: "Nick unexpectedly nil while handling USER; ignoring USER")
            throw SessionHandlerError.invalidState("Missing nick while handling USER")
        }
        sessionInfo.setUserId(IRCUserIdentifier(nick: nick))
        sessionInfo.setState(.registered)
        self.logger.log(level: .info, message: "Registered User: \(nick) with Info: \(info)")
    }
    
    func getSender(_ message: IRCMessage) async throws -> IRCUserIdentifier {
        guard let origin = message.origin else {
            self.logger.log(level: .error, message: "Message has no origin, cannot determine sender")
            throw NeedleTailError.nilData
        }
        guard !origin.isEmpty else {
            self.logger.log(level: .error, message: "Message origin is empty")
            throw NeedleTailError.nilData
        }
        guard let data = Data(base64Encoded: origin) else {
            self.logger.log(level: .error, message: "Failed to decode base64 origin: \(origin)")
            throw NeedleTailError.nilData
        }
        guard !data.isEmpty else {
            self.logger.log(level: .error, message: "Decoded origin data is empty")
            throw NeedleTailError.nilData
        }
        do {
            let senderNick = try BinaryDecoder().decode(NeedleTailNick.self, from: data)
            guard
                let userId = IRCUserIdentifier(
                    senderNick.name,
                    deviceId: senderNick.deviceId
                )
            else {
                self.logger.log(level: .error, message: "Failed to create IRCUserIdentifier from nick: \(senderNick)")
                throw NeedleTailError.nilData
            }
            return userId
        } catch {
            //We Are Pinging and Ponging. Maybe this should be inlined with the rest of the origins we send
            do {
                return try BinaryDecoder().decode(IRCUserIdentifier.self, from: data)
            } catch {
                self.logger.log(level: .error, message: "Failed to decode sender from origin: \(error)")
                throw error
            }
        }
    }
    
    nonisolated static func == (lhs: SessionHandler, rhs: SessionHandler) -> Bool {
        return lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}

extension SessionHandler: ChannelContextDelegate {
    
    private func handleChannelTermination(reason: String, channelId: String) async {
        logger.log(level: .info, message: "Channel \(channelId) terminated (\(reason)); unregistering session")
        do {
            try await unregisterCurrentSesssion()
        } catch {
            logger.log(level: .error, message: "Failed to unregister session on channel termination (\(reason)) for \(channelId): \(error)")
        }
        self.writer = nil
    }
    
    nonisolated func channelActive(_ stream: AsyncStream<Void>, id: String) {}
    
    nonisolated func channelInactive(_ stream: AsyncStream<Void>, id: String) {
        Task { [weak self] in
            guard let self else { return }
            await self.handleChannelTermination(reason: "inactive", channelId: id)
        }
    }
    
    func reportChildChannel(error: any Error, id: String) async {
        logger.log(level: .error, message: "Child channel error for id \(id): \(error)")
        await handleChannelTermination(reason: "error", channelId: id)
    }
    
    func didShutdownChildChannel() async {
        await handleChannelTermination(reason: "shutdown", channelId: "unknown")
    }
    
    func deliverWriter<Outbound, Inbound>(context: ConnectionManagerKit.WriterContext<Inbound, Outbound>) async where Outbound : Sendable, Inbound : Sendable {
        guard let outboundWriter = context.writer as? NIOAsyncChannelOutboundWriter<IRCPayload> else {
            logger.log(level: .error, message: "Received unexpected writer type in deliverWriter; expected NIOAsyncChannelOutboundWriter<IRCPayload>")
            return
        }
        await self.setWriter(writer: outboundWriter)
        let source = self.sessionConfiguration.sessionManager.origin
        try? await self.doPing(source: source, secondarySource: nil)
    }
    
    func deliverInboundBuffer<Inbound, Outbound>(context: ConnectionManagerKit.StreamContext<Inbound, Outbound>) async where Inbound : Sendable, Outbound : Sendable {
        await self.processInboundBuffer(context: context)
    }
    
    private func processInboundBuffer<Inbound, Outbound>(
        context: ConnectionManagerKit.StreamContext<Inbound, Outbound>
    ) async where Inbound: Sendable, Outbound: Sendable {
        guard let payload = context.inbound as? IRCPayload else { return }
        switch payload {
        case .irc(let message):
            // Only attempt reassembly for messages that might be multi-part
            // Simple commands like NICK, USER, PING, PONG don't need reassembly
            let needsReassembly: Bool
            switch message.command {
            case .privMsg, .notice:
                needsReassembly = true
            default:
                needsReassembly = false
            }
            
            if needsReassembly {
                do {
                    if let reassembledMessage = try await self.messageGenerator.messageReassembler(ircMessage: message) {
                        await processMessage(reassembledMessage)
                    } else {
                        // If reassembly returns nil, process the original message
                        await processMessage(message)
                    }
                } catch {
                    self.logger.log(level: .error, message: "Failed to reassemble message: \(error)")
                    // Log more details about decoding errors
                    if let decodingError = error as? DecodingError {
                        self.logger.log(level: .debug, message: "Decoding error details: \(decodingError)")
                    }
                    // Continue processing the original message even if reassembly fails
                    await processMessage(message)
                }
            } else {
                // Simple commands don't need reassembly, process directly
                await processMessage(message)
            }
            switch message.command {
            case .quit(_):
                self.logger.log(level: .info, message: "Finishing stream with session \(id)")
                try? await unregisterCurrentSesssion()
            default:
                break
            }
        default:
            break
        }
    }
    
    public func doPing(source: String, secondarySource: String?) async throws {
        let message = IRCMessage(origin: source,
                                 command: .ping(server: source,
                                                server2: secondarySource))
        await sendMessage(message)
    }
    
    @discardableResult
    func sendMessage(_ message: IRCMessage) async -> Bool {
        do {
            guard let writer else {
                let nick = sessionInfo.nick
                let nickDescription: String
                if let nick {
                    let deviceIdDescription = nick.deviceId?.uuidString ?? "nil"
                    nickDescription = "\(nick.name) (\(deviceIdDescription))"
                } else {
                    nickDescription = "nil"
                }
                logger.log(level: .warning, message: "Attempted to send message without an available writer for session id \(id), nick: \(nickDescription); treating as offline")
                return false
            }
            try await transportMessage(
                messageGenerator,
                executor: executor,
                logger: logger,
                writer: writer,
                origin: message.origin ?? "unknown_origin",
                command: message.command,
                tags: message.tags)
            return true
        } catch {
            logger.log(level: .error, message: "There was an error sending next message - Error: \(error)")
            return false
        }
    }
}


public enum MessageFlag: String, Codable, Sendable {
    case publishUserConfiguration, friendshipStateRequest, communicationSynchronization, contactCreated, addContacts, privateMessage
}

public struct MessagePacket: Codable, Sendable, Equatable {
    
    public let id: String
    public let flag: MessageFlag
    public let userConfiguration: UserConfiguration?
    public let sender: UUID?
    public let recipient: NeedleTailNick?
    public let message: SignedRatchetMessage?
    
    public init(
        id: String,
        flag: MessageFlag,
        userConfiguration: UserConfiguration? = nil,
        sender: UUID? = nil,
        recipient: NeedleTailNick? = nil,
        message: SignedRatchetMessage? = nil,
    ) {
        self.id = id
        self.flag = flag
        self.userConfiguration = userConfiguration
        self.sender = sender
        self.recipient = recipient
        self.message = message
    }
    
    public static func == (lhs: MessagePacket, rhs: MessagePacket) -> Bool {
        return lhs.id == rhs.id
    }
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

public struct User: Codable, Sendable, Hashable {
    
    public static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
    
    public var id = UUID()
    public var _id: String
    public var configuration: UserConfiguration
    public var tokens: [String: String]?
    public var deviceTokens: [String: String] {
        get { tokens ?? [:] }
        set { tokens = newValue }
    }
    
    public init(
        username: String,
        configuration: UserConfiguration
    ) {
        self._id = username
        self.configuration = configuration
        self.tokens = [:]
    }
    
    public mutating func updateConfiguration(_ newConfiguration: UserConfiguration) {
        self.configuration = newConfiguration
    }
}

public struct UserConfiguration: Codable, Sendable, Equatable {
    
    /// Coding keys for encoding and decoding the struct.
    enum CodingKeys: String, CodingKey, Codable, Sendable {
        case signingPublicKey = "a"
        case signedDevices = "b"
        case signedPublicOneTimeKeys = "c"
        case signedPublicMLKEMOneTimeKeys = "d"
    }
    
    var signingPublicKey: Data
    var signedDevices: [SignedDeviceConfiguration]
    var signedPublicOneTimeKeys: [SignedPublicOneTimeKey]
    var signedPublicMLKEMOneTimeKeys: [SignedMLKEMOneTimeKey]
    
    init(
        signingPublicKey: Data,
        signedDevices: [SignedDeviceConfiguration],
        signedPublicOneTimeKeys: [SignedPublicOneTimeKey],
        signedPublicMLKEMOneTimeKeys: [SignedMLKEMOneTimeKey]
    ) {
        self.signingPublicKey = signingPublicKey
        self.signedDevices = signedDevices
        self.signedPublicOneTimeKeys = signedPublicOneTimeKeys
        self.signedPublicMLKEMOneTimeKeys = signedPublicMLKEMOneTimeKeys
    }
    
    mutating func setSignedPublicOneTimeKeys(_ signedPublicOneTimeKeys: [SignedPublicOneTimeKey]) {
        self.signedPublicOneTimeKeys = signedPublicOneTimeKeys
    }
    
    mutating func setSignedPublicOneTimeMLKEMKeys(_ signedPublicMLKEMOneTimeKeys: [SignedMLKEMOneTimeKey]) {
        self.signedPublicMLKEMOneTimeKeys = signedPublicMLKEMOneTimeKeys
    }
    
    func getVerifiedDevices() throws -> [UserDeviceConfiguration] {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKey)
        return try signedDevices.compactMap { try $0.verified(using: publicKey) }
    }
    
    func getVerifiedKeys(deviceId: UUID) async throws -> [CurvePublicKey] {
        guard let device = signedDevices.first(where: { $0.id == deviceId }),
              let verifiedDevice = try device.verified(using: try Curve25519.Signing.PublicKey(rawRepresentation: self.signingPublicKey)) else {
            throw Errors.invalidSignature
        }
        
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: verifiedDevice.signingPublicKey)
        
        // Use a dictionary for faster access
        let keysByDeviceId = Dictionary(grouping: signedPublicOneTimeKeys, by: { $0.deviceId })
        let filteredKeys = keysByDeviceId[deviceId] ?? []
        
        // Use async let to run verifications concurrently
        let verifiedKeys: [CurvePublicKey] = try await withThrowingTaskGroup(of: CurvePublicKey?.self) { group in
            for key in filteredKeys {
                group.addTask {
                    return try? key.verified(using: publicKey)
                }
            }
            
            var results: [CurvePublicKey] = []
            for try await result in group {
                if let verifiedKey = result {
                    results.append(verifiedKey)
                }
            }
            
            return results
        }
        
        return verifiedKeys
    }
    
    struct SignedDeviceConfiguration: Codable, Sendable {
        let id: UUID
        let data: Data
        let signature: Data
        
        enum CodingKeys: String, CodingKey, Codable, Sendable {
            case id = "a"
            case data = "b"
            case signature = "c"
        }
        
        init(device: UserDeviceConfiguration, signingKey: Curve25519.Signing.PrivateKey) throws {
            let encoded = try BinaryEncoder().encode(device)
            self.id = device.deviceId
            self.data = encoded
            self.signature = try signingKey.signature(for: encoded)
        }
        
        func verified(using publicKey: Curve25519.Signing.PublicKey) throws -> UserDeviceConfiguration? {
            guard publicKey.isValidSignature(signature, for: data) else { return nil }
            return try BinaryDecoder().decode(UserDeviceConfiguration.self, from: data)
        }
    }
    
    struct SignedPublicOneTimeKey: Codable, Sendable {
        let id: UUID
        let deviceId: UUID
        let data: Data
        let signature: Data
        
        enum CodingKeys: String, CodingKey, Codable, Sendable {
            case id = "a"
            case deviceId = "b"
            case data = "c"
            case signature = "d"
        }
        
        init(
            key: CurvePublicKey,
            deviceId: UUID,
            signingKey: Curve25519.Signing.PrivateKey
        ) throws {
            let encoded = try BinaryEncoder().encode(key)
            self.id = key.id
            self.deviceId = deviceId
            self.data = encoded
            self.signature = try signingKey.signature(for: encoded)
        }
        
        func verified(using publicKey: Curve25519.Signing.PublicKey) throws -> CurvePublicKey? {
            guard publicKey.isValidSignature(signature, for: data) else { return nil }
            return try BinaryDecoder().decode(CurvePublicKey.self, from: data)
        }
    }
    
    struct SignedMLKEMOneTimeKey: Codable, Sendable {
        let id: UUID
        let deviceId: UUID
        let data: Data
        let signature: Data
        
        enum CodingKeys: String, CodingKey, Codable, Sendable {
            case id = "a"
            case deviceId = "b"
            case data = "c"
            case signature = "d"
        }
        
        init(
            key: MLKEMPublicKey,
            deviceId: UUID,
            signingKey: Curve25519.Signing.PrivateKey
        ) throws {
            let encoded = try BinaryEncoder().encode(key)
            self.id = key.id
            self.deviceId = deviceId
            self.data = encoded
            self.signature = try signingKey.signature(for: encoded)
        }
        
        func mlKEMVerified(using publicKey: Curve25519.Signing.PublicKey) throws -> MLKEMPublicKey? {
            guard publicKey.isValidSignature(signature, for: data) else { return nil }
            return try BinaryDecoder().decode(MLKEMPublicKey.self, from: data)
        }
    }
    
    public static func ==(lhs: UserConfiguration, rhs: UserConfiguration) -> Bool {
        return lhs.signingPublicKey == rhs.signingPublicKey
    }
}

public struct UserDeviceConfiguration: Codable, Sendable {
    
    /// Unique identifier for the device.
    public let deviceId: UUID
    /// Data representing the signing identity of the device.
    public var signingPublicKey: Data
    /// Public key associated with the device.
    public var longTermPublicKey: Data
    /// Public key associated with the device.
    public var finalMLKEMPublicKey: MLKEMPublicKey
    /// An optional Device Name to identify What device this actualy is.
    public let deviceName: String?
    /// HMAC data for JWT Authentication
    public let hmacData: Data
    /// A flag indicating if this device is the master device.
    public let isMasterDevice: Bool
    
    /// Coding keys for encoding and decoding the struct.
    enum CodingKeys: String, CodingKey, Codable, Sendable {
        case deviceId = "a"
        case signingPublicKey = "b"
        case longTermPublicKey = "c"
        case finalMLKEMPublicKey = "d"
        case deviceName = "e"
        case hmacData = "f"
        case isMasterDevice = "g"
    }
    
    /// Initializes a new `UserDeviceConfiguration` instance.
    /// - Parameters:
    ///   - deviceId: The unique identifier for the device.
    ///   - signingIdentity: The signing identity data.
    ///   - publicKey: The public key data.
    ///   - isMasterDevice: A flag indicating if this is the master device.
    /// - Throws: An error if signing the configuration fails.
    public init(
        deviceId: UUID,
        signingPublicKey: Data,
        longTermPublicKey: Data,
        finalMLKEMPublicKey: MLKEMPublicKey,
        deviceName: String?,
        hmacData: Data,
        isMasterDevice: Bool
    ) throws {
        self.deviceId = deviceId
        self.signingPublicKey = signingPublicKey
        self.longTermPublicKey = longTermPublicKey
        self.finalMLKEMPublicKey = finalMLKEMPublicKey
        self.deviceName = deviceName
        self.hmacData = hmacData
        self.isMasterDevice = isMasterDevice
    }
}

public struct CurvePublicKey: Codable, Sendable {
    
    public let id: UUID
    public let rawRepresentation: Data
    
    public init (id: UUID = UUID(), _ rawRepresentation: Data) throws {
        guard rawRepresentation.count == 32 else {
            throw Errors.invalidKeySize
        }
        self.id = id
        self.rawRepresentation = rawRepresentation
    }
    
}

public struct MLKEMPublicKey: Codable, Sendable, Equatable {
    /// A unique identifier for the key (e.g. device or session key).
    public let id: UUID
    
    /// The raw key data.
    public let rawRepresentation: Data
    
    /// Initializes a new Kyber1024 public key wrapper.
    ///
    /// - Parameter rawRepresentation: The raw Kyber1024 public key bytes.
    /// - Throws: `KyberError.invalidKeySize` if the key size is incorrect.
    public init(id: UUID = UUID(), _ rawRepresentation: Data) throws {
        guard rawRepresentation.count == Int(1568) else {
            throw Errors.invalidKeySize
        }
        self.id = id
        self.rawRepresentation = rawRepresentation
    }
}

public struct OneTimeKeys: Codable, Sendable {
    public let curve: CurvePublicKey?
    public let mlKEM: MLKEMPublicKey?
    
    public init(curve: CurvePublicKey? = nil,
                mlKEM: MLKEMPublicKey? = nil
    ) {
        self.curve = curve
        self.mlKEM = mlKEM
    }
    
}

enum Errors: Error {
    case invalidKeySize, invalidSignature
}



