//
//  AppConfiguration.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import Foundation
import PQSSession
import NeedleTailLogger

public struct AppConfiguration {
    // MARK: - Server Configuration
    public struct Server {
        public static let host = "localhost"
        public static let port: Int = 6667
        public static let enableTLS = false
        public static let cacheKey = "pqs_demo"
        public static let maxReconnectionAttempts = 3
        public static let connectionTimeout: TimeInterval = 10.0
        public static let initialDelay: TimeInterval = 2.0
    }
    
    // MARK: - API Configuration
    public struct API {
        public static let baseURL = "http://localhost:8081"
        public static let timeout: TimeInterval = 30.0
    }
    
    // MARK: - Session Configuration
    public struct Session {
        public static let defaultAppPassword = "123"
        public static let logLevel: Level = .debug
    }
}
