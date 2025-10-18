import Vapor
import SwiftSoup

// MARK: - Domain Models

struct TrackInfo: Content {
    let trackId: Int
    let title: String
}

struct GroupInfo: Content {
    let groupId: Int
    let code: String
    let name: String
    let tracks: [TrackInfo]
    let program: String
    let faculty: String
}

struct ScheduleEvent: Content, Sendable {
    let title: String

     let teacherName: String?
     let teacherId: Int?
     let teacherEmail: String?

     let room: String?
     let type: String?
     let grading: String?      // Forma zaliczenia
     let studyTrack: String?   // Toki nauki
     let groups: String?       // Grupy  ← НОВОЕ ПОЛЕ
     let remarks: String?      // Uwagi

     let startISO: String
     let endISO: String
}

struct TeacherCard: Content, Sendable {
    var id: Int
    var name: String?
    var title: String?
    var department: String?
    var email: String?
    var phone: String?
    var aboutHTML: String?
    var schedule: [ScheduleEvent]
}

enum IntervalType: Int, Content, Sendable {
    case week = 1, month = 2, semester = 3
}

struct AggregateResponse: Content, Sendable {
    var groupId: Int
    var from: String
    var to: String
    var intervalType: Int
    var groupSchedule: [ScheduleEvent]
    var teachers: [TeacherCard]
    var fetchedAt: String
}

// MARK: - Utilities

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Europe/Warsaw ISO helper (DST учитывается системными календарями)
private func warsawISO(_ plDate: String, _ timeRange: String) -> (String, String)? {
    // очистить мусор и достать именно yyyy.MM.dd
    let cleaned = plDate
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "Data Zajęć:", with: "")
        .replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "—", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let dayMatch = cleaned.range(of: #"\b\d{4}\.\d{2}\.\d{2}\b"#, options: .regularExpression) else {
        return nil
    }
    let dayStr = String(cleaned[dayMatch]) // например "2025.10.18"

    // разрезать диапазон времени
    let tr = timeRange
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "—", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let parts = tr.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }

    guard parts.count == 2 else {
        return nil
    }

    let tz = TimeZone(identifier: "Europe/Warsaw")!

    let inFmt = DateFormatter()
    inFmt.dateFormat = "yyyy.MM.dd HH:mm"
    inFmt.locale = Locale(identifier: "pl_PL")
    inFmt.timeZone = tz

    guard let start = inFmt.date(from: "\(dayStr) \(parts[0])"),
          let end0  = inFmt.date(from: "\(dayStr) \(parts[1])") else {
        return nil
    }

    // если конец «перешёл через полночь», докинем сутки
    let end = (end0 < start) ? Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: end0)! : end0

    let outFmt = ISO8601DateFormatter()
    outFmt.timeZone = tz
    outFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    return (outFmt.string(from: start), outFmt.string(from: end))
}

// MARK: - Cloudflare email decoder

enum CFEmailDecoder {
    static func decode(hex: String) -> String? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count >= 4, h.count % 2 == 0,
              let key = UInt8(h.prefix(2), radix: 16) else { return nil }
        var bytes = [UInt8](); bytes.reserveCapacity((h.count - 2)/2)
        var i = h.index(h.startIndex, offsetBy: 2)
        while i < h.endIndex {
            let j = h.index(i, offsetBy: 2)
            guard j <= h.endIndex, let b = UInt8(h[i..<j], radix: 16) else { break }
            bytes.append(b ^ key)
            i = j
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func from(element el: Element) -> String? {
        if let cf = try? el.attr("data-cfemail"), !cf.isEmpty { return decode(hex: cf) }
        if let href = try? el.attr("href"),
           let r = href.range(of: "/cdn-cgi/l/email-protection#") {
            return decode(hex: String(href[r.upperBound...]))
        }
        if let text = try? el.text(), text.contains("@") { return text }
        return nil
    }
}

// MARK: - Ports (SOLID: Protocols)

protocol DSWClient: Sendable {
    func groupScheduleHTML(
        groupId: Int,
        from: String,
        to: String,
        interval: IntervalType
    ) async throws -> String
    func teacherScheduleHTML(
        teacherId: Int,
        from: String,
        to: String,
        interval: IntervalType
    ) async throws -> String
    func teacherInfoHTML(teacherId: Int) async throws -> String
}

protocol ScheduleParser: Sendable {
    func parseSchedule(_ html: String) throws -> [ScheduleEvent]
    func parseTeacherInfo(_ html: String, teacherId: Int) throws
      -> (name: String?, title: String?, dept: String?, email: String?, phone: String?, aboutHTML: String?)
}

// MARK: - Adapters

/// HTTP-клиент под DSW на базе Vapor
final class VaporDSWClient: @unchecked Sendable, DSWClient {
    private let client: any Client
    init(client: any Client) { self.client = client }

