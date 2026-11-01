//
//  FileItem.swift
//  WER
//

import Foundation

nonisolated struct FileItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
}
