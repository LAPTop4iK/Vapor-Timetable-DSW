//
//  FeatureFlagsRoutes.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct FeatureFlagsRoutes: RouteCollection {

    func boot(routes: any RoutesBuilder) throws {

        // /api/feature-flags
        routes.get("api","feature-flags") { req async throws -> FeatureFlagsResponse in
            let config = req.di.appConfig
            if config.isMockEnabled { return MockFactory.featureFlags() }

            let flags: [String: JSONValue] = [
                FeatureCases.showSubjectsTab.rawValue        : .bool(false),
                FeatureCases.showTeachersTab.rawValue        : .bool(false),
                FeatureCases.enableAnalytics.rawValue        : .bool(false),
                FeatureCases.showAds.rawValue                : .bool(true),
                FeatureCases.enablePushNotifications.rawValue: .bool(false),
                FeatureCases.darkModeOnly.rawValue           : .bool(false),
                FeatureCases.showDebugMenu.rawValue          : .bool(false),
            ]

            req.logger.info("Sent feature flags \(flags)")
            return FeatureFlagsResponse(
                flags: flags,
                version: "1.0(1)",
                updatedAt: Date.timeIntervalSinceReferenceDate.description
            )
        }

        // /api/feature-parameters
        routes.get("api","feature-parameters") { req async throws -> FeatureParametersResponse in
            let config = req.di.appConfig
            if config.isMockEnabled { return MockFactory.featureParameters() }

            let parameters: [String: JSONValue] = [
                ParameterCases.premiumTrialDuration.rawValue: .int(60 * 60 * 24)
            ]

            req.logger.info("Sent feature parameters \(parameters)")
            return FeatureParametersResponse(
                parameters: parameters,
                version: "1.0(1)",
                updatedAt: Date.timeIntervalSinceReferenceDate.description
            )
        }
    }
}
