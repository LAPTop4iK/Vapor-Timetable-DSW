//
//  AppConfig.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor
import Foundation

enum BackendMode: String {
    case live = "live"      // scrape university site on request
    case cached = "cached"  // read from PostgreSQL preloaded data
}

struct AppConfig {
    // дефолтные границы семестра (используются как fallback в query)
    let defaultFrom: String
    let defaultTo: String
    let defaultInterval: IntervalType

    // флаги
    let isMockEnabled: Bool
    let backendMode: BackendMode

    // Database config
    let databaseURL: String?

    init() {
        // Read from environment
        self.defaultFrom = Environment.get("DSW_DEFAULT_FROM") ?? "2025-09-06"
        self.defaultTo = Environment.get("DSW_DEFAULT_TO") ?? "2026-02-08"

        if let intervalStr = Environment.get("DSW_DEFAULT_INTERVAL") {
            switch intervalStr.lowercased() {
            case "week":
                self.defaultInterval = .week
            case "month":
                self.defaultInterval = .month
            case "semester":
                self.defaultInterval = .semester
            default:
                self.defaultInterval = .semester
            }
        } else {
            self.defaultInterval = .semester
        }

        self.isMockEnabled = Environment.get("DSW_ENABLE_MOCK") == "1"

        if let modeStr = Environment.get("DSW_BACKEND_MODE") {
            self.backendMode = BackendMode(rawValue: modeStr.lowercased()) ?? .live
        } else {
            self.backendMode = .live
        }

        self.databaseURL = Environment.get("DATABASE_URL")
    }
}