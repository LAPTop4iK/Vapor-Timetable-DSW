//
//  AppConfig.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor
import Foundation

struct AppConfig {
    // дефолтные границы семестра (используются как fallback в query)
    // можно вынести в env потом
    let defaultFrom = "2025-09-06"
    let defaultTo   = "2026-02-08"
    let defaultInterval: IntervalType = .semester

    // флаги
    let isMockEnabled: Bool = false
}