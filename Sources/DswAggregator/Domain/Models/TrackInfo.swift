//
//  TrackInfo.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

public struct TrackInfo: Content {
    public let trackId: Int
    public let title: String

    public init(trackId: Int, title: String) {
        self.trackId = trackId
        self.title = title
    }
}