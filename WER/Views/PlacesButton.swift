//
//  PlacesButton.swift
//  WER
//

import AppKit
import SwiftUI

/// Finder 사이드바처럼 자주 가는 곳 (즐겨찾기, 클라우드, 볼륨, 최근 폴더). 사이드바 파일은 공개되지 않은 형식이라 읽지 않고 같은 구성을 직접 만든다.
/// 열 수 있는 폴더만 담고(AirDrop·태그·최근 항목 등 제외), 메뉴를 열 때마다 새로 만들어 볼륨 연결 상태를 반영한다
enum Places {
    struct Section {
        let title: String
        let urls: [URL]
    }

    private static let recentKey = "places.recentFolders"
    private static let recentLimit = 5

    static func sections(current: URL) -> [Section] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let userFolders: [FileManager.SearchPathDirectory] = [
            .desktopDirectory, .documentDirectory, .downloadsDirectory,
            .picturesDirectory, .moviesDirectory, .musicDirectory,
        ]
        let favorites = [home]
            + userFolders.compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
            + [URL(fileURLWithPath: "/Applications")]
        // iCloud Drive와, 클라우드 저장소 앱(Synology Drive, Dropbox, Google Drive, OneDrive 등)이 만드는 폴더.
        // 클라우드 저장소 폴더는 처음 열 때 macOS가 접근 허용을 묻는다
        let cloudStorage = home.appending(path: "Library/CloudStorage")
        let providers = ((try? fileManager.contentsOfDirectory(
            at: cloudStorage, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { !isDataless($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let cloud = [home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs")] + providers
        let volumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]
        ) ?? []
        let recent = (UserDefaults.standard.stringArray(forKey: recentKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { $0.standardizedFileURL != current.standardizedFileURL }
        return [
            Section(title: "Favorites", urls: favorites),
            Section(title: "Cloud", urls: cloud),
            Section(title: "Locations", urls: volumes),
            Section(title: "Recent", urls: recent),
        ]
        .map { Section(title: $0.title, urls: $0.urls.filter(isOpenableFolder)) }
        .filter { !$0.urls.isEmpty }
    }

    /// 최근 폴더에 넣는다 (가장 최근이 앞)
    static func remember(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        var recent = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        // 지금 폴더는 메뉴에서 빼므로 하나 더 둔다
        UserDefaults.standard.set(Array(recent.prefix(recentLimit + 1)), forKey: recentKey)
    }

    /// 내용이 내려받아지지 않은 자리만 있는 폴더. 앱이 숨겨 둔 클라우드 저장소(예: MYBOX-none)가 이렇게 남아
    /// Finder 사이드바에는 보이지 않는다
    private static func isDataless(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }

    private static func isOpenableFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// 경로 표시줄 맨 앞의 Places 버튼
struct PlacesButton: View {
    let current: URL
    let onSelect: (URL) -> Void

    @State private var anchor = MenuAnchorBox()

    var body: some View {
        // Rename의 프리셋 메뉴 버튼과 같은 모양: 버튼 배경 + 아이콘 + 작은 ⌄ (메뉴가 열린다는 표시)
        Button(action: showMenu) {
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
        // 아이콘 이름에서 자동으로 만든 이름("Map Pin…") 대신
        .accessibilityLabel("Places")
        .background(MenuAnchor { anchor.view = $0 })
        .fixedSize()
        .help("Go to a favorite folder, volume or recent folder")
    }

    private func showMenu() {
        guard let view = anchor.view, view.window != nil else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, section) in Places.sections(current: current).enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: section.title))
            for url in section.urls {
                let item = MenuAction.item(title: FileManager.default.displayName(atPath: url.path)) { onSelect(url) }
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                item.toolTip = (url.path as NSString).abbreviatingWithTildeInPath
                item.state = url.standardizedFileURL == current.standardizedFileURL ? .on : .off
                menu.addItem(item)
            }
        }
        menu.popUp(below: view)
    }
}
