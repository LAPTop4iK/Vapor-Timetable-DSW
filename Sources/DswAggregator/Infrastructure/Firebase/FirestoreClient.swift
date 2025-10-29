//
//  FirestoreClient.swift
//  DswAggregator
//
//  Client for Firestore REST API operations
//

import Vapor
import Foundation

/// Client for reading and writing Firestore documents
actor FirestoreClient {
    private let projectId: String
    private let authenticator: FirestoreAuthenticator
    private let client: Client
    private let logger: Logger

    init(projectId: String, credentials: ServiceAccountCredentials, client: Client, logger: Logger) throws {
        self.projectId = projectId
        self.authenticator = try FirestoreAuthenticator(credentials: credentials, client: client)
        self.client = client
        self.logger = logger
    }

    // MARK: - Read Operations

    /// Get a document from Firestore
    func getDocument<T: Decodable>(collection: String, documentId: String) async throws -> T? {
        let path = "projects/\(projectId)/databases/(default)/documents/\(collection)/\(documentId)"
        let url = "https://firestore.googleapis.com/v1/\(path)"

        let token = try await authenticator.getAccessToken()

        let response = try await client.get(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
        }

        if response.status == .notFound {
            return nil
        }

        guard response.status == .ok else {
            logger.error("Firestore GET failed: \(response.status)")
            throw Abort(.badGateway, reason: "Firestore returned \(response.status)")
        }

        let firestoreDoc = try response.content.decode(FirestoreDocument.self)
        return try convertFromFirestoreDocument(firestoreDoc, as: T.self)
    }

    /// List documents in a collection
    func listDocuments<T: Decodable>(collection: String, pageSize: Int = 100) async throws -> [T] {
        let path = "projects/\(projectId)/databases/(default)/documents/\(collection)"
        let url = "https://firestore.googleapis.com/v1/\(path)?pageSize=\(pageSize)"

        let token = try await authenticator.getAccessToken()

        let response = try await client.get(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
        }

        guard response.status == .ok else {
            logger.error("Firestore LIST failed: \(response.status)")
            throw Abort(.badGateway, reason: "Firestore returned \(response.status)")
        }

        struct ListResponse: Decodable {
            let documents: [FirestoreDocument]?
        }

        let listResponse = try response.content.decode(ListResponse.self)
        guard let docs = listResponse.documents else {
            return []
        }

        return try docs.map { try convertFromFirestoreDocument($0, as: T.self) }
    }

    // MARK: - Write Operations

    /// Create or update a document in Firestore
    func setDocument<T: Encodable>(collection: String, documentId: String, data: T) async throws {
        let path = "projects/\(projectId)/databases/(default)/documents/\(collection)/\(documentId)"
        let url = "https://firestore.googleapis.com/v1/\(path)"

        let token = try await authenticator.getAccessToken()
        let firestoreDoc = try convertToFirestoreDocument(data)

        let response = try await client.patch(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.contentType = .json
            try req.content.encode(firestoreDoc)
        }

        guard response.status == .ok else {
            logger.error("Firestore SET failed: \(response.status)")
            throw Abort(.badGateway, reason: "Firestore write failed: \(response.status)")
        }
    }

    /// Batch write multiple documents (more efficient)
    func batchWrite(writes: [BatchWrite]) async throws {
        let url = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents:batchWrite"

        let token = try await authenticator.getAccessToken()

        struct BatchWriteRequest: Encodable {
            let writes: [BatchWriteEntry]
        }

        struct BatchWriteEntry: Encodable {
            let update: FirestoreDocument
        }

        let entries = try writes.map { write in
            let docPath = "projects/\(projectId)/databases/(default)/documents/\(write.collection)/\(write.documentId)"
            var firestoreDoc = try convertToFirestoreDocument(write.data)
            firestoreDoc.name = docPath
            return BatchWriteEntry(update: firestoreDoc)
        }

        let request = BatchWriteRequest(writes: entries)

        let response = try await client.post(URI(string: url)) { req in
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
            req.headers.contentType = .json
            try req.content.encode(request)
        }

        guard response.status == .ok else {
            logger.error("Firestore BATCH_WRITE failed: \(response.status)")
            throw Abort(.badGateway, reason: "Firestore batch write failed: \(response.status)")
        }
    }

    // MARK: - Private Helpers

    private func convertToFirestoreDocument<T: Encodable>(_ data: T) throws -> FirestoreDocument {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        let json = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]

        var fields: [String: FirestoreValue] = [:]
        for (key, value) in json {
            fields[key] = convertToFirestoreValue(value)
        }

        return FirestoreDocument(name: "", fields: fields)
    }

    private func convertToFirestoreValue(_ value: Any) -> FirestoreValue {
        if let str = value as? String {
            return .string(str)
        } else if let num = value as? Int {
            return .integer(num)
        } else if let num = value as? Double {
            return .double(num)
        } else if let bool = value as? Bool {
            return .boolean(bool)
        } else if let arr = value as? [Any] {
            return .array(arr.map { convertToFirestoreValue($0) })
        } else if let dict = value as? [String: Any] {
            var fields: [String: FirestoreValue] = [:]
            for (k, v) in dict {
                fields[k] = convertToFirestoreValue(v)
            }
            return .map(fields)
        } else if value is NSNull {
            return .null
        }
        return .null
    }

    private func convertFromFirestoreDocument<T: Decodable>(_ doc: FirestoreDocument, as type: T.Type) throws -> T {
        let json = convertFromFirestoreFields(doc.fields)
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: jsonData)
    }

    private func convertFromFirestoreFields(_ fields: [String: FirestoreValue]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in fields {
            result[key] = convertFromFirestoreValue(value)
        }
        return result
    }

    private func convertFromFirestoreValue(_ value: FirestoreValue) -> Any {
        switch value {
        case .string(let str):
            return str
        case .integer(let num):
            return num
        case .double(let num):
            return num
        case .boolean(let bool):
            return bool
        case .array(let arr):
            return arr.map { convertFromFirestoreValue($0) }
        case .map(let fields):
            return convertFromFirestoreFields(fields)
        case .null:
            return NSNull()
        }
    }
}

