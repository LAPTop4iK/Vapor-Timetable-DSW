//
//  CacheStats.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Foundation

public struct CacheStats: Sendable {
    public let groupScheduleCount: Int
    public let groupSearchCount: Int
    public let aggregateCount: Int
    public let teacherCount: Int
    public let dailyScheduleCount: Int

    /// примерная оценка занимаемой памяти в байтах
    public let approxTotalBytes: Int
}