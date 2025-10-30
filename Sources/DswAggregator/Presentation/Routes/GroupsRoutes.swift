//
//  GroupsRoutes.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct GroupsRoutes: RouteCollection {

    func boot(routes: any RoutesBuilder) throws {

        routes.get("api", "groups", ":groupId", "aggregate") { req async throws -> AggregateResponse in
            guard let gid = req.parameters.get("groupId", as: Int.self) else {
                throw Abort(.badRequest)
            }

            let config = req.di.appConfig
            let from = (try? req.query.get(String.self, at: "from")) ?? config.defaultFrom
            let to   = (try? req.query.get(String.self, at: "to"))   ?? config.defaultTo
            let tRaw = (try? req.query.get(Int.self, at: "type")) ?? config.defaultInterval.rawValue
            let interval = IntervalType(rawValue: tRaw) ?? config.defaultInterval

            let response: AggregateResponse

            if config.isMockEnabled {
                response = MockFactory.makeAggregate(
                    groupId: gid,
                    from: from,
                    to: to,
                    intervalType: interval
                )
            } else if config.backendMode == .cached {
                // Read from PostgreSQL
                let dbService = req.di.makeDatabaseService(req: req)

                guard let cachedData = try await dbService.getGroupAggregate(groupId: gid) else {
                    throw Abort(.notFound, reason: "Group \(gid) not found in cache")
                }

                response = cachedData
            } else {
                // Live mode: scrape university site
                let service = req.di.makeCachedAggregationService(req: req)
                response = try await service.aggregate(
                    groupId: gid,
                    from: from,
                    to: to,
                    intervalType: interval
                )
            }

            // лог статы кэша
            let stats = await req.di.cacheStats()
            let messageAgg = "CACHE STATS after /aggregate: sched=\(stats.groupScheduleCount), search=\(stats.groupSearchCount), agg=\(stats.aggregateCount), teacher=\(stats.teacherCount), bytes≈\(stats.approxTotalBytes)"
            req.logger.info("\(messageAgg)")

            return response
        }

        routes.get("groups", "search") { req async throws -> [GroupInfo] in
            let config = req.di.appConfig
            let query = (try? req.query.get(String.self, at: "q")) ?? "sem"

            let result: [GroupInfo]

            if config.isMockEnabled {
                result = MockFactory.makeGroups()
            } else if config.backendMode == .cached {
                // Read from PostgreSQL
                let dbService = req.di.makeDatabaseService(req: req)
                let allGroups = try await dbService.getGroupsList()

                // Filter by query (case-insensitive)
                let lowercaseQuery = query.lowercased()
                result = allGroups.filter { group in
                    group.name.lowercased().contains(lowercaseQuery) ||
                    group.code.lowercased().contains(lowercaseQuery) ||
                    group.program.lowercased().contains(lowercaseQuery) ||
                    group.faculty.lowercased().contains(lowercaseQuery)
                }
            } else {
                // Live mode: search university site
                let service = req.di.makeCachedGroupSearchService(req: req)
                result = try await service.search(query: query)
            }

            let stats = await req.di.cacheStats()
            let messageSearch = "CACHE STATS after /search: sched=\(stats.groupScheduleCount), search=\(stats.groupSearchCount), agg=\(stats.aggregateCount), teacher=\(stats.teacherCount), bytes≈\(stats.approxTotalBytes)"
            req.logger.info("\(messageSearch)")

            return result
        }

        routes.get("api", "groups", ":groupId", "schedule") { req async throws -> GroupScheduleResponse in
            guard let gid = req.parameters.get("groupId", as: Int.self) else {
                throw Abort(.badRequest)
            }

            let config = req.di.appConfig
            let from = (try? req.query.get(String.self, at: "from")) ?? config.defaultFrom
            let to   = (try? req.query.get(String.self, at: "to"))   ?? config.defaultTo
            let tRaw = (try? req.query.get(Int.self, at: "type")) ?? config.defaultInterval.rawValue
            let interval = IntervalType(rawValue: tRaw) ?? config.defaultInterval

            let response: GroupScheduleResponse
            if config.isMockEnabled {
                response = MockFactory.makeGroupScheduleOnly(
                    groupId: gid,
                    from: from,
                    to: to,
                    intervalType: interval
                )
            } else {
                let service = req.di.makeCachedGroupScheduleService(req: req)
                response = try await service.fetchSchedule(
                    groupId: gid,
                    from: from,
                    to: to,
                    intervalType: interval
                )
            }

            let stats = await req.di.cacheStats()
            let messageSched = "CACHE STATS after /schedule: sched=\(stats.groupScheduleCount), search=\(stats.groupSearchCount), agg=\(stats.aggregateCount), teacher=\(stats.teacherCount), bytes≈\(stats.approxTotalBytes)"
            req.logger.info("\(messageSched)")

            return response
        }
    }
}

