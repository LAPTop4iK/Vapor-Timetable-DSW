//
//  IntervalType.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//


import Vapor

public enum IntervalType: Int, Content, Sendable {
    case week = 1
    case month = 2
    case semester = 3
}