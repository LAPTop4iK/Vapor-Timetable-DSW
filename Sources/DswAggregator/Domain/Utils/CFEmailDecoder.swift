//
//  CFEmailDecoder.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//

import Foundation
import SwiftSoup

enum CFEmailDecoder {
    static func decode(hex: String) -> String? {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count >= 4, h.count % 2 == 0,
              let key = UInt8(h.prefix(2), radix: 16)
        else { return nil }

        var bytes = [UInt8]()
        bytes.reserveCapacity((h.count - 2)/2)

        var i = h.index(h.startIndex, offsetBy: 2)
        while i < h.endIndex {
            let j = h.index(i, offsetBy: 2)
            guard j <= h.endIndex,
                  let b = UInt8(h[i..<j], radix: 16)
            else { break }
            bytes.append(b ^ key)
            i = j
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    static func from(element el: Element) -> String? {
        if let cf = try? el.attr("data-cfemail"), !cf.isEmpty {
            return decode(hex: cf)
        }
        if let href = try? el.attr("href"),
           let r = href.range(of: "/cdn-cgi/l/email-protection#") {
            return decode(hex: String(href[r.upperBound...]))
        }
        if let text = try? el.text(), text.contains("@") {
            return text
        }
        return nil
    }
}
