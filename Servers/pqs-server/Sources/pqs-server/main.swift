import PQSServerCore

@main
struct Main {
    static func main() async throws {
        try await PQSServer.run()
    }
}


