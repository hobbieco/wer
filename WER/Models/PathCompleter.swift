//
//  PathCompleter.swift
//  WER
//

import Foundation

nonisolated enum PathCompleter {
    /// 입력 중인 경로의 후보 목록. 폴더는 "/"로 끝나고, "~"로 입력하면 "~" 형태로 돌려준다.
    static func suggestions(for input: String, limit: Int = 50) -> [String] {
        guard !input.isEmpty else { return [] }
        let expanded = (input as NSString).expandingTildeInPath
        let directory: String
        let prefix: String
        if input.hasSuffix("/") {
            directory = expanded
            prefix = ""
        } else {
            directory = (expanded as NSString).deletingLastPathComponent
            prefix = (expanded as NSString).lastPathComponent
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }

        // 숨김 파일은 "."으로 입력할 때만 보여준다
        let showHidden = prefix.hasPrefix(".")
        // 대소문자 구분 볼륨이면 입력한 대소문자 그대로 비교한다
        let caseSensitive = (try? URL(fileURLWithPath: directory)
            .resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames) ?? false
        let matchOptions: String.CompareOptions = caseSensitive ? [.anchored] : [.caseInsensitive, .anchored]
        let home = NSHomeDirectory()
        return names
            .filter { name in
                (showHidden || !name.hasPrefix("."))
                    && (prefix.isEmpty || name.range(of: prefix, options: matchOptions) != nil)
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(limit)
            .map { name in
                var path = (directory as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    path += "/"
                }
                if input.hasPrefix("~"), path.hasPrefix(home) {
                    path = "~" + path.dropFirst(home.count)
                }
                return path
            }
    }

    /// 폴더 경로 자신과 하위 폴더 목록. 폴더가 아니면 빈 배열.
    static func folderListing(for path: String) -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath, isDirectory: &isDirectory),
              isDirectory.boolValue else { return [] }
        let folder = path.hasSuffix("/") ? path : path + "/"
        return [folder] + suggestions(for: folder, limit: .max).filter { $0.hasSuffix("/") }
    }

    /// 상위 폴더 경로("/"로 끝남). 루트면 nil. "~"로 시작하면 "~" 형태를 유지한다.
    static func parent(of path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded != "/" else { return nil }
        var parent = (expanded as NSString).deletingLastPathComponent
        if !parent.hasSuffix("/") { parent += "/" }
        let home = NSHomeDirectory() + "/"
        if path.hasPrefix("~"), parent.hasPrefix(home) {
            parent = "~/" + parent.dropFirst(home.count)
        }
        return parent
    }

    /// Tab 자동완성용 공통 접두어. 대소문자가 다르면 거기서 끊어 입력한 대소문자를 바꾸지 않는다.
    static func commonPrefix(of paths: [String]) -> String? {
        guard var result = paths.first else { return nil }
        for path in paths.dropFirst() {
            result = result.commonPrefix(with: path)
        }
        return result
    }
}
