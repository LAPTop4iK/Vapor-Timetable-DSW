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
            
            let defaultFlags: [String: JSONValue] = [
                FeatureCases.showAds.rawValue                 : .bool(false),
                FeatureCases.showDebugMenu.rawValue           : .bool(false),
            ]
            
            var flags = defaultFlags
            
            if let flagsJson = Environment.get("DSW_FEATURE_FLAGS_JSON") {
                if let jsonData = flagsJson.data(using: .utf8) {
                    do {
                        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: jsonData)
                        for (key, value) in decoded {
                            flags[key] = value
                        }
                    } catch {
                        // ignore decoding errors, fallback to other environment vars
                    }
                }
            }
            
//            if Environment.get("DSW_FEATURE_FLAGS_JSON") == nil {
//                if let showAdsRaw = Environment.get("DSW_SHOW_ADS") {
//                    let lower = showAdsRaw.lowercased()
//                    let enabled = lower == "1" || lower == "true" || lower == "yes"
//                    flags[FeatureCases.showAds.rawValue] = .bool(enabled)
//                }
//            }
            
            let flagsVersion = Environment.get("DSW_FEATURE_FLAGS_VERSION") ?? "1.0(1)"
            let updatedAtISO = ISO8601DateFormatter().string(from: Date())
            
            req.logger.info("Sent feature flags \(flags)")
            return FeatureFlagsResponse(
                flags: flags,
                version: flagsVersion,
                updatedAt: updatedAtISO
            )
        }

        // /api/feature-parameters
        routes.get("api","feature-parameters") { req async throws -> FeatureParametersResponse in
            let config = req.di.appConfig
            if config.isMockEnabled { return MockFactory.featureParameters() }
            
            let defaultParams: [String: JSONValue] = [
                ParameterCases.premiumTrialDuration.rawValue: .int(60 * 60 * 24)
            ]
            
            var parameters = defaultParams
            
//            if let trialDurationStr = Environment.get("DSW_PREMIUM_TRIAL_DURATION_SECS"), let trialDuration = Int(trialDurationStr) {
//                parameters[ParameterCases.premiumTrialDuration.rawValue] = .int(trialDuration)
//            }
            
            if let paramsJson = Environment.get("DSW_FEATURE_PARAMETERS_JSON") {
                if let jsonData = paramsJson.data(using: .utf8) {
                    do {
                        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: jsonData)
                        for (key, value) in decoded {
                            parameters[key] = value
                        }
                    } catch {
                        // ignore decoding errors
                    }
                }
            }
            
            let paramsVersion = Environment.get("DSW_FEATURE_PARAMS_VERSION") ?? "1.0(1)"
            let updatedAtISO = ISO8601DateFormatter().string(from: Date())
            
            req.logger.info("Sent feature parameters \(parameters)")
            return FeatureParametersResponse(
                parameters: parameters,
                version: paramsVersion,
                updatedAt: updatedAtISO
            )
        }
    }
}

