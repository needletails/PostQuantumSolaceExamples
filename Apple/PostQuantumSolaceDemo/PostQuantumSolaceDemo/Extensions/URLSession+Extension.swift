//
//  URLSession+Extension.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import BSON

enum RequestType: String {
    case post = "POST"
    case get = "GET"
    case delete = "DELETE"
    case put = "PUT"
}

struct Response<T: Codable & Sendable>: Sendable {
    let data: T?
    let urlResponse: URLResponse
}

extension URLSession {
    enum Errors: Error {
        case httpBodyIsEmpty, responseError(String, String)
    }
    
    func request<T: Codable>(
        method: RequestType = .get,
        httpHost: String,
        url: String,
        nickname: String,
        token: String?,
        body: Data? = nil
    ) async throws -> Response<T> {
        // Ensure the URL is valid
        guard let url = URL(string: "\(httpHost)/\(url)") else {
            throw URLError(.badURL)
        }
        
        // Prepare headers
        var headers: [String: String] = ["x-nickname": nickname]
        
        if let token = token {
            headers["x-token"] = token
        }
        
        return try await request(
            url: url,
            method: method,
            headers: headers,
            body: body,
            codableType: .bson)
    }
    
    enum CodableType {
        case bson, json
    }
    
    func request<T: Codable>(
        url: URL,
        method: RequestType,
        headers: [String: String]? = nil,
        body: Data? = nil,
        codableType: CodableType = .bson
    ) async throws -> Response<T> {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 60 * 5
        if codableType == .json {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        } else {
            request.addValue("application/bson", forHTTPHeaderField: "Content-Type")
        }
        // Set headers if provided
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Perform the network request
        let (data, response) = try await (method == .post || method == .put || method == .delete) ?
        self.upload(for: request, from: body ?? Data()) :
        self.data(for: request)
        
        // Handle the response
        return try handleResponse(data: data, response: response, codableType: codableType)
    }
    
    private func handleResponse<T: Codable>(data: Data, response: URLResponse, codableType: CodableType) throws -> Response<T> {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Check for successful status codes (2xx)
        guard (200...299).contains(httpResponse.statusCode) else {
            return Response(data: nil, urlResponse: response)
        }
        let decodedResponse: T
        // Decode the response based on the expected type
        if codableType == .json {
            decodedResponse = try JSONDecoder().decode(T.self, from: data)
        } else {
            decodedResponse = try BSONDecoder().decode(T.self, from: Document(data: data))
        }
        return Response(data: decodedResponse, urlResponse: response)
    }
}
