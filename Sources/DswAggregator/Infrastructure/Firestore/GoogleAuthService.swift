import Foundation
import Vapor

/// Сервисный аккаунт Google из JSON файла
struct GoogleServiceAccount: Codable, Sendable {
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
}

/// OAuth2 токен для доступа к Google APIs
struct GoogleAccessToken: Sendable {
    let token: String
    let expiresAt: Date
}

/// Сервис для аутентификации в Google Cloud через сервисный аккаунт
actor GoogleAuthService {
    private let serviceAccount: GoogleServiceAccount
    private let client: Client
    private let logger: Logger

    private var cachedToken: GoogleAccessToken?

    init(credentialsPath: String, client: Client, logger: Logger) throws {
        self.client = client
        self.logger = logger

        // Загрузить JSON файл сервисного аккаунта
        let fileURL = URL(fileURLWithPath: credentialsPath)
        let data = try Data(contentsOf: fileURL)
        self.serviceAccount = try JSONDecoder().decode(GoogleServiceAccount.self, from: data)

        logger.info("Loaded Google service account for project: \(serviceAccount.projectId)")
    }

    /// Получить действующий access token (с кешированием)
    func getAccessToken() async throws -> String {
        // Проверить кеш
        if let cached = cachedToken, cached.expiresAt > Date().addingTimeInterval(60) {
            return cached.token
        }

        // Получить новый токен
        let token = try await fetchNewAccessToken()
        cachedToken = token
        return token.token
    }

    /// Получить новый access token через JWT assertion
    private func fetchNewAccessToken() async throws -> GoogleAccessToken {
        // Создать JWT для OAuth2 assertion
        let jwt = try createJWT()

        // Запросить токен
        let response = try await client.post(URI(string: serviceAccount.tokenUri)) { @Sendable req in
            try! req.content.encode([
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": jwt
            ], as: .urlEncodedForm)
        }

        guard response.status == .ok else {
            let body = response.body?.getString(at: 0, length: response.body?.readableBytes ?? 0) ?? "no body"
            logger.error("Failed to get access token: \(response.status) - \(body)")
            throw Abort(.internalServerError, reason: "Failed to authenticate with Google")
        }

        struct TokenResponse: Codable {
            let accessToken: String
            let expiresIn: Int
            let tokenType: String

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
                case tokenType = "token_type"
            }
        }

        let tokenResponse = try response.content.decode(TokenResponse.self)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        logger.info("Obtained new Google access token, expires at: \(expiresAt)")

        return GoogleAccessToken(token: tokenResponse.accessToken, expiresAt: expiresAt)
    }

    /// Создать JWT для OAuth2 assertion
    private func createJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let expiration = now + 3600 // 1 hour

        // JWT Header
        let header: [String: Any] = [
            "alg": "RS256",
            "typ": "JWT"
        ]

        // JWT Payload
        let payload: [String: Any] = [
            "iss": serviceAccount.clientEmail,
            "scope": "https://www.googleapis.com/auth/datastore",
            "aud": serviceAccount.tokenUri,
            "exp": expiration,
            "iat": now
        ]

        // Encode header and payload
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let headerB64 = headerData.base64URLEncodedString()
        let payloadB64 = payloadData.base64URLEncodedString()

        let message = "\(headerB64).\(payloadB64)"

        // Sign with private key
        let signature = try signRS256(message: message, privateKey: serviceAccount.privateKey)
        let signatureB64 = signature.base64URLEncodedString()

        return "\(message).\(signatureB64)"
    }

    /// Подписать сообщение с помощью RS256
    private func signRS256(message: String, privateKey: String) throws -> Data {
        // Импортировать private key
        let key = try importPrivateKey(privateKey)

        // Подписать
        guard let messageData = message.data(using: .utf8) else {
            throw Abort(.internalServerError, reason: "Failed to encode message")
        }

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            messageData as CFData,
            &error
        ) as Data? else {
            if let error = error?.takeRetainedValue() {
                throw Abort(.internalServerError, reason: "Failed to sign JWT: \(error)")
            }
            throw Abort(.internalServerError, reason: "Failed to sign JWT")
        }

        return signature
    }

    /// Импортировать приватный ключ из PEM строки
    private func importPrivateKey(_ pemString: String) throws -> SecKey {
        // Убрать PEM заголовки
        var key = pemString
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let keyData = Data(base64Encoded: key) else {
            throw Abort(.internalServerError, reason: "Failed to decode private key")
        }

        let options: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(
            keyData as CFData,
            options as CFDictionary,
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                throw Abort(.internalServerError, reason: "Failed to create SecKey: \(error)")
            }
            throw Abort(.internalServerError, reason: "Failed to create SecKey")
        }

        return secKey
    }
}

// MARK: - Base64URL Encoding

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