    // Константное состояние окна (из работающего запроса)
    private let custWindowStateJSON = #"{"windowsState":"0:0:-1:0:0:0:-10000:-10000:1:0:0:0"}"#

    // Универсальный POST x-www-form-urlencoded
    private func postForm(_ url: String,
                          fields: [String: String]) async throws -> String {
        let body = formURLEncode(fields)
        let res = try await client.post(URI(string: url)) { req in
            req.headers.replaceOrAdd(name: "User-Agent", value: "Mozilla/5.0 (DSW Aggregator)")
            req.headers.replaceOrAdd(name: .contentType, value: "application/x-www-form-urlencoded; charset=UTF-8")
            req.headers.replaceOrAdd(name: .accept, value: "text/html, */*; q=0.01")
            req.body = .init(string: body)
        }
        guard res.status == .ok,
              let buf = res.body,
              let html = buf.getString(at: 0, length: buf.readableBytes) else {
            throw Abort(.badGateway, reason: "POST \(url) -> \(res.status.code)")
        }
        return html
    }

    // MARK: Schedules

    /// Расписание группы на произвольный интервал
    func groupScheduleHTML(
        groupId: Int,
        from: String,
        to: String,
        interval: IntervalType = .semester
    ) async throws -> String {
        let url = "https://harmonogramy.dsw.edu.pl/Plany/PlanyGrupGridCustom/\(groupId)"
        // обязательные поля по факту:
        let fields: [String: String] = [
            "DXCallbackName": "gridViewPlanyGrup",
            "gridViewPlanyGrup$custwindowState": custWindowStateJSON,
            "DXMVCEditorsValues": "{}", // пусто — достаточно
            "parametry": "\(from);\(to);\(interval.rawValue);\(groupId)",
            "id": "\(groupId)"
        ]
        return try await postForm(url, fields: fields)
    }

    /// Расписание преподавателя на произвольный интервал
    func teacherScheduleHTML(
        teacherId: Int,
        from: String,
        to: String,
        interval: IntervalType = .semester
    ) async throws -> String {
        let url = "https://harmonogramy.dsw.edu.pl/Plany/PlanyProwadzacychGridCustom/\(teacherId)"
        let fields: [String: String] = [
            "DXCallbackName": "gridViewPlanyProwadzacych",
            "gridViewPlanyProwadzacych$custwindowState": custWindowStateJSON,
            "DXMVCEditorsValues": "{}",
            "parametry": "\(from);\(to);\(interval.rawValue);\(teacherId)",
            "id": "\(teacherId)"
        ]
        return try await postForm(url, fields: fields)
    }

    /// Информация о преподавателе (GET без формы)
    func teacherInfoHTML(teacherId: Int) async throws -> String {
        let url = "https://harmonogramy.dsw.edu.pl/Plany/OpisProwadzacego/\(teacherId)"
        let resp = try await client.get(URI(string: url)) { req in
            req.headers.replaceOrAdd(name: "User-Agent", value: "Mozilla/5.0 (DSW Aggregator)")
            req.headers.replaceOrAdd(name: .accept, value: "text/html, */*; q=0.01")
        }
        guard resp.status == .ok,
              let buf = resp.body,
              let html = buf.getString(at: 0, length: buf.readableBytes) else {
            throw Abort(.badGateway, reason: "GET \(url) -> \(resp.status.code)")
        }
        return html
    }

