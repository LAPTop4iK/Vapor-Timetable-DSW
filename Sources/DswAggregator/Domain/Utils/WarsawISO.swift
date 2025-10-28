//
//  WarsawISO.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//

import Foundation

/// Europe/Warsaw ISO helper (DST handled by system TZ)
func warsawISO(_ plDate: String, _ timeRange: String) -> (String, String)? {
    let cleaned = plDate
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "Data Zajęć:", with: "")
        .replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "—", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let dayMatch = cleaned.range(of: #"\b\d{4}\.\d{2}\.\d{2}\b"#,
                                       options: .regularExpression) else {
        return nil
    }
    let dayStr = String(cleaned[dayMatch]) // "2025.10.18"

    let tr = timeRange
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "—", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let parts = tr.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespaces) }

    guard parts.count == 2 else { return nil }

    let tz = TimeZone(identifier: "Europe/Warsaw")!

    let inFmt = DateFormatter()
    inFmt.dateFormat = "yyyy.MM.dd HH:mm"
    inFmt.locale = Locale(identifier: "pl_PL")
    inFmt.timeZone = tz

    guard let start = inFmt.date(from: "\(dayStr) \(parts[0])"),
          let end0  = inFmt.date(from: "\(dayStr) \(parts[1])") else { return nil }

    let cal = Calendar(identifier: .gregorian)
    let end = (end0 < start)
        ? cal.date(byAdding: .day, value: 1, to: end0)!
        : end0

    let outFmt = ISO8601DateFormatter()
    outFmt.timeZone = tz
    outFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    return (outFmt.string(from: start), outFmt.string(from: end))
}
