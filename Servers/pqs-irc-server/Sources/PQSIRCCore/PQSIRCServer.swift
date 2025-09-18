import NIOPosix
import ConnectionManagerKit

public enum PQSIRCCore {
    public static func run(port: Int = 6667) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        var config = Configuration(group: group)
        config.port = port
        let server = IRCServer(executor: .init(eventLoop: group.next(), shouldExecuteAsTask: true))
        await server.startListening(configuration: config)
    }
}


