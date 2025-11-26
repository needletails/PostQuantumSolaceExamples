//
//  CacheController.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/15/25.
//
import Hummingbird
import HummingbirdHTTP2
import HummingbirdRouter
import BinaryCodable

struct CacheController {
    func addRoutes(to router: Router<BasicRequestContext>, store: PQSCache) {

        router.post("/api/store/create-user") { request, context in
            return try await createUser(request: request, context: context, store: store)
        }
        
        router.get("/api/store/find-user/:secretName") { request, context in
            return try await findUser(request: request, context: context, store: store)
        }
        
        router.post("/api/store/update-user") { request, context in
            return try await updateUser(request: request, context: context, store: store)
        }
    }
    
    private func createUser(request: Request, context: BasicRequestContext, store: PQSCache) async throws -> Response {
        let request = try await request.decode(as: User.self, context: context)
        await store.createUser(user: request)
        return .init(status: .ok)
    }
    
    private func findUser(request: Request, context: BasicRequestContext, store: PQSCache) async throws -> User {
        guard let secretName = context.parameters.get("secretName") else {
            throw Errors.missingParameter
        }
        do {
            guard let user = await store.findUser(secretName: secretName) else {
                throw HTTPError(.init(code: 998, reasonPhrase: "User not found"))
            }
            return user
        } catch {
            throw error
        }
    }
    
    private func updateUser(request: Request, context: BasicRequestContext, store: PQSCache) async throws -> Response {
        let request = try await request.decode(as: User.self, context: context)
        await store.updateUser(user: request)
        return .init(status: .ok)
    }
}

extension User: ResponseGenerator {
    public func response(from request: HummingbirdCore.Request, context: some Hummingbird.RequestContext) throws -> HummingbirdCore.Response {
        let data = try BinaryEncoder().encode(self)
        return Response(
            status: .ok,
            body: .init(byteBuffer: ByteBuffer(data: data))
        )
    }
}