    // MARK: - Helpers
    /// Простой application/x-www-form-urlencoded, корректно кодирует ключи и значения.
    private func formURLEncode(_ dict: [String: String]) -> String {
        dict.map { key, value in
            "\(urlEncode(key))=\(urlEncode(value))"
        }
        .sorted() // порядок не важен, но стабильно
        .joined(separator: "&")
    }

    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

struct SwiftSoupGroupSearchParser {
    func parseGroups(_ html: String) throws -> [GroupInfo] {
        let doc = try SwiftSoup.parse(html)
        guard let table = try doc.select("table[id*=ZnajdzGrupeGrid]").first() else { return [] }

        var result: [GroupInfo] = []

        for tr in try table.select("tr.dxgvDataRow_iOS").array() {
            let tds = try tr.select("> td").array()
            guard tds.count >= 5 else { continue }

            let code = try tds[0].text()
            let groupA = try tds[1].select("a[href*=/Plany/PlanyGrup/]").first()
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

            result.append(GroupInfo(
                groupId: groupId,
                code: code,
                name: name,
                tracks: tracks,
                program: program,
                faculty: faculty
            ))
        }

        return result
    }
}

/// Парсер на SwiftSoup — изолирован в адаптер
struct SwiftSoupScheduleParser: ScheduleParser {

    // MARK: - Logging

    let logger: Logger

    private func log(_ msg: String, _ data: Any? = nil) {
        if let data {
            logger.debug("\(msg) \(String(describing: data))")
        } else {
            logger.debug("\(msg)")
        }
    }

    // MARK: - Helpers


    private func timeIfValid(_ s: String?) -> String? {
        guard var t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        t = t.replacingOccurrences(of: "\u{00A0}", with: " ")
             .replacingOccurrences(of: "–", with: "-")
             .replacingOccurrences(of: "—", with: "-")
        // строгая проверка формата HH:mm (0–23)
        let re = try! NSRegularExpression(pattern: #"^([01]?\d|2[0-3]):[0-5]\d$"#)
        let ns = t as NSString
        return re.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) != nil ? t : nil
    }

    private func unwrapDXHTML(_ raw: String) -> String {
        if let r = raw.range(of: "/*DXHTML*/") {
            return String(raw[r.upperBound...])
        }
        return raw
    }

    /// "Data Zajęć: 2025.10.18 sobota" -> "2025.10.18 sobota"
    private func normalizeGroupDate(_ raw: String) -> String {
        let s1 = raw.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let s2 = s1.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true).last.map { String($0) } ?? s1
        return s2.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeTime(_ s: String?) -> String? {
        guard var out = s?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty else { return nil }
        out = out.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        out = out.replacingOccurrences(of: "\u{00A0}", with: " ")
                 .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return out
    }

