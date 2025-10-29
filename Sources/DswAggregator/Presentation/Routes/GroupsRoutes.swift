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
                // Mock mode
                response = MockFactory.makeAggregate(
                    groupId: gid,
                    from: from,
                    to: to,
                    intervalType: interval
                )
            } else if config.backendMode == .cached {
                // Firestore mode: read preloaded data
                guard let firestore = req.di.getFirestoreService(req: req) else {
                    req.logger.error("Firestore service not available in cached mode")
                    throw Abort(.serviceUnavailable, reason: "Firestore service not configured")
                }

                let service = FirestoreAggregationService(firestore: firestore, logger: req.logger)
                response = try await service.aggregate(
                    groupId: gid,
                    from: from,
                    to: to,
                    intervalType: interval
                )
            } else {
                // Live mode: scrape university website
                let service = req.di.makeCachedAggregationService(req: req)
                response = try await service.aggregate(
                    groupId: gid,
                    from: from,
                    to: to,
                    intervalType: interval
                )

                // Log cache stats for live mode
                let stats = await req.di.cacheStats()
                let messageAgg = "CACHE STATS after /aggregate: sched=\(stats.groupScheduleCount), search=\(stats.groupSearchCount), agg=\(stats.aggregateCount), teacher=\(stats.teacherCount), bytes≈\(stats.approxTotalBytes)"
                req.logger.info("\(messageAgg)")
            }

            return response
        }

        routes.get("groups", "search") { req async throws -> [GroupInfo] in
            let config = req.di.appConfig
            let query = (try? req.query.get(String.self, at: "q")) ?? "sem"

            let result: [GroupInfo]

            if config.isMockEnabled {
                // Mock mode
                result = MockFactory.makeGroups()
            } else if config.backendMode == .cached {
                // Firestore mode: read preloaded groups list
                guard let firestore = req.di.getFirestoreService(req: req) else {
                    req.logger.error("Firestore service not available in cached mode")
                    throw Abort(.serviceUnavailable, reason: "Firestore service not configured")
                }

                let service = FirestoreGroupSearchService(firestore: firestore, logger: req.logger)
                result = try await service.search(query: query)
            } else {
                // Live mode: scrape university website
                let service = req.di.makeCachedGroupSearchService(req: req)
                result = try await service.search(query: query)

                // Log cache stats for live mode
                let stats = await req.di.cacheStats()
                let messageSearch = "CACHE STATS after /search: sched=\(stats.groupScheduleCount), search=\(stats.groupSearchCount), agg=\(stats.aggregateCount), teacher=\(stats.teacherCount), bytes≈\(stats.approxTotalBytes)"
                req.logger.info("\(messageSearch)")
            }

            return result
        }

        routes.get("api", "groups", ":groupId", "schedule") { req async throws -> GroupScheduleResponse in
            guard let gid = req.parameters.get("groupId", as: Int.self) else {
                throw Abort(.badRequest)
            }

            let config = req.di.appConfig

            // NEW: This endpoint now returns ONE DAY schedule (today or ?date=YYYY-MM-DD)
            // Get today's date in Warsaw timezone if not specified
            let dateParam = try? req.query.get(String.self, at: "date")
            let warsawTZ = TimeZone(identifier: "Europe/Warsaw")!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = warsawTZ

            let targetDate: String
            if let dateParam = dateParam {
                // Validate date format
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = warsawTZ
                guard dateFormatter.date(from: dateParam) != nil else {
                    throw Abort(.badRequest, reason: "Invalid date format. Use YYYY-MM-DD")
                }
                targetDate = dateParam
            } else {
                // Use today's date in Warsaw timezone
                let now = Date()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = warsawTZ
                targetDate = dateFormatter.string(from: now)
            }

            let response: GroupScheduleResponse

            if config.isMockEnabled {
                // Mock mode: use one day interval
                response = MockFactory.makeGroupScheduleOnly(
                    groupId: gid,
                    from: targetDate,
                    to: targetDate,
                    intervalType: .week
                )
            } else {
                // Check daily cache first
                let cacheKey = DailyScheduleCacheKey(groupId: gid, date: targetDate)
                if let cached = await req.di.cacheStore.getDailySchedule(for: cacheKey) {
                    req.logger.debug("Daily schedule cache HIT for group \(gid), date \(targetDate)")
                    return cached
                }

                req.logger.debug("Daily schedule cache MISS for group \(gid), date \(targetDate)")

                // Live scraping: fetch one day schedule
                let service = req.di.makeCachedGroupScheduleService(req: req)
                response = try await service.fetchSchedule(
                    groupId: gid,
                    from: targetDate,
                    to: targetDate,
                    intervalType: .week // Use week interval for single day
                )

                // Cache the result for 60 seconds
                await req.di.cacheStore.setDailySchedule(response, for: cacheKey)
            }

            let stats = await req.di.cacheStats()
            let messageSched = "CACHE STATS after /schedule: sched=\(stats.groupScheduleCount), search=\(stats.groupSearchCount), agg=\(stats.aggregateCount), teacher=\(stats.teacherCount), daily=\(stats.dailyScheduleCount), bytes≈\(stats.approxTotalBytes)"
            req.logger.info("\(messageSched)")

            return response
        }
    }
}

