//
//  SessionManager.swift (Library target)
//

import Foundation
import NIOCore
import NeedleTailIRC
import NeedleTailLogger
import ConnectionManagerKit
import BSON
@preconcurrency import Crypto
import AsyncHTTPClient

actor SessionManager {
    
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
        guard let targetSession = await cache.findSession(nick: nick) else {
            fatalError()
        }
        return targetSession
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
            if await session.sessionInfo.nick!.name == needletailNick.name {
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
    
    /// Updates the session handler for the given nickname.
    /// - Throws: An error if the session does not exist.
    func updateSession(nick: NeedleTailNick, handler: SessionHandler) async throws {
        guard sessions[nick] != nil else {
            fatalError()
        }
        sessions[nick] = handler
    }
    
    /// Deletes the session associated with the given nickname.
    /// - Throws: An error if the session does not exist.
    func removeSession(nick: NeedleTailNick) async throws {
        if sessions.removeValue(forKey: nick) == nil {
            fatalError("Failed to remove session for \(nick): session does not exist")
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
            try! await doPing(source: origin, secondarySource: origin2)
        case .privMsg(let recipients, let payload):
            let sender = try! await self.getSender(message)
            try! await doMessage(
                senderID: sender,
                recipients: recipients,
                message: payload,
                associatedTags: tags
            )
        case .nick(let nickName):
            let sender = try! await self.getSender(message)
            try! await doNick(senderID: sender, nick: nickName, associatedTags: tags)
            
        case .user(let info):
            try! await doUserInfo(info: info, associatedTags: tags)
        default:
            break
        }
    }
    
    func doMessage(
        senderID: IRCUserIdentifier?,
        recipients: [IRCMessageRecipient],
        message: String,
        associatedTags: [IRCTag]?
    ) async throws {
        guard let data = Data(base64Encoded: message) else {
            fatalError()
        }
        let messagePacket = try BSONDecoder().decode(MessagePacket.self, from: Document(data: data))
        for recipient in recipients {
            switch recipient {
            case .all:
                break
            case .nick(let nick):
                switch messagePacket.flag {
                case .publishUserConfiguration:
                    guard let configuration = messagePacket.userConfiguration else {
                        fatalError()
                    }
                    
                    let user = User(
                        username: nick.name,
                        configuration: configuration)
                    
                    var request = HTTPClientRequest(url: "http://localhost:8080/api/store/create-user")
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
                    self.logger.log(level: .info, message: "Searching for session for \(nick)")
                    //TODO: Ensure that unregister removes the session i think that we are sending on an old session causing closed channel error
                    if let session = await sessionConfiguration.sessionManager.getSessions().async.first(where: { await $0.sessionInfo.nick == nick }) {
                        let sender = IRCUserIdentifier(nick: senderID!.nick)
                        try await doSendMessage(messagePacket,
                                                sender: sender,
                                                recipient: IRCMessageRecipient.nick(nick),
                                                targetSession: session)
                    } else {
                        // Log when recipient is not online
                        self.logger.log(level: .warning, message: "Recipient \(nick.name) is not online or not registered. Message not delivered.")
                        print("WARNING: Recipient \(nick.name) is not online. Contact creation request not delivered.")
                    }
                }
            case .channel(let channelName):
                self.logger.log(level: .info, message: "\(#function) - Channel: \(channelName)")
            }
        }
    }
    
    func doSendMessage(_
                       messagePacket: MessagePacket,
                       sender: IRCUserIdentifier,
                       recipient: IRCMessageRecipient,
                       targetSession: SessionHandler
    ) async throws {
        self.logger.log(level: .info, message: "Sender: \(sender) is sending message to Recipient: \(recipient)")
        let senderString = try BSONEncoder().encode(sender).makeData().base64EncodedString()
        let packetString = try BSONEncoder().encode(messagePacket).makeData().base64EncodedString()
        let message = IRCMessage(
            origin: senderString,
            command: .privMsg([recipient], packetString))
        await targetSession.sendMessage(message)
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
            messageInfo.setOrigin(try BSONEncoder().encode(sender).makeData().base64EncodedString())
        }
        
        try await sessionConfiguration.sessionManager.registerSession(self, needletailNick: nick)
    }
    
    func doUserInfo(info: IRCUserDetails, associatedTags: [IRCTag]?) async throws {
        self.logger.log(level: .info, message: "Do User Info: \(info)")
        guard sessionInfo.state == SessionState.registerNick else {
            fatalError()
        }
        
        sessionInfo.setState(.registerUserInfo)
        
        self.logger.log(level: .info, message: "Registering User Info")
        sessionInfo.setUserInfo(info)
        guard let info = sessionInfo.userInfo else { assert(sessionInfo.userInfo != nil); return }
        guard let nick = sessionInfo.nick else { assert(sessionInfo.nick != nil); return }
        sessionInfo.setUserId(IRCUserIdentifier(nick: nick))
        sessionInfo.setState(.registered)
        self.logger.log(level: .info, message: "Registered User: \(nick) with Info: \(info)")
    }
    
    func getSender(_ message: IRCMessage) async throws -> IRCUserIdentifier {
        guard let origin = message.origin else {
            fatalError()
        }
        guard let data = Data(base64Encoded: origin) else { throw NeedleTailError.nilData }
        do {
            let senderNick = try BSONDecoder().decode(NeedleTailNick.self, from: Document(data: data))
            guard
                let userId = IRCUserIdentifier(
                    senderNick.name,
                    deviceId: senderNick.deviceId
                )
            else { fatalError() }
            return userId
        } catch {
            //We Are Pinging and Ponging. Maybe this should be inlined with the rest of the origins we send
            return try BSONDecoder().decode(IRCUserIdentifier.self, from: Document(data: data))
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
    nonisolated func channelActive(_ stream: AsyncStream<Void>, id: String) {}
    nonisolated func channelInactive(_ stream: AsyncStream<Void>, id: String) {}
    func reportChildChannel(error: any Error, id: String) async {}
    func didShutdownChildChannel() async {}
    
    func deliverWriter<Outbound, Inbound>(context: ConnectionManagerKit.WriterContext<Inbound, Outbound>) async where Outbound : Sendable, Inbound : Sendable {
        guard let outboundWriter = context.writer as? NIOAsyncChannelOutboundWriter<IRCPayload> else { fatalError() }
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
            if let reassembledMessage = try! await self.messageGenerator.messageReassembler(ircMessage: message) {
                await processMessage(reassembledMessage)
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
    
    func sendMessage(_ message: IRCMessage) async {
        do {
            guard let writer else { fatalError() }
            try await transportMessage(
                messageGenerator,
                executor: executor,
                logger: logger,
                writer: writer,
                origin: message.origin ?? "unknown_origin",
                command: message.command,
                tags: message.tags)
        } catch {
            logger.log(level: .error, message: "There was an error sending next message - Error: \(error)")
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
    public let message: SignedRatchetMessage?
    
    public init(
        id: String,
        flag: MessageFlag,
        userConfiguration: UserConfiguration? = nil,
        sender: UUID? = nil,
        message: SignedRatchetMessage? = nil,
    ) {
        self.id = id
        self.flag = flag
        self.userConfiguration = userConfiguration
        self.sender = sender
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
    public enum CodingKeys: String, CodingKey, Codable, Sendable {
        case signingPublicKey = "a"
        case signedDevices = "b"
        case signedPublicOneTimeKeys = "c"
        case signedPublicKyberOneTimeKeys = "d"
    }
    
    public var signingPublicKey: Data
    public var signedDevices: [SignedDeviceConfiguration]
    public var signedPublicOneTimeKeys: [SignedPublicOneTimeKey]
    public var signedPublicKyberOneTimeKeys: [SignedKyberOneTimeKey]
    
    public init(
        signingPublicKey: Data,
        signedDevices: [SignedDeviceConfiguration],
        signedPublicOneTimeKeys: [SignedPublicOneTimeKey],
        signedPublicKyberOneTimeKeys: [SignedKyberOneTimeKey]
    ) {
        self.signingPublicKey = signingPublicKey
        self.signedDevices = signedDevices
        self.signedPublicOneTimeKeys = signedPublicOneTimeKeys
        self.signedPublicKyberOneTimeKeys = signedPublicKyberOneTimeKeys
    }
    
    mutating func setSignedPublicOneTimeKeys(_ signedPublicOneTimeKeys: [SignedPublicOneTimeKey]) {
        self.signedPublicOneTimeKeys = signedPublicOneTimeKeys
    }
    
    mutating func setSignedPublicOneTimeKyberKeys(_ signedPublicKyberOneTimeKeys: [SignedKyberOneTimeKey]) {
        self.signedPublicKyberOneTimeKeys = signedPublicKyberOneTimeKeys
    }
    
    public func getVerifiedDevices() throws -> [UserDeviceConfiguration] {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKey)
        return try signedDevices.compactMap { try $0.verified(using: publicKey) }
    }
    
    public func getVerifiedKeys(deviceId: UUID) async throws -> [Curve25519PublicKeyRepresentable] {
        guard let device = signedDevices.first(where: { $0.id == deviceId }),
              let verifiedDevice = try device.verified(using: try Curve25519.Signing.PublicKey(rawRepresentation: self.signingPublicKey)) else {
            fatalError()
        }
        
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: verifiedDevice.signingPublicKey)
        
        // Use a dictionary for faster access
        let keysByDeviceId = Dictionary(grouping: signedPublicOneTimeKeys, by: { $0.deviceId })
        let filteredKeys = keysByDeviceId[deviceId] ?? []
        
        // Use async let to run verifications concurrently
        let verifiedKeys: [Curve25519PublicKeyRepresentable] = try await withThrowingTaskGroup(of: Curve25519PublicKeyRepresentable?.self) { group in
            for key in filteredKeys {
                group.addTask {
                    return try? key.verified(using: publicKey)
                }
            }
            
            var results: [Curve25519PublicKeyRepresentable] = []
            for try await result in group {
                if let verifiedKey = result {
                    results.append(verifiedKey)
                }
            }
            
            return results
        }
        
        return verifiedKeys
    }
    
    public struct SignedDeviceConfiguration: Codable, Sendable {
        let id: UUID
        let data: Data
        let signature: Data
        
        public enum CodingKeys: String, CodingKey, Codable, Sendable {
            case id = "a"
            case data = "b"
            case signature = "c"
        }
        
        public init(device: UserDeviceConfiguration, signingKey: Curve25519.Signing.PrivateKey) throws {
            let encoded = try BSONEncoder().encode(device).makeData()
            self.id = device.deviceId
            self.data = encoded
            self.signature = try signingKey.signature(for: encoded)
        }
        
        func verified(using publicKey: Curve25519.Signing.PublicKey) throws -> UserDeviceConfiguration? {
            guard publicKey.isValidSignature(signature, for: data) else { return nil }
            return try BSONDecoder().decode(UserDeviceConfiguration.self, from: Document(data: data))
        }
    }
    
    public struct SignedPublicOneTimeKey: Codable, Sendable {
        public let id: UUID
        public let deviceId: UUID
        public let data: Data
        public let signature: Data
        
        public enum CodingKeys: String, CodingKey, Codable, Sendable {
            case id = "a"
            case deviceId = "b"
            case data = "c"
            case signature = "d"
        }
        
        public init(
            key: Curve25519PublicKeyRepresentable,
            deviceId: UUID,
            signingKey: Curve25519.Signing.PrivateKey
        ) throws {
            let encoded = try BSONEncoder().encode(key).makeData()
            self.id = key.id
            self.deviceId = deviceId
            self.data = encoded
            self.signature = try signingKey.signature(for: encoded)
        }
        
        public func verified(using publicKey: Curve25519.Signing.PublicKey) throws -> Curve25519PublicKeyRepresentable? {
            guard publicKey.isValidSignature(signature, for: data) else { return nil }
            return try BSONDecoder().decode(Curve25519PublicKeyRepresentable.self, from: Document(data: data))
        }
    }
    
    public struct SignedKyberOneTimeKey: Codable, Sendable {
        public let id: UUID
        public let deviceId: UUID
        public let data: Data
        public let signature: Data
        
        public enum CodingKeys: String, CodingKey, Codable, Sendable {
            case id = "a"
            case deviceId = "b"
            case data = "c"
            case signature = "d"
        }
        
        public init(
            key: Kyber1024PublicKeyRepresentable,
            deviceId: UUID,
            signingKey: Curve25519.Signing.PrivateKey
        ) throws {
            let encoded = try BSONEncoder().encode(key).makeData()
            self.id = key.id
            self.deviceId = deviceId
            self.data = encoded
            self.signature = try signingKey.signature(for: encoded)
        }
        
        public func kyberVerified(using publicKey: Curve25519.Signing.PublicKey) throws -> Kyber1024PublicKeyRepresentable? {
            guard publicKey.isValidSignature(signature, for: data) else { return nil }
            return try BSONDecoder().decode(Kyber1024PublicKeyRepresentable.self, from: Document(data: data))
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
    public var finalKyber1024PublicKey: Kyber1024PublicKeyRepresentable
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
        case finalKyber1024PublicKey = "d"
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
        finalKyber1024PublicKey: Kyber1024PublicKeyRepresentable,
        deviceName: String?,
        hmacData: Data,
        isMasterDevice: Bool
    ) throws {
        self.deviceId = deviceId
        self.signingPublicKey = signingPublicKey
        self.longTermPublicKey = longTermPublicKey
        self.finalKyber1024PublicKey = finalKyber1024PublicKey
        self.deviceName = deviceName
        self.hmacData = hmacData
        self.isMasterDevice = isMasterDevice
    }
}

public struct Curve25519PublicKeyRepresentable: Codable, Sendable {
    
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

public struct Kyber1024PublicKeyRepresentable: Codable, Sendable, Equatable {
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
    public let curve: Curve25519PublicKeyRepresentable?
    public let kyber: Kyber1024PublicKeyRepresentable?
    
    public init(curve: Curve25519PublicKeyRepresentable? = nil,
                kyber: Kyber1024PublicKeyRepresentable? = nil
    ) {
        self.curve = curve
        self.kyber = kyber
    }
}

enum Errors: Error {
    case invalidKeySize
}


