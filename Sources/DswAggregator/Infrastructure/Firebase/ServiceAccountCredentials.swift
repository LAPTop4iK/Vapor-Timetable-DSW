//
//  ServiceAccountCredentials.swift
//  DswAggregator
//
//  Google Service Account credentials structure
//

import Vapor

/// Google Service Account JSON key structure
struct ServiceAccountCredentials: Decodable {
    let type: String
    let projectId: String
    let privateKeyId: String
    let privateKey: String
    let clientEmail: String
    let clientId: String
    let authUri: String
    let tokenUri: String
    let authProviderX509CertUrl: String
    let clientX509CertUrl: String

    enum CodingKeys: String, CodingKey {
        case type
        case projectId = "project_id"
        case privateKeyId = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientId = "client_id"
        case authUri = "auth_uri"
        case tokenUri = "token_uri"
        case authProviderX509CertUrl = "auth_provider_x509_cert_url"
        case clientX509CertUrl = "client_x509_cert_url"
    }

    /// Load credentials from JSON file
    static func load(from path: String) throws -> ServiceAccountCredentials {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ServiceAccountCredentials.self, from: data)
    }
}
