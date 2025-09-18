//
//  main.swift (Executable target)
//

import PQSIRCCore

@main
struct Main {
    static func main() async throws {
        try await PQSIRCCore.run()
    }
}


