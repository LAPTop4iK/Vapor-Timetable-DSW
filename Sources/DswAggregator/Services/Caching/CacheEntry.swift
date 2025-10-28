//
//  CacheEntry.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Foundation

struct CacheEntry<Value: Sendable>: Sendable {
    let value: Value
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}
