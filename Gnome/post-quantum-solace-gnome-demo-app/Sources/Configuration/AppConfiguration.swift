//
//  AppConfiguration.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PQSSession
import NeedleTailLogger

struct AppConfiguration {
    // MARK: - Server Configuration
    struct Server {
        static let host = "{your-host-name}.local"
        static let port: Int = 6667
        static let enableTLS = false
        static let cacheKey = "pqs_demo_cache_key"
        static let maxReconnectionAttempts = 1
        static let connectionTimeout: TimeInterval = 10.0
        static let initialDelay: TimeInterval = 2.0
    }

    // MARK: - API Configuration
    struct API {
        static let baseURL = "http://{your-host-name}.local:8080"
        static let timeout: TimeInterval = 30.0
    }

    // MARK: - Session Configuration
    struct Session {
        static let defaultAppPassword = "123"
        static let logLevel: Level = .debug
    }
}
