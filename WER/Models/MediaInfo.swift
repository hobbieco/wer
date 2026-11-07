//
//  MediaInfo.swift
//  WER
//

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 이미지·영상·오디오 파일 안의 정보. 파일 정보 레이어와 미리보기 플레이어에 쓴다
nonisolated struct MediaInfo: Equatable, Sendable {
    /// 촬영일. 이미지는 EXIF, 영상은 QuickTime 메타데이터
    var taken: Date?
    /// 보이는 크기(픽셀). 회전 정보를 반영해 세로 사진·영상은 가로·세로가 바뀐다
    var pixelSize: CGSize?
    /// 재생 길이(초). AVFoundation이 재생할 수 있는 파일만
    var duration: Double?
    /// AVFoundation이 재생할 수 있는지. 미리보기 플레이어를 띄우는 기준
    var isPlayable = false
}

nonisolated enum MediaInfoReader {
    enum Kind { case image, audiovisual }

    /// 확장자로 고른 종류. 파일을 열지 않는다
    static func kind(of url: URL) -> Kind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audiovisualContent) { return .audiovisual }
        return nil
    }

    /// 클라우드에만 있고 내려받지 않은 파일 (Synology Drive, MYBOX 등). 열면 내려받기가 시작되어 읽지 않는다
    static func isNotDownloaded(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true, let status = values.ubiquitousItemDownloadingStatus else { return false }
        return status == .notDownloaded
    }

    /// 파일 안의 정보. 이미지·영상·오디오가 아니면 nil
    static func read(_ url: URL) async -> MediaInfo? {
        switch kind(of: url) {
        case .image: image(url)
        case .audiovisual: await audiovisual(url)
        case nil: nil
        }
    }

    /// 이미지 헤더만 읽는다 (픽셀 데이터는 읽지 않는다)
    static func image(_ url: URL) -> MediaInfo {
        var info = MediaInfo()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return info }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let dateText = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        info.taken = dateText.flatMap(exifDate)
        if let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 {
            // EXIF 방향 5~8은 90도 회전이라 가로·세로를 바꾼다
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            info.pixelSize = (5...8).contains(orientation)
                ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }
        return info
    }

    /// EXIF 날짜 "yyyy:MM:dd HH:mm:ss". 시간대가 없어 찍은 곳의 시각 그대로 로컬 시간으로 읽는다
    static func exifDate(_ text: String) -> Date? {
        exifFormatter.date(from: text.trimmingCharacters(in: .whitespaces.union(.controlCharacters)))
    }

    private static let exifFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    static func audiovisual(_ url: URL) async -> MediaInfo {
        var info = MediaInfo()
        let asset = AVURLAsset(url: url)
        guard let (isPlayable, duration) = try? await asset.load(.isPlayable, .duration) else { return info }
        info.isPlayable = isPlayable
        guard isPlayable else { return info }
        if duration.isNumeric, duration.seconds > 0 { info.duration = duration.seconds }
        info.pixelSize = await displaySize(of: asset)
        info.taken = await creationDate(of: asset)
        return info
    }

    /// 회전 정보를 반영한 영상 크기 (세로 영상은 가로·세로가 바뀐다). 영상 트랙이 없으면(오디오) nil
    static func displaySize(of asset: AVURLAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let rotated = size.applying(transform)
        let result = CGSize(width: abs(rotated.width), height: abs(rotated.height))
        return result.width > 0 && result.height > 0 ? result : nil
    }

    /// 촬영일. 아이폰이 쓰는 com.apple.quicktime.creationdate(시간대 포함)를 먼저 보고, 없으면 파일 헤더의 생성 시각(UTC)
    private static func creationDate(of asset: AVURLAsset) async -> Date? {
        if let metadata = try? await asset.load(.metadata),
           let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataCreationDate).first {
            if let date = try? await item.load(.dateValue) { return date }
            // 날짜 형식이 아닌 문자열로 들어 있기도 하다 (예: 2024-05-01T13:22:10+0900)
            if let text = try? await item.load(.stringValue), let date = isoDate(text) { return date }
        }
        guard let item = try? await asset.load(.creationDate) else { return nil }
        return try? await item.load(.dateValue)
    }

    private static func isoDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss.SSSZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

/// 백그라운드 수집에서 파일 하나를 읽은 결과
nonisolated enum MediaReadResult: Equatable, Sendable {
    case loaded(MediaInfo)
    /// 이미지·영상·오디오가 아님
    case notMedia
    /// 클라우드에만 있어 읽지 않음
    case notDownloaded
    /// 제한 시간 안에 읽지 못함 (SMB 응답 없음 등)
    case timedOut

    var info: MediaInfo? {
        if case .loaded(let info) = self { info } else { nil }
    }
}

nonisolated extension MediaInfoReader {
    /// 메인 스레드 밖에서 읽는다. 제한 시간이 지나면 기다리지 않고 timedOut (읽기는 뒤에서 끝난다)
    static func readInBackground(_ url: URL, timeout: Duration = .seconds(10)) async -> MediaReadResult {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task.detached(priority: .utility) {
                if isNotDownloaded(url) { return once.resume(.notDownloaded) }
                let info = await read(url)
                once.resume(info.map(MediaReadResult.loaded) ?? .notMedia)
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                once.resume(.timedOut)
            }
        }
    }

    /// 먼저 온 결과로 한 번만 이어 간다
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<MediaReadResult, Never>?

        init(_ continuation: CheckedContinuation<MediaReadResult, Never>) {
            self.continuation = continuation
        }

        func resume(_ result: MediaReadResult) {
            let continuation = lock.withLock {
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume(returning: result)
        }
    }
}

/// 하나만 고른 항목의 파일 안 정보 (BrowserModel이 선택이 멈추면 읽는다)
nonisolated struct SelectionMedia: Equatable, Sendable {
    let url: URL
    let result: MediaReadResult
}
