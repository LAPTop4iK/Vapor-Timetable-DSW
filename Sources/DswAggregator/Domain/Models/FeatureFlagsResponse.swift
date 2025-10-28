//
//  FeatureFlagsResponse.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct FeatureFlagsResponse: Content, Sendable {
    let flags: [String: JSONValue]
    let version: String
    let updatedAt: String
}

struct FeatureParametersResponse: Content, Sendable {
    let parameters: [String: JSONValue]
    let version: String
    let updatedAt: String
}

enum FeatureCases: String {
    case showSubjectsTab = "show_subjects_tab"
    case showTeachersTab = "show_teachers_tab"
    case enableAnalytics = "enable_analytics"
    case showAds = "show_ads"
    case enablePushNotifications = "enable_push_notifications"
    case darkModeOnly = "dark_mode_only"
    case showDebugMenu = "show_debug_menu"
}

enum ParameterCases: String {
    case premiumTrialDuration = "premium_trial_duration"
}