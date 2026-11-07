//
//  FileInfoView.swift
//  WER
//

import SwiftUI
import UniformTypeIdentifiers

/// 파일 정보 레이어에 보여줄 선택 항목 하나
nonisolated struct FileInfoEntry: Equatable, Hashable {
    let url: URL
    let isDirectory: Bool
    /// 현재 폴더(Select 목록)의 항목인지. 아니면 Order에 남은 다른 폴더 파일이라 용량을 따로 읽는다
    let isInFolder: Bool
    /// 현재 폴더 파일의 용량. 폴더·패키지는 없다
    let size: Int64?
}

/// 파일 정보. 하나면 날짜·형식·크기·길이, 여러 개면 개수와 파일 합산 용량.
/// 미리보기 위에 겹쳐 띄우거나(⌘I), 미리보기를 끈 자리에 그대로 보여준다
struct FileInfoView: View {
    enum Style { case overlay, inline }

    let entries: [FileInfoEntry]
    /// 등록일·수정일 (BrowserModel.dates(of:))
    let dates: (URL) -> FileDates
    /// 하나만 고른 항목의 파일 안 정보. 아직 읽지 않았으면 nil
    var media: MediaReadResult?
    var style = Style.overlay

    var body: some View {
        let content = Group {
            if entries.count == 1, let entry = entries.first {
                SingleFileInfo(entry: entry, dates: dates(entry.url), media: media)
            } else {
                MultipleFileInfo(entries: entries)
            }
        }
        .font(.callout)
        .monospacedDigit()
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        switch style {
        case .overlay:
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .padding(6)
                // 아래 미리보기의 클릭·재생을 막지 않는다
                .allowsHitTesting(false)
        case .inline:
            content
        }
    }

    /// 날짜 표시. 이름 조각 형식과 같은 방식(시스템 언어와 관계없음)
    static func format(_ date: Date?) -> String {
        date.map { DateFormat.string(from: $0, format: "yyyy-MM-dd HH:mm:ss") } ?? "—"
    }

    static func format(bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// "1 file", "2 files"
    static func count(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }
}

private struct SingleFileInfo: View {
    let entry: FileInfoEntry
    let dates: FileDates
    /// nil이면 아직 읽는 중
    let media: MediaReadResult?

    /// 다른 폴더 파일의 용량
    @State private var size: Int64?

    private var isMedia: Bool { !entry.isDirectory && MediaInfoReader.kind(of: entry.url) != nil }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
            row("Created", FileInfoView.format(dates.created))
            row("Modified", FileInfoView.format(dates.modified))
            if isMedia {
                row("Taken", takenText)
            }
            if !entry.isDirectory {
                row("Type", typeText)
            }
            if !entry.isDirectory, let sizeText {
                row("Size", sizeText)
            }
            if let duration = media?.info?.duration {
                row("Duration", Self.format(duration: duration))
            }
        }
        .task(id: entry) { await load() }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    /// MIME 형식 (예: image/jpeg). 확장자로 정해지고, MIME 형식이 없으면 종류 이름 (예: Alias)
    private var typeText: String {
        guard let type = (try? entry.url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: entry.url.pathExtension) else { return "—" }
        return type.preferredMIMEType ?? type.localizedDescription ?? "—"
    }

    private var takenText: String {
        switch media {
        case nil: "…"
        case .notDownloaded: "Not downloaded"
        case let result?: FileInfoView.format(result.info?.taken)
        }
    }

    /// "3024 × 4032 · 2.4 MB". 패키지처럼 용량이 없으면 크기만
    private var sizeText: String? {
        var parts: [String] = []
        if let pixels = media?.info?.pixelSize {
            parts.append("\(Int(pixels.width)) × \(Int(pixels.height))")
        }
        if let size = entry.size ?? size { parts.append(FileInfoView.format(bytes: size)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func load() async {
        let url = entry.url
        // 다른 폴더 파일은 용량을 따로 읽는다
        if !entry.isDirectory, entry.size == nil, !entry.isInFolder {
            size = await Task.detached {
                (try? url.resourceValues(forKeys: [.fileSizeKey, .isPackageKey])).flatMap { values in
                    values.isPackage == true ? nil : values.fileSize.map(Int64.init)
                }
            }.value
        }
    }

    static func format(duration seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// 여러 개 선택. 폴더만이면 폴더 수, 섞이면 폴더·파일 수, 파일만이면 파일 수와 합산 용량.
/// 미리보기의 여러 개 선택 문구도 같은 뷰를 쓴다
struct MultipleFileInfo: View {
    let entries: [FileInfoEntry]

    private enum Total: Equatable {
        case calculating
        /// 패키지가 섞여 합산하지 않는다
        case none
        case bytes(Int64, unknown: Int)
    }

    @State private var total: Total = .calculating

    private var folderCount: Int { entries.filter(\.isDirectory).count }
    private var fileCount: Int { entries.count - folderCount }

    var body: some View {
        Text(text)
            .task(id: entries) { await calculate() }
    }

    private var text: String {
        let folders = FileInfoView.count(folderCount, "folder")
        let files = FileInfoView.count(fileCount, "file")
        if fileCount == 0 { return folders }
        if folderCount > 0 { return "\(folders), \(files)" }
        switch total {
        case .calculating: return "\(files) · Calculating…"
        case .none: return files
        case .bytes(let bytes, 0): return "\(files) · \(FileInfoView.format(bytes: bytes))"
        case .bytes(let bytes, let unknown): return "\(files) · \(FileInfoView.format(bytes: bytes))+ (\(unknown) unknown)"
        }
    }

    private func calculate() async {
        guard folderCount == 0 else { return }
        var bytes: Int64 = 0
        var outside: [URL] = []
        for entry in entries {
            if let size = entry.size {
                bytes += size
            } else if entry.isInFolder {
                // 현재 폴더에서 용량이 없는 파일은 패키지
                total = .none
                return
            } else {
                outside.append(entry.url)
            }
        }
        if outside.isEmpty {
            total = .bytes(bytes, unknown: 0)
            return
        }
        total = .calculating
        let result = await Task.detached { () -> (bytes: Int64, unknown: Int, hasPackage: Bool) in
            var bytes: Int64 = 0
            var unknown = 0
            for url in outside {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isPackageKey])
                if values?.isPackage == true { return (0, 0, true) }
                if let size = values?.fileSize { bytes += Int64(size) } else { unknown += 1 }
            }
            return (bytes, unknown, false)
        }.value
        guard !Task.isCancelled else { return }
        total = result.hasPackage ? .none : .bytes(bytes + result.bytes, unknown: result.unknown)
    }
}