    private func textOrNil(_ el: Element?) -> String? {
        guard let t = try? el?.text(), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cellText(_ tds: [Element], _ idx: Int?) -> String? {
        guard let i = idx, let el = tds[safe: i] else { return nil }
        return (try? el.text())?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    // MARK: - Main

    func parseSchedule(_ html: String) throws -> [ScheduleEvent] {
        log(": raw.length: \(html.count)")

        let unwrapped = unwrapDXHTML(html)
        if unwrapped.count != html.count { log(": DX wrapper: found /*DXHTML*/ marker — trimming prelude") }
        log(": unwrapped.length: \(unwrapped.count)")
        if unwrapped.count > 200 { log(": unwrapped.prefix: \(String(unwrapped.prefix(200)))") }

        let doc = try SwiftSoup.parse(unwrapped)

        guard let tbl =
            try doc.select("table#gridViewPlanyGrup_DXMainTable").first()
            ?? doc.select("table#gridViewPlanyProwadzacych_DXMainTable").first()
            ?? doc.select("table[id*=_DXMainTable]").first()
        else {
            log(": no table found -> return []")
            return []
        }
        log(": table.id: \(try tbl.id())")
        log(": table.class: \(try tbl.className())")

        // шапка (для информации, индексы не используем)
        if let headersRow = try tbl.select("tr[id*=DXHeadersRow]").first() {
            let headerCells = try headersRow.select("td").array()
            log(": header visible cells count = \(headerCells.count)")
            var headerMap: [String:Int] = [:]
            func norm(_ s: String) -> String {
                s.replacingOccurrences(of: "\u{00A0}", with: " ")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
                 .lowercased()
            }
            for (i, h) in headerCells.enumerated() {
                let t = norm((try? h.text()) ?? "")
                if t.hasPrefix("czas od") { headerMap["timeStart"] = i }
                else if t.hasPrefix("czas do") { headerMap["timeEnd"] = i }
                else if t.hasPrefix("zajęcia") { headerMap["subject"] = i }
                else if t.hasPrefix("sala") { headerMap["room"] = i }
                else if t.hasPrefix("forma zaj") { headerMap["type"] = i }
                else if t.hasPrefix("grupy") { headerMap["groups"] = i }
                else if t.hasPrefix("prowadzący") { headerMap["teacher"] = i }
                else if t.hasPrefix("forma zaliczenia") { headerMap["grading"] = i }
                else if t.hasPrefix("toki nauki") { headerMap["track"] = i }
                else if t.hasPrefix("uwagi") { headerMap["remarks"] = i }
            }
            log(": header map: \(headerMap)")
        }

        let rows = try tbl.select("tr.dxgvGroupRow_iOS, tr.dxgvDataRow_iOS").array()
        let typeSet: Set<String> = ["Wyk","Cw","Sem","Labor","Proj","Konw","Prac"]

        func clean(_ s: String?) -> String? {
            guard var str = s?.replacingOccurrences(of: "\u{00A0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else { return nil }
            return str
        }
        func cellText(_ el: Element) -> String? { clean((try? el.text()) ?? "") }
        func hrefOf(_ el: Element) -> String? { (try? el.select("a").first()?.attr("href")).flatMap(clean) }

        func allTimes(in tds: [Element]) -> [String] {
            let re = try! NSRegularExpression(pattern: #"(?<!\d)(\d{1,2}:\d{2})(?!\d)"#)
            var res: [String] = []
            for td in tds {
                let txt = (try? td.text()) ?? ""
                let ns = txt as NSString
                for m in re.matches(in: txt, range: NSRange(location: 0, length: ns.length)) {
                    res.append(ns.substring(with: m.range(at: 1)))
                }
            }
            return res
        }

        var currentGroupDate: String?
        var out: [ScheduleEvent] = []

        if let firstData = rows.first(where: { (try? $0.hasClass("dxgvDataRow_iOS")) == true }) {
            let tds = try firstData.select("> td").array()
            log(": first data row td.count (all) = \(tds.count)")
        }

        for tr in rows {
            let cls = (try? tr.className()) ?? ""

            if cls.contains("dxgvGroupRow") {
                let raw = (try? tr.text()) ?? ""
                currentGroupDate = normalizeGroupDate(raw)
                log(": group date -> Data Zajęć: \(currentGroupDate ?? raw)")
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

            let times = allTimes(in: tds)
            let startTime = times.first
            let endTime   = times.dropFirst().first

            for td in tds {
                let txt = cellText(td)
                let href = hrefOf(td) ?? ""

                if href.contains("/Plany/PlanyPrzedmiotow/"), foundSubject == nil {
                    foundSubject = (try? td.text())
                }
                if href.contains("/Plany/PlanySal/"), foundRoom == nil {
                    foundRoom = (try? td.text())
                }
                if href.contains("/Plany/PlanyProwadzacych/"), foundTeacher == nil {
                    foundTeacher = (try? td.text())
                    if let idStr = href.split(separator: "/").last?.split(separator: "?").first,
                       let id = Int(idStr) { foundTeacherId = id }
                    if let cf = try? td.select("a.__cf_email__").first(),
                       let dec = CFEmailDecoder.from(element: cf) {
                        foundTeacherEmail = dec
                    }
                }
                if href.contains("/Plany/PlanyGrup/"), foundGroups == nil {
                    foundGroups = (try? td.text())
                }
                if href.contains("/Plany/PlanyTokow/"), foundTrack == nil {
                    foundTrack = (try? td.text())
                }
                if let t = txt, typeSet.contains(t), foundType == nil {
                    foundType = t
                }
                if let t = txt, foundGrading == nil {
                    if t.contains("Zaliczenie") || t.contains("Egzamin") || t.contains("Nie dotyczy") {
                        foundGrading = t
                    }
                }
                if let t = txt, href.isEmpty {
                    if t == "Brak" || t == "Distance learning" || t == "Sala na zajęcia zdalne" || t.hasPrefix("Uwagi:") {
                        foundRemarks = t
                    }
                }
            }

            // fallback если нет ссылки для групп
            if foundGroups == nil {
                if let td = try? tds.first(where: { ((try? $0.text()) ?? "").contains("sem") }),
                   let txt = try? td.text(), !txt.isEmpty {
                    foundGroups = txt
                }
            }

            guard let dateStr = currentGroupDate,
                  let s = startTime, let e = endTime,
                  let title = clean(foundSubject)
            else {
                log(": skip row — missing essentials after classification")
                continue
            }

            guard let (startISO, endISO) = warsawISO(dateStr, "\(s)-\(e)") else {
                log(": skip row — warsawISO failed for date:\(dateStr) time:\(s)–\(e)")
                continue
            }

            // если аудитории нет — помечаем как "online"
            var roomValue = clean(foundRoom)
            if roomValue == nil || roomValue == "Brak" {
                roomValue = "online"
            }

            let ev = ScheduleEvent(
                title: title,
                teacherName: clean(foundTeacher),
                teacherId: foundTeacherId,
                teacherEmail: clean(foundTeacherEmail),
                room: roomValue,
                type: clean(foundType),
                grading: clean(foundGrading),
                studyTrack: clean(foundTrack),
                groups: clean(foundGroups),
                remarks: clean(foundRemarks),
                startISO: startISO,
                endISO: endISO
            )
            out.append(ev)

            log(": row ok -> \(title) @ \(dateStr) \(s)-\(e) room:\(ev.room ?? "-") type:\(ev.type ?? "-") grading:\(ev.grading ?? "-") track:\(ev.studyTrack ?? "-") groups:\(ev.groups ?? "-") remarks:\(ev.remarks ?? "-")")
        }

        log(": result.count: \(out.count)")
        return out
    }

    private func allTimes(in tds: [Element]) -> [String] {
        let pattern = #"\b([01]?\d|2[0-3]):[0-5]\d\b"#
        return tds.compactMap { try? $0.text() }
            .flatMap { text -> [String] in
                let s = text.replacingOccurrences(of: "\u{00A0}", with: " ")
                do {
                    let re = try NSRegularExpression(pattern: pattern, options: [])
                    let ns = s as NSString
                    return re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
                        .map { ns.substring(with: $0.range) }
                } catch { return [] }
            }
    }

    private func findSubject(in row: Element) -> String? {
        // 1) приоритет — ссылка на карточку предмета
        if let a = try? row.select("a[href*=/Plany/OpisPrzedmiotu]").first(),
           let t = try? a.text(), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2) fallback — «самая содержательная» ячейка, но с фильтрами-предохранителями
        let banRegex = try! NSRegularExpression(pattern:
            #"(?:\bN\s*lic\.\b)|(?:\b20\d{2}/20\d{2}\b)|\bZima\b|\bLetnia\b|\bstudia\b|\bkierunek\b|\bspecjaln"#,
            options: [.caseInsensitive])

        let timeRegex = try! NSRegularExpression(pattern: #"\b([01]?\d|2[0-3]):[0-5]\d\b"#)

        let candidates = ((try? row.select("td").array()) ?? [])
            .compactMap { try? $0.text().replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            // убрать строки, где основное — время
            .filter { s in timeRegex.numberOfMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) <= 1 }
            // убрать «служебные» и строки с маркерами учебной программы
            .filter { s in
                let ns = s as NSString
                return banRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) == nil
                    && !s.lowercased().contains("media kreatywne")
                    && !s.lowercased().contains("lic.")
            }
            .sorted { $0.count > $1.count }

        return candidates.first
    }

    func parseTeacherInfo(_ html: String, teacherId: Int) throws
      -> (name: String?, title: String?, dept: String?, email: String?, phone: String?, aboutHTML: String?) {

        log("teacherInfo.input.length", html.count)
        let doc = try SwiftSoup.parse(html)

        let name = (try? doc.select("h1, h2, .teacher-name, .nazwisko, .imie-nazwisko").first()?.text())?.nilIfEmpty
        let title = (try? doc.select(".teacher-title, .tytul, .stopien, .stopien-naukowy").first()?.text())?.nilIfEmpty
        let dept  = (try? doc.select(".teacher-dept, .katedra, .wydzial, .jednostka").first()?.text())?.nilIfEmpty

        var email: String? = nil
        let cfCount = (try? doc.select("a.__cf_email__").size()) ?? 0
        log("teacherInfo.cfEmail.count", cfCount)

        if let a = try? doc.select("a.__cf_email__").first(), let e = CFEmailDecoder.from(element: a) {
            email = e
            log("teacherInfo.email", e)
        } else if let a = try? doc.select("a[href*=/cdn-cgi/l/email-protection]").first(),
                  let e = CFEmailDecoder.from(element: a) {
            email = e
            log("teacherInfo.email", e)
        } else if let m = try? doc.select("a[href^=mailto]").first()?.attr("href"), m.hasPrefix("mailto:") {
            email = String(m.dropFirst("mailto:".count))
            log("teacherInfo.email", email ?? "nil")
        } else {
            log("teacherInfo.email", "not found")
        }

        let phone = (try? doc.select("a[href^=tel]").first()?.text())?.nilIfEmpty
        let about = (try? doc.select(".teacher-bio, .opis, .content, .article, .panel-body").first()?.outerHtml())?.nilIfEmpty

        log("teacherInfo.name", name ?? "nil")
        log("teacherInfo.title", title ?? "nil")
        log("teacherInfo.dept", dept ?? "nil")
        log("teacherInfo.phone", phone ?? "nil")
        log("teacherInfo.about.length", about?.count ?? 0)

        return (name, title, dept, email, phone, about)
    }
}

// MARK: - Safe subscript for SwiftSoup Elements
private extension Array {
    subscript(safe idx: Int) -> Element? {
        (0..<count).contains(idx) ? self[idx] : nil
    }
}

// MARK: - Application Service (use-case)

/// Аггрегирует данные: расписание группы + все преподаватели с инфой и расписанием.
/// Ограничение параллелизма — *батчами* через TaskGroup.
struct AggregationService: Sendable {
    let client: any DSWClient
    let parser: any ScheduleParser
    let batchSize: Int

    init(client: any DSWClient, parser: any ScheduleParser, batchSize: Int = 6) {
        self.client = client
        self.parser = parser
        self.batchSize = max(1, batchSize)
    }

    func aggregate(
        groupId: Int,
        from: String,
        to: String,
        intervalType: IntervalType
    ) async throws -> AggregateResponse {

        // 1) расписание группы
        let gHTML = try await client.groupScheduleHTML(groupId: groupId, from: from, to: to, interval: intervalType)
        let groupEvents = try parser.parseSchedule(gHTML)

        // 2) добываем уникальных преподавателей из расписания
        struct LiteT: Hashable, Sendable { let id: Int?; let name: String? }
        var set = Set<LiteT>()
        for e in groupEvents { set.insert(LiteT(id: e.teacherId, name: e.teacherName)) }
        var teachers = Array(set)
        teachers.sort { ($0.name ?? "") < ($1.name ?? "") }

        // 3) по преподавателям — батчами
        var cards = Array(
            repeating: TeacherCard(id: 0, name: nil, title: nil, department: nil, email: nil, phone: nil, aboutHTML: nil, schedule: []),
            count: teachers.count
        )

        for batchStart in stride(from: 0, to: teachers.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, teachers.count)
            let slice = teachers[batchStart..<batchEnd]

            try await withThrowingTaskGroup(of: (Int, TeacherCard).self) { tg in
                for (offset, t) in slice.enumerated() {
                    let index = batchStart + offset
                    tg.addTask { @Sendable in
                        do {
                            let tid = t.id
                            var name = t.name
                            var title: String?; var dept: String?; var email: String?; var phone: String?; var about: String?
                            var sched: [ScheduleEvent] = []

                            if let tid = tid {
                                let infoHTML = try await client.teacherInfoHTML(teacherId: tid)
                                let info = try parser.parseTeacherInfo(infoHTML, teacherId: tid)
                                name = name ?? info.name
                                title = info.title; dept = info.dept; email = info.email; phone = info.phone; about = info.aboutHTML

                                let schHTML = try await client.teacherScheduleHTML(teacherId: tid, from: from, to: to, interval: intervalType)
                                sched = try parser.parseSchedule(schHTML)
                            }

                            let card = TeacherCard(
                                id: tid ?? 0,
                                name: name,
                                title: title,
                                department: dept,
                                email: email,
                                phone: phone,
                                aboutHTML: about,
                                schedule: sched
                            )
                            return (index, card)
                        } catch {
                            let fallback = TeacherCard(
                                id: t.id ?? 0,
                                name: t.name,
                                title: nil, department: nil, email: nil, phone: nil, aboutHTML: nil, schedule: []
                            )
                            return (index, fallback)
                        }
                    }
                }
                for try await (i, card) in tg { cards[i] = card }
            }
        }

        let isoNow = ISO8601DateFormatter().string(from: Date())
        return AggregateResponse(
            groupId: groupId,
            from: from,
            to: to,
            intervalType: intervalType.rawValue,
            groupSchedule: groupEvents,
            teachers: cards,
            fetchedAt: isoNow
        )
    }
}

// MARK: - Routes (composition root)

public func routes(_ app: Application) throws {

    // GET /api/groups/:groupId/aggregate?from=YYYY-MM-DD&to=YYYY-MM-DD&type=1|2|3
    app.get("api", "groups", ":groupId", "aggregate") { req async throws -> AggregateResponse in
        guard let gid = req.parameters.get("groupId", as: Int.self) else { throw Abort(.badRequest) }

        // Параметры периода (по умолчанию семестр)
        let from = (try? req.query.get(String.self, at: "from")) ?? "2025-09-06"
        let to   = (try? req.query.get(String.self, at: "to"))   ?? "2026-02-08"
        let tRaw = (try? req.query.get(Int.self, at: "type")) ?? 3
        let interval = IntervalType(rawValue: tRaw) ?? .semester

        // DI: подставляем конкретные адаптеры
        let client = VaporDSWClient(client: req.client)
        let parser = SwiftSoupScheduleParser(logger: req.logger)
        let service = AggregationService(client: client, parser: parser, batchSize: 6)

        return try await service.aggregate(groupId: gid, from: from, to: to, intervalType: interval)
    }

    app.get("groups", "search") { req async throws -> [GroupInfo] in
            // минимальный POST как по твоему curl
            let htmlResponse = try await req.client.post("https://harmonogramy.dsw.edu.pl/Plany/ZnajdzGrupe") { request in
                request.headers.contentType = .urlEncodedForm
                try request.content.encode(["nazwaGrupy": "sem"], as: .urlEncodedForm)
            }

            guard htmlResponse.status == .ok, let html = htmlResponse.body?.string else {
                throw Abort(.badGateway, reason: "DSW returned \(htmlResponse.status.code)")
            }

            let parsed = try SwiftSoupGroupSearchParser().parseGroups(html)
            req.logger.info("Fetched \(parsed.count) groups")
            return parsed
        }
}


extension ByteBuffer {
    var string: String? { getString(at: readerIndex, length: readableBytes) }
}
