//
//  AppConfig.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor
import Foundation

enum BackendMode: String {
    case live   // Scrape from university website on each request
    case cached // Read preloaded data from Firestore
}

struct AppConfig {
    // Default semester boundaries (used as fallback in queries)
    let defaultFrom: String
    let defaultTo: String
    let defaultInterval: IntervalType

    // Backend mode: live (scraping) or cached (Firestore)
    let backendMode: BackendMode

    // Mock mode (for testing)
    let isMockEnabled: Bool

    // Firestore configuration (used when backendMode == .cached)
    let firestoreProjectId: String?
    let firestoreCredentialsPath: String?

    init(from environment: Environment) {
        // Read from environment variables
        self.defaultFrom = Environment.get("DSW_DEFAULT_FROM") ?? "2025-09-06"
        self.defaultTo = Environment.get("DSW_DEFAULT_TO") ?? "2026-02-08"

        let intervalRaw = Environment.get("DSW_DEFAULT_INTERVAL") ?? "semester"
        switch intervalRaw.lowercased() {
        case "week": self.defaultInterval = .week
        case "month": self.defaultInterval = .month
        case "semester": self.defaultInterval = .semester
        default: self.defaultInterval = .semester
        }

        // Mock mode
        let mockRaw = Environment.get("DSW_ENABLE_MOCK") ?? "0"
        self.isMockEnabled = mockRaw == "1" || mockRaw.lowercased() == "true"

        // Backend mode
        let modeRaw = Environment.get("DSW_BACKEND_MODE") ?? "live"
        self.backendMode = BackendMode(rawValue: modeRaw.lowercased()) ?? .live

        // Firestore config
        self.firestoreProjectId = Environment.get("FIRESTORE_PROJECT_ID")
        self.firestoreCredentialsPath = Environment.get("FIRESTORE_CREDENTIALS_PATH")
    }

    var isFirestoreEnabled: Bool {
        backendMode == .cached && firestoreProjectId != nil && firestoreCredentialsPath != nil
    }
}