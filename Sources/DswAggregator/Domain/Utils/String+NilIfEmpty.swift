//
//  String+NilIfEmpty.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//

import Foundation

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
