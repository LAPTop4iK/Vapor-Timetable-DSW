//
//  GroupSearchService.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct GroupSearchService: Sendable {
    let client: any Client
    private let parser = SwiftSoupGroupSearchParser()

    func search(query: String) async throws -> [GroupInfo] {
        let htmlResponse = try await client.post("https://harmonogramy.dsw.edu.pl/Plany/ZnajdzGrupe") { request in
            request.headers.contentType = .urlEncodedForm
            try request.content.encode(["nazwaGrupy": query], as: .urlEncodedForm)
        }

        guard htmlResponse.status == .ok,
              let html = htmlResponse.body?.string
        else {
            throw Abort(
                .badGateway,
                reason: "DSW returned \(htmlResponse.status.code)"
            )
        }

        return try parser.parseGroups(html)
    }
}

struct CachedGroupSearchService: Sendable {
    let base: GroupSearchService
    let cache: InMemoryCacheStore

    func search(query: String) async throws -> [GroupInfo] {
        let key = GroupSearchCacheKey(query: query)

        if let cached = await cache.getGroupSearch(for: key) {
            return cached
        }

        let fresh = try await base.search(query: query)
        await cache.setGroupSearch(fresh, for: key)
        return fresh
    }
}