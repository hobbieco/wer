//
//  PathBar.swift
//  WER
//

import SwiftUI

/// Finder 경로 막대처럼 각 단계를 클릭하면 해당 폴더로 이동한다.
struct PathBar: View {
    let url: URL
    let onSelect: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(Self.components(of: url).enumerated()), id: \.element) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button { onSelect(component) } label: {
                        Label {
                            Text(FileManager.default.displayName(atPath: component.path))
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: component.path))
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 볼륨 루트부터 현재 폴더까지의 경로
    static func components(of url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL
        while true {
            result.insert(current, at: 0)
            let isVolume = (try? current.resourceValues(forKeys: [.isVolumeKey]).isVolume) ?? false
            if isVolume || current.path == "/" { break }
            current = current.deletingLastPathComponent()
        }
        return result
    }
}
