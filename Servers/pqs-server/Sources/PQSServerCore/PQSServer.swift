import Foundation
import Hummingbird
import HummingbirdHTTP2
import HummingbirdRouter
import HummingbirdWebSocket
import WSCompression
import Logging

let serverLogger = Logger(label: "PQSServer")
let connectionManager = ConnectionManager()

struct RouterConfig {
    static func configureRouter(pqsController: PQSController, cacheController: CacheController) -> Router<BasicRequestContext> {
        let router = Router<BasicRequestContext>()
        let store = PQSCache.shared
        pqsController.addRoutes(to: router, store: store)
        cacheController.addRoutes(to: router, store: store)
        
        return router
    }
    
    static func configureWebSocketRouter(controller: WebSocketController) -> Router<BasicWebSocketRequestContext> {
        let router = Router(context: BasicWebSocketRequestContext.self)
        let store = PQSCache.shared
        controller.addRoutes(to: router, store: store)
        return router
    }
}

public enum PQSServer {
    public static func run() async throws {
        var appLogger = Logger(label: "PQSServer")
        appLogger.logLevel = .trace
        let router = RouterConfig.configureRouter(pqsController: PQSController(), cacheController: CacheController())
        let wsRouter = RouterConfig.configureWebSocketRouter(controller: WebSocketController())
        var app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: wsRouter, configuration: .init(maxFrameSize: 500_000, extensions: [.perMessageDeflate()])),
            configuration: .init(address: .hostname("0.0.0.0", port: 8081)),
            logger: appLogger
        )
        app.addServices(connectionManager)
        try await app.runService()
    }
}


