//
//  FileNameComparer.swift
//  WER
//

import Foundation

/// 볼륨 포맷에 맞춰 파일 이름이 같은지 비교한다.
nonisolated enum FileNameComparer {
    /// 대소문자 구분 볼륨인지. 폴더가 아직 없으면 가장 가까운 상위 폴더의 볼륨으로 판단한다.
    static func isCaseSensitive(at url: URL) -> Bool {
        var current = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: current.path), current.path != "/" {
            current = current.deletingLastPathComponent()
        }
        return (try? current.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames) ?? false
    }

    /// 비교용 키. 한글 자모 분리(NFD) 차이는 항상 무시하고, 대소문자 비구분 볼륨이면 대소문자도 무시한다.
    static func key(_ name: String, caseSensitive: Bool) -> String {
        let normalized = name.precomposedStringWithCanonicalMapping
        return caseSensitive ? normalized : normalized.lowercased()
    }
}
