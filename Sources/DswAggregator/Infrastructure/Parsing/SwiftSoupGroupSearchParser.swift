//
//  SwiftSoupGroupSearchParser.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor
import SwiftSoup

struct SwiftSoupGroupSearchParser {

    func parseGroups(_ html: String) throws -> [GroupInfo] {
        let doc = try SwiftSoup.parse(html)
        guard let table = try doc
            .select("table[id*=ZnajdzGrupeGrid]")
            .first()
        else { return [] }

        var result: [GroupInfo] = []

        for tr in try table.select("tr.dxgvDataRow_iOS").array() {
            let tds = try tr.select("> td").array()
            guard tds.count >= 5 else { continue }

            let code = try tds[0].text()

            let groupA = try tds[1]
                .select("a[href*=/Plany/PlanyGrup/]")
                .first()
            let name = try groupA?.text() ?? ""
            let groupHref = try groupA?.attr("href") ?? ""
            let groupId = Int(groupHref.split(separator: "/").last ?? "") ?? -1

            var tracks: [TrackInfo] = []
            for a in try tds[2].select("a[href*=/Plany/PlanyTokow/]").array() {
                let href = try a.attr("href")
                let id = Int(href.split(separator: "/").last ?? "") ?? -1
                tracks.append(TrackInfo(trackId: id, title: try a.text()))
            }

            let program = try tds[3].text()
            let faculty = try tds[4].text()

            result.append(
                GroupInfo(
                    groupId: groupId,
                    code: code,
                    name: name,
                    tracks: tracks,
                    program: program,
                    faculty: faculty
                )
            )
        }

        return result
    }
}