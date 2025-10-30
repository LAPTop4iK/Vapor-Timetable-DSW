//
//  GroupInfo.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

public struct GroupInfo: Content {
    public let groupId: Int
    public let code: String
    public let name: String
    public let tracks: [TrackInfo]
    public let program: String
    public let faculty: String

    public init(
        groupId: Int,
        code: String,
        name: String,
        tracks: [TrackInfo],
        program: String,
        faculty: String
    ) {
        self.groupId = groupId
        self.code = code
        self.name = name
        self.tracks = tracks
        self.program = program
        self.faculty = faculty
    }
}