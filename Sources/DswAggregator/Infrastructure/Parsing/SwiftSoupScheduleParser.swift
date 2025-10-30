//
//  SwiftSoupScheduleParser.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor
import SwiftSoup
import Foundation

public struct SwiftSoupScheduleParser: ScheduleParser {

    let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    private func log(_ msg: String, _ data: Any? = nil) {
        if let data {
            logger.debug("\(msg) \(String(describing: data))")
        } else {
            logger.debug("\(msg)")
        }
    }

    // unwrap /*DXHTML*/...
    private func unwrapDXHTML(_ raw: String) -> String {
        if let r = raw.range(of: "/*DXHTML*/") {
            return String(raw[r.upperBound...])
        }
        return raw
    }

    private func normalizeGroupDate(_ raw: String) -> String {
        let s1 = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let s2 = s1
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? s1
        return s2.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clean(_ s: String?) -> String? {
        guard var str = s?.replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !str.isEmpty else { return nil }
        return str
    }

    private func allTimes(in tds: [Element]) -> [String] {
        let re = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2}:\d{2})(?!\d)"#)
        var res: [String] = []
        for td in tds {
            let txt = (try? td.text()) ?? ""
            let ns = txt as NSString
            for m in re.matches(in: txt,
                                range: NSRange(location: 0, length: ns.length)) {
                res.append(ns.substring(with: m.range(at: 1)))
            }
        }
        return res
    }

    public func parseSchedule(_ html: String) throws -> [ScheduleEvent] {
        log("parseSchedule.raw.length", html.count)

        let unwrapped = unwrapDXHTML(html)
        if unwrapped.count != html.count {
            log("parseSchedule.dxWrapper", "/*DXHTML*/ trimmed")
        }
        log("parseSchedule.unwrapped.length", unwrapped.count)

        let doc = try SwiftSoup.parse(unwrapped)
        guard let tbl =
            try doc.select("table#gridViewPlanyGrup_DXMainTable").first()
            ?? doc.select("table#gridViewPlanyProwadzacych_DXMainTable").first()
            ?? doc.select("table[id*=_DXMainTable]").first()
        else {
            log("parseSchedule.noTable", "[]")
            return []
        }
        log("parseSchedule.table.id", try tbl.id())

        let rows = try tbl.select("tr.dxgvGroupRow_iOS, tr.dxgvDataRow_iOS").array()
        let typeSet: Set<String> = ["Wyk","Cw","Sem","Labor","Proj","Konw","Prac"]

        var currentGroupDate: String?
        var result: [ScheduleEvent] = []

        for tr in rows {
            let cls = (try? tr.className()) ?? ""

            if cls.contains("dxgvGroupRow") {
                let raw = (try? tr.text()) ?? ""
                currentGroupDate = normalizeGroupDate(raw)
                log("parseSchedule.groupDate", currentGroupDate ?? raw)
                continue
            }
            guard cls.contains("dxgvDataRow") else { continue }

            let tds = try tr.select("> td").array()
            if tds.isEmpty { continue }

            var foundSubject: String?
            var foundRoom: String?
            var foundTeacher: String?
            var foundTeacherId: Int?
            var foundTeacherEmail: String?
            var foundType: String?
            var foundGrading: String?
            var foundTrack: String?
            var foundGroups: String?
            var foundRemarks: String?

            func hrefOf(_ el: Element) -> String? {
                (try? el.select("a").first()?.attr("href")).flatMap { href in
                    href.replacingOccurrences(of: "\u{00A0}", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .nilIfEmpty
                }
            }

            let times = allTimes(in: tds)
            let startTime = times.first
            let endTime   = times.dropFirst().first

            for td in tds {
                let txt = (try? td.text())?
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let href = hrefOf(td) ?? ""

                if href.contains("/Plany/PlanyPrzedmiotow/"),
                   foundSubject == nil {
                    foundSubject = (try? td.text())
                }
                if href.contains("/Plany/PlanySal/"),
                   foundRoom == nil {
                    foundRoom = (try? td.text())
                }
                if href.contains("/Plany/PlanyProwadzacych/"),
                   foundTeacher == nil {
                    foundTeacher = (try? td.text())
                    if let idStr = href.split(separator: "/").last?
                        .split(separator: "?").first,
                       let id = Int(idStr) {
                        foundTeacherId = id
                    }
                    if let cf = try? td.select("a.__cf_email__").first(),
                       let dec = CFEmailDecoder.from(element: cf) {
                        foundTeacherEmail = dec
                    }
                }
                if href.contains("/Plany/PlanyGrup/"),
                   foundGroups == nil {
                    foundGroups = (try? td.text())
                }
                if href.contains("/Plany/PlanyTokow/"),
                   foundTrack == nil {
                    foundTrack = (try? td.text())
                }
                if let t = txt,
                   typeSet.contains(t),
                   foundType == nil {
                    foundType = t
                }
                if let t = txt,
                   foundGrading == nil,
                   (t.contains("Zaliczenie")
                    || t.contains("Egzamin")
                    || t.contains("Nie dotyczy")) {
                    foundGrading = t
                }
                if let t = txt, href.isEmpty {
                    if t == "Brak"
                        || t == "Distance learning"
                        || t == "Sala na zajęcia zdalne"
                        || t == "Zajęcia odwołane"
                        || t.hasPrefix("Uwagi:")
                    {
                        foundRemarks = t
                    }
                }
            }

            // fallback группы (бывают без ссылки)
            if foundGroups == nil {
                if let td = try? tds.first(where: {
                    ((try? $0.text()) ?? "").contains("sem")
                }),
                   let txt = try? td.text(),
                   !txt.isEmpty {
                    foundGroups = txt
                }
            }

            guard
                let dateStr = currentGroupDate,
                let s = startTime, let e = endTime,
                let title = clean(foundSubject)
            else {
                log("parseSchedule.skipRow", "missing essentials")
                continue
            }

            guard let (startISO, endISO) = warsawISO(
                dateStr,
                "\(s)-\(e)"
            ) else {
                log("parseSchedule.skipRow", "warsawISO fail \(dateStr) \(s)-\(e)")
                continue
            }

            let ev = ScheduleEvent(
                title: title,
                teacherName: clean(foundTeacher),
                teacherId: foundTeacherId,
                teacherEmail: clean(foundTeacherEmail),
                room: clean(foundRoom),
                type: clean(foundType),
                grading: clean(foundGrading),
                studyTrack: clean(foundTrack),
                groups: clean(foundGroups),
                remarks: clean(foundRemarks),
                startISO: startISO,
                endISO: endISO
            )
            result.append(ev)
        }

        log("parseSchedule.result.count", result.count)
        return result
    }

    public func parseTeacherInfo(
        _ html: String,
        teacherId: Int
    ) throws -> (name: String?,
                 title: String?,
                 dept: String?,
                 email: String?,
                 phone: String?,
                 aboutHTML: String?) {

        log("teacherInfo.input.length", html.count)

        let doc = try SwiftSoup.parse(html)

        let name = (try? doc.select("h1, h2, .teacher-name, .nazwisko, .imie-nazwisko")
            .first()?.text())?.nilIfEmpty
        let title = (try? doc.select(".teacher-title, .tytul, .stopien, .stopien-naukowy")
            .first()?.text())?.nilIfEmpty
        let dept  = (try? doc.select(".teacher-dept, .katedra, .wydzial, .jednostka")
            .first()?.text())?.nilIfEmpty

        var email: String? = nil
        if let a = try? doc.select("a.__cf_email__").first(),
           let e = CFEmailDecoder.from(element: a) {
            email = e
            log("teacherInfo.email", e)
        } else if let a = try? doc
            .select("a[href*=/cdn-cgi/l/email-protection]")
            .first(),
                  let e = CFEmailDecoder.from(element: a) {
            email = e
            log("teacherInfo.email", e)
        } else if let m = try? doc
            .select("a[href^=mailto]")
            .first()?
            .attr("href"),
           m.hasPrefix("mailto:") {
            email = String(m.dropFirst("mailto:".count))
            log("teacherInfo.email", email ?? "nil")
        } else {
            log("teacherInfo.email", "not found")
        }

        let phone = (try? doc.select("a[href^=tel]").first()?.text())?.nilIfEmpty
        let about = (try? doc.select(".teacher-bio, .opis, .content, .article, .panel-body")
            .first()?.outerHtml())?.nilIfEmpty

        log("teacherInfo.name", name ?? "nil")
        log("teacherInfo.title", title ?? "nil")
        log("teacherInfo.dept", dept ?? "nil")
        log("teacherInfo.phone", phone ?? "nil")
        log("teacherInfo.about.length", about?.count ?? 0)

        return (name, title, dept, email, phone, about)
    }
}
