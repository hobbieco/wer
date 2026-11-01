//
//  FolderLoader.swift
//  WER
//

import Foundation

/// Select 목록 이름 정렬 방식
nonisolated enum FileSort: String {
    /// 자연 정렬. file2 < file10 (Finder 방식)
    case natural
    /// 사전식 정렬. file10 < file2 (ls 방식)
    case lexicographic

    /// 메뉴에 보여줄 이름
    var title: String {
        switch self {
        case .natural: "Number Order"
        case .lexicographic: "Text Order"
        }
    }

    /// 메뉴에 이름과 함께 보여줄 예시
    var example: String {
        switch self {
        case .natural: "file2, file10"
        case .lexicographic: "file10, file2"
        }
    }

    /// foldersFirst면 폴더를 모두 파일보다 앞에 두고, 각각 이름 순으로 정렬한다
    func sorted(_ items: [FileItem], foldersFirst: Bool = false) -> [FileItem] {
        items.sorted { a, b in
            if foldersFirst, a.isDirectory != b.isDirectory { return a.isDirectory }
            switch self {
            case .natural: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .lexicographic: return a.name < b.name
            }
        }
    }
}

nonisolated enum FolderLoader {
    /// 폴더 내용을 읽어 sort 방식으로 정렬한다. 기본은 Finder 이름순(자연 정렬)
    static func load(_ folder: URL, showHidden: Bool, sort: FileSort = .natural, foldersFirst: Bool = false) throws -> [FileItem] {
        try loadWithSizes(folder, showHidden: showHidden, sort: sort, foldersFirst: foldersFirst).items
    }

    /// load와 같고, 파일 용량(바이트)도 함께 돌려준다. 폴더는 용량이 없다.
    /// 용량은 FileItem에 넣지 않는다 (용량이 바뀌어도 Order의 같은 파일로 알아봐야 한다)
    static func loadWithSizes(
        _ folder: URL, showHidden: Bool, sort: FileSort = .natural, foldersFirst: Bool = false
    ) throws -> (items: [FileItem], sizes: [URL: Int64]) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .fileSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: showHidden ? [] : [.skipsHiddenFiles]
        )
        var sizes: [URL: Int64] = [:]
        let items = urls.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            // .app 같은 패키지는 Finder처럼 파일로 취급 (패키지 용량은 표시하지 않는다)
            let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            let item = FileItem(url: url.standardizedFileURL, isDirectory: isDirectory)
            if !(values?.isDirectory ?? false), let size = values?.fileSize { sizes[item.url] = Int64(size) }
            return item
        }
        return (sort.sorted(items, foldersFirst: foldersFirst), sizes)
    }
}
