//
//  DSWClient.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

protocol DSWClient: Sendable {
    func groupScheduleHTML(
        groupId: Int,
        from: String,
        to: String,
        interval: IntervalType
    ) async throws -> String

    func teacherScheduleHTML(
        teacherId: Int,
        from: String,
        to: String,
        interval: IntervalType
    ) async throws -> String

    func teacherInfoHTML(teacherId: Int) async throws -> String
}