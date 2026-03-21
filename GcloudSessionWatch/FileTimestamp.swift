//
//  FileTimestamp.swift
//  GcloudSessionWatch
//
//  Created by Youngho Chaa on 21/03/2026.
//
import Foundation

protocol FileTimestampProvider {
    func modificationDate(at path: String) -> Date?
}

struct LiveFileTimestampProvider: FileTimestampProvider {
    func modificationDate(at path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
