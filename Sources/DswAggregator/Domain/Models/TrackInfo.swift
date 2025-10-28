//
//  TrackInfo.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct TrackInfo: Content {
    let trackId: Int
    let title: String
}