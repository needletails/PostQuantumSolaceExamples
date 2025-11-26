//
//  PQSCache.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/15/25.
//


import Foundation
@preconcurrency import Crypto
import BinaryCodable

public actor PQSCache {
    public static let shared = PQSCache()
    
    public var configurations: [UserConfiguration] = []
    public var users: [User] = []
    
    public init() {}
    
    public func createUser(user: User) {
        if let index = users.firstIndex(where: { $0._id == user._id }) {
            users[index] = user
        } else {
            users.append(user)
        }
        print("CREATE USER", users.map({ $0._id }))
    }
    
    public func findUser(secretName: String) -> User? {
        print("FIND USER", Date().description)
       return users.first(where: { $0._id == secretName })
    }
    
    public func updateUser(user: User) {
        if let index = users.firstIndex(where: { $0._id == user._id }) {
            users[index] = user
        }
    }
}

public struct UserConfiguration: Codable, Sendable, Equatable {
    
    /// Coding keys for encoding and decoding the struct.
    public enum CodingKeys: String, CodingKey, Codable, Sendable {
        case signingPublicKey = "a"
        case signedDevices = "b"
        case signedPublicOneTimeKeys = "c"
        case signedPublicMLKEMOneTimeKeys = "d"
    }
    
    public var signingPublicKey: Data
    public var signedDevices: [SignedDeviceConfiguration]
    public var signedPublicOneTimeKeys: [SignedPublicOneTimeKey]
    public var signedPublicMLKEMOneTimeKeys: [SignedMLKEMOneTimeKey]
    
    public init(
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
    
    public func getVerifiedDevices() throws -> [UserDeviceConfiguration] {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: signingPublicKey)
        return try signedDevices.compactMap { try $0.verified(using: publicKey) }
    }
    
    public func getVerifiedKeys(deviceId: UUID) async throws -> [CurvePublicKey] {
        guard let device = signedDevices.first(where: { $0.id == deviceId }),
              let verifiedDevice = try device.verified(using: try Curve25519.Signing.PublicKey(rawRepresentation: self.signingPublicKey)) else {
           fatalError()
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
        
        public func verified(using publicKey: Curve25519.Signing.PublicKey) throws -> CurvePublicKey? {
            guard publicKey.isValidSignature(signature, for: data) else { return nil }
            return try BinaryDecoder().decode(CurvePublicKey.self, from: data)
        }
    }
    
    public struct SignedMLKEMOneTimeKey: Codable, Sendable {
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
        
        public func mlKEMVerified(using publicKey: Curve25519.Signing.PublicKey) throws -> MLKEMPublicKey? {
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


