//
//  FirestoreAuthenticator.swift
//  DswAggregator
//
//  Handles Google Service Account authentication for Firestore
//

import Vapor
import JWTKit
import Foundation

/// Manages OAuth2 authentication for Firestore using Service Account
actor FirestoreAuthenticator {
    private let credentials: ServiceAccountCredentials
    private let client: Client

    private var cachedToken: String?
    private var tokenExpiry: Date?

    init(credentials: ServiceAccountCredentials, client: Client) throws {
        self.credentials = credentials
        self.client = client
    }

    /// Get a valid access token (cached or fresh)
    func getAccessToken() async throws -> String {
        // Return cached token if still valid
        if let token = cachedToken,
           let expiry = tokenExpiry,
           Date() < expiry.addingTimeInterval(-60) {  // refresh 60s before expiry
            return token
        }

        // Generate new token
        let token = try await fetchNewAccessToken()
        return token
    }

    private func fetchNewAccessToken() async throws -> String {
        // 1. Create JWT
        let jwt = try await createJWT()

        // 2. Exchange JWT for access token
        let tokenResponse = try await client.post(URI(string: credentials.tokenUri)) { req in
            try req.content.encode([
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": jwt
            ], as: .urlEncodedForm)
        }

        guard tokenResponse.status == .ok else {
            throw Abort(.badGateway, reason: "Failed to get access token: \(tokenResponse.status)")
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let expiresIn: Int
            let tokenType: String

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
                case tokenType = "token_type"
            }
        }

        let response = try tokenResponse.content.decode(TokenResponse.self)

        // Cache the token
        self.cachedToken = response.accessToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(response.expiresIn))

        return response.accessToken
    }

    private func createJWT() async throws -> String {
        struct JWTPayload: JWTKit.JWTPayload {
            let iss: SubjectClaim  // issuer (service account email)
            let scope: String      // requested scopes
            let aud: AudienceClaim // audience (token URI)
            let exp: ExpirationClaim // expiration (1 hour max)
            let iat: IssuedAtClaim // issued at

            func verify(using algorithm: some JWTAlgorithm) throws {
                try exp.verifyNotExpired()
            }
        }

        let now = Date()
        let expiry = now.addingTimeInterval(3600) // 1 hour

        let payload = JWTPayload(
            iss: SubjectClaim(value: credentials.clientEmail),
            scope: "https://www.googleapis.com/auth/datastore",
            aud: AudienceClaim(value: credentials.tokenUri),
            exp: ExpirationClaim(value: expiry),
            iat: IssuedAtClaim(value: now)
        )

        // Build a local signer collection for this JWT
        let rsaPrivate = try Insecure.RSA.PrivateKey(pem: credentials.privateKey)
        let signers = JWTKeyCollection()
        await signers.add(rsa: rsaPrivate, digestAlgorithm: .sha256, kid: JWKIdentifier(string: credentials.privateKeyId))

        return try await signers.sign(payload, kid: JWKIdentifier(string: credentials.privateKeyId))
    }
}

