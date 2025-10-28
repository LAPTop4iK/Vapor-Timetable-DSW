//
//  ByteBuffer+String.swift
//  DswAggregator
//
//  Created by Mikita Laptsionak on 27/10/2025.
//

import Vapor

extension ByteBuffer {
    var string: String? {
        getString(at: readerIndex, length: readableBytes)
    }
}
