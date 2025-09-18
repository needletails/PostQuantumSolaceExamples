//
//  SessionManager.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import Foundation
import PQSSession
import ConnectionManagerKit
import NeedleTailLogger
import NeedleTailIRC
import NeedleTailAsyncSequence
import NTKLoop
import Network
import BSON

let logger = NeedleTailLogger("PQSDemoLogger")

actor SessionManager {
    
    let receiver: MessageReceiverManager
    let useWebSockets: Bool
    
    @MainActor let socket = WebSocketClient(socketReceiver: .init())
    init(receiver: MessageReceiverManager, useWebSockets: Bool = false) {
        self.receiver = receiver
        self.useWebSockets = useWebSockets
    }
    
    // MARK: - Properties
    let connectionManager = ConnectionManager<IRCPayload, IRCPayload>(logger: logger)
    let taskLoop = NTKLoop()
    var pqsSession: PQSSession = .shared
    var delegate: NetworkDelegate?
    var transport: SessionTransport?
    var eventStreamTask: Task<Void, Error>?
    var messageStreamTask: Task<Void, Error>?
    private var nick: NeedleTailNick?
    
    // MARK: - Public Methods
    
    public func createSession(
        secretName: String,
        appPassword: String,
        store: PQSSessionStore
    ) async throws {
        logger.log(level: .info, message: "Creating session for user: \(secretName)")
        
        // Setup delegates and transport
        try await setupDelegatesAndTransport(store: store)
        
        do {
            // Create or resume crypto session
            pqsSession = try await pqsSession.createSession(
                secretName: secretName,
                appPassword: appPassword,
                createInitialTransport: createInitialTransportClosure()
            )
            
            if useWebSockets {
                await socket.shutDown()
                messageStreamTask?.cancel()
                messageStreamTask = nil
                eventStreamTask?.cancel()
                eventStreamTask = nil
            } else {
                await connectionManager.gracefulShutdown()
            }

            // Start the session
            try await startSession(store: store, sessionTransport: transport)
        } catch {
            logger.log(level: .error, message: "ERROR CREATING SESSION: \(error)")
            throw error
        }
    }
    
    public func startSession(
        store: PQSSessionStore,
        sessionTransport: SessionTransport? = nil
    ) async throws {
        logger.log(level: .info, message: "Starting session")
        
        // Setup transport
        let transport = sessionTransport ?? SessionTransportManager(logger: logger)
        self.transport = transport
        
        // Setup delegates
        try await setupDelegatesAndTransport(store: store, transport: transport)
        
        do {
            // Start PQSSession
            pqsSession = try await pqsSession.startSession(appPassword: AppConfiguration.Session.defaultAppPassword)
            
            guard let sessionContext = await pqsSession.sessionContext else {
                throw PQSSession.SessionErrors.sessionNotInitialized
            }
            
                // Create network connection
                try await createNetworkConnection()
                
                // Wait for connection to establish
                try await Task.sleep(until: .now + .seconds(AppConfiguration.Server.initialDelay))

            // Verify device
            try await verifyDeviceIfNeeded(sessionContext: sessionContext)
            
        } catch {
            logger.log(level: .error, message: "Failed to start session: \(error)")
            throw error
        }
    }
    
    public func verifyDevice(for secretName: String) async throws -> Bool {
        guard let sessionContext = await pqsSession.sessionContext else {
            throw PQSSession.SessionErrors.sessionNotInitialized
        }
        guard let transport else {
            throw SessionManagerError.transportNotInitialized
        }
        
        let configuration = try await transport.findConfiguration(for: secretName)
        let myDeviceId = sessionContext.sessionUser.deviceId
        return try configuration.getVerifiedDevices().contains(where: { $0.deviceId == myDeviceId })
    }
    
    // MARK: - Private Methods
    
    private func setupDelegatesAndTransport(
        store: PQSSessionStore,
        transport: SessionTransport? = nil,
    ) async throws {
        if useWebSockets {
            let wsTransport = transport ?? WebSocketTransportManager(logger: logger, socket: socket)
            self.transport = wsTransport
        } else {
            let transport = transport ?? SessionTransportManager(logger: logger)
            self.transport = transport
        }
        
        let pqsDelegate = PQSSessionDelegateWrapper(
            pqsSession: pqsSession,
            messageReciever: receiver,
            logger: logger
        )
        
        // Set all delegates
        await pqsSession.setPQSSessionDelegate(conformer: pqsDelegate)
        await pqsSession.setDatabaseDelegate(conformer: store)
        await pqsSession.setTransportDelegate(conformer: self.transport!)
        await pqsSession.setReceiverDelegate(conformer: receiver)
        await pqsSession.setLogLevel(AppConfiguration.Session.logLevel)
        self.delegate = pqsSession
    }
    
    private func verifyDeviceIfNeeded(sessionContext: SessionContext) async throws {
        do {
            let isVerified = try await verifyDevice(for: sessionContext.sessionUser.secretName)
            if !isVerified {
                logger.log(level: .warning, message: "Device verification failed - this could be a security issue")
                throw SessionManagerError.verificationFailed
            }
            logger.log(level: .info, message: "Device verification successful")
        } catch {
            logger.log(level: .error, message: "Device verification error: \(error)")
            // Don't throw here as verification might not be critical for demo
        }
    }
    
    func createContact(secretName: String) async throws {
        logger.log(level: .info, message: "Creating contact for secretName: \(secretName)")
        _ = try await pqsSession.createContact(secretName: secretName, requestFriendship: true)
        logger.log(level: .info, message: "Contact creation request sent for: \(secretName)")
    }
}

// MARK: - Errors
extension SessionManager {
    enum SessionManagerError: Error {
        case verificationFailed
        case transportNotInitialized
    }
}