// MARK: - Supporting Types

struct FirestoreDocument: Codable {
    var name: String
    var fields: [String: FirestoreValue]
}

enum FirestoreValue: Codable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case array([FirestoreValue])
    case map([String: FirestoreValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try? container.decode(String.self, forKey: .stringValue) {
            self = .string(value)
        } else if let value = try? container.decode(String.self, forKey: .integerValue), let intValue = Int(value) {
            self = .integer(intValue)
        } else if let value = try? container.decode(Double.self, forKey: .doubleValue) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self, forKey: .booleanValue) {
            self = .boolean(value)
        } else if let arrayContainer = try? container.nestedContainer(keyedBy: ArrayCodingKeys.self, forKey: .arrayValue),
                  let values = try? arrayContainer.decode([FirestoreValue].self, forKey: .values) {
            self = .array(values)
        } else if let mapContainer = try? container.nestedContainer(keyedBy: MapCodingKeys.self, forKey: .mapValue),
                  let fields = try? mapContainer.decode([String: FirestoreValue].self, forKey: .fields) {
            self = .map(fields)
        } else if (try? container.decodeNil(forKey: .nullValue)) == true {
            self = .null
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .string(let value):
            try container.encode(value, forKey: .stringValue)
        case .integer(let value):
            try container.encode(String(value), forKey: .integerValue)
        case .double(let value):
            try container.encode(value, forKey: .doubleValue)
        case .boolean(let value):
            try container.encode(value, forKey: .booleanValue)
        case .array(let values):
            var arrayContainer = container.nestedContainer(keyedBy: ArrayCodingKeys.self, forKey: .arrayValue)
            try arrayContainer.encode(values, forKey: .values)
        case .map(let fields):
            var mapContainer = container.nestedContainer(keyedBy: MapCodingKeys.self, forKey: .mapValue)
            try mapContainer.encode(fields, forKey: .fields)
        case .null:
            try container.encodeNil(forKey: .nullValue)
        }
    }

    enum CodingKeys: String, CodingKey {
        case stringValue, integerValue, doubleValue, booleanValue, arrayValue, mapValue, nullValue
    }

    enum ArrayCodingKeys: String, CodingKey {
        case values
    }

    enum MapCodingKeys: String, CodingKey {
        case fields
    }
}

struct BatchWrite {
    let collection: String
    let documentId: String
    let data: any Encodable
}
