//
//  RouteBuilder.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//

import Vapor

public func routes(_ app: Application) throws {
    try app.register(collection: GroupsRoutes())
    try app.register(collection: FeatureFlagsRoutes())
}
