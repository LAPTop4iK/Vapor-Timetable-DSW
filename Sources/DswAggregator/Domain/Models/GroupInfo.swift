//
//  GroupInfo.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

struct GroupInfo: Content {
    let groupId: Int
    let code: String
    let name: String
    let tracks: [TrackInfo]
    let program: String
    let faculty: String
}