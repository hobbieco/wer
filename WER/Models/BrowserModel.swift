//
//  BrowserModel.swift
//  WER
//

import AppKit
import Observation
import SwiftUI

/// 창 하나의 파일 선택·정렬 상태.
@Observable
final class BrowserModel {
    private(set) var folder: URL
    /// Select 목록에 보여줄 파일 용량(바이트). 폴더·패키지는 없다
    private(set) var fileSizes: [URL: Int64] = [:]
    private(set) var items: [FileItem] = [] {
        didSet { refreshRename() }
    }
    private(set) var loadError: String?
    /// 폴더를 열 때마다 증가. 같은 폴더를 다시 열어도 목록 스크롤을 초기화하는 데 쓴다.
    private(set) var openCount = 0
    var showHidden = false {
        didSet { reload() }
    }
    /// Select 목록 이름 정렬 방식. 앱 전체에서 기억한다
    private(set) var sort: FileSort = .natural {
        didSet {
            items = sort.sorted(items, foldersFirst: AppSettings.sortsFoldersFirst)
            UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey)
        }
    }
    var selection: Set<URL> = [] {
        didSet {
            // 다른 파일을 고르면 실행 로그 대신 미리보기로 돌아간다
            if !selection.isEmpty, !isRunning { isShowingRunLog = false }
            // Select에서 고르면 Order 선택(과 그에 따른 Select의 약한 강조)을 지운다
            if !selection.isEmpty, !orderSelection.isEmpty {
                orderSelection = []
            }
            previewSelection = selection
        }
    }
    var isGoToFolderPresented = false

    /// 칸 구분. 키 입력을 받는 칸을 나타낸다
    enum Pane { case select, order, rename }
    /// 키 입력을 받는 칸. 제목 강조와 메뉴 단축키 활성화에 쓴다
    private(set) var focusedPane: Pane?

    /// ⌘T / ⇧⌘T로 옮겨 갈 칸. 각 칸이 받아 자기 목록이나 입력칸에 포커스를 준다
    struct FocusRequest: Equatable {
        let id = UUID()
        let pane: Pane
    }
    private(set) var focusRequest: FocusRequest?
    /// Select 칸이 접혀 있으면 칸 전환에서 건너뛴다 (창이 SceneStorage로 기억하는 값을 받아 둔다)
    var isSelectCollapsed = false

    /// Select → Order → Rename 순서로 돌아가며 포커스를 옮긴다. 포커스가 없으면 첫 칸부터
    func focusNextPane(forward: Bool = true) {
        let panes: [Pane] = isSelectCollapsed ? [.order, .rename] : [.select, .order, .rename]
        let next = focusedPane.flatMap(panes.firstIndex(of:)).map {
            ($0 + (forward ? 1 : panes.count - 1)) % panes.count
        } ?? 0
        focusRequest = FocusRequest(pane: panes[next])
    }

    /// 칸에 포커스를 옮긴다. 접힌 Select 칸으로는 옮기지 않는다
    func requestFocus(_ pane: Pane) {
        guard pane != .select || !isSelectCollapsed else { return }
        focusRequest = FocusRequest(pane: pane)
    }

    /// 목록용 단축키를 켤 칸. Select 목록에서 이름을 고치는 중에는 입력칸의 화살표·⌘화살표가 커서를 움직여야 해서 nil
    var shortcutPane: Pane? {
        renamingURL == nil ? focusedPane : nil
    }

    /// 칸의 포커스가 바뀔 때 부른다. 다른 칸이 먼저 포커스를 받았으면 그대로 둔다
    func setFocus(_ pane: Pane, _ isFocused: Bool) {
        if isFocused {
            focusedPane = pane
        } else if focusedPane == pane {
            focusedPane = nil
        }
    }

    // Run Rename 상태
    var runRequest: RunRequest?
    private(set) var runState: RunState = .idle
    /// 실행 진행률(0~1). nil이면 끝을 알 수 없음(실패 후 되돌리는 중)
    private(set) var runProgress: Double? = 0
    /// 금방 끝나는 실행에서 막대가 깜빡이지 않도록, 0.3초가 지나도 실행 중일 때만 보여준다
    private(set) var isRunProgressVisible = false
    private var runProgressID = UUID()
    private(set) var runLog: [RenameLogEntry] = []
    /// 지금 로그가 되돌릴 수 있는 실행(lastRun)의 로그인지. 로그 제목 줄의 Undo 버튼에 쓴다
    private(set) var isRunLogUndoable = false
    var isShowingRunLog = false
    private(set) var lastRun: UndoRecord?
    /// 강제 종료로 남은 작업 기록 (복구 확인용)
    var pendingRecovery: RenameJournal?
    static var didCheckJournal = false

    private(set) var orderedFiles: [FileItem] = [] {
        didSet { refreshRename() }
    }
    var orderSelection: Set<URL> = [] {
        didSet {
            if !orderSelection.isEmpty, !isRunning { isShowingRunLog = false }
            // Order에서 고르면 Select 선택(과 그에 따른 Order의 약한 강조)을 지운다
            if !orderSelection.isEmpty, !selection.isEmpty {
                selection = []
            }
            previewSelection = orderSelection
        }
    }
    /// 마지막으로 선택을 바꾼 목록(Select 또는 Order)의 선택
    private(set) var previewSelection: Set<URL> = []

    var renameSettings = RenameSettings()
    /// Apply로 적용한 설정. nil이면 새 이름을 보여주지 않는다.
    private(set) var appliedSettings: RenameSettings? {
        didSet { refreshRename() }
    }
    /// 적용한 설정 기준의 새 이름과 충돌 결과.
    /// Table 셀은 행 값이 같으면 다시 그리지 않아서, 셀이 직접 읽어 변경을 감지할 수 있게 저장해 둔다.
    private(set) var newNames: [URL: String] = [:]
    private(set) var regexHighlights: [URL: [NameHighlight]] = [:]
    private(set) var newNameHighlights: [URL: [NameHighlight]] = [:]
    private(set) var renameConflicts = RenameConflicts()
    var isCopyFolderPresented = false

    private static let lastFolderKey = "lastFolderPath"
    private static let sortKey = "fileSort"

    init(folder: URL? = nil) {
        // 시작 폴더: 지정 폴더(설정) → 마지막 작업 폴더 → HOME
        let startup = AppSettings.customFolder(modeKey: AppSettings.startupModeKey, pathKey: AppSettings.startupPathKey)
        self.folder = (folder ?? startup ?? Self.lastFolder ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
        // 이름 규칙은 시작 프리셋(설정 > General, 기본 Default)으로 시작한다
        let startupPreset = PresetStore.shared.startupPreset
        startupPreset.apply(to: &renameSettings)
        loadedPresetID = startupPreset.id
        sort = UserDefaults.standard.string(forKey: Self.sortKey).flatMap(FileSort.init(rawValue:)) ?? .natural
        reload()
    }

    /// 자연 정렬 ↔ 사전식 정렬
    func toggleSort() {
        sort = sort == .natural ? .lexicographic : .natural
    }

    func setSort(_ newSort: FileSort) {
        sort = newSort
    }

    /// 마지막으로 연 폴더. 저장된 값이 없거나 폴더가 사라졌으면 nil
    private static var lastFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: lastFolderKey) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path)
    }

    var files: [FileItem] { items.filter { !$0.isDirectory } }

    /// Select에서 파일을 하나 이상 골랐는지 (폴더만 고르면 false)
    var hasSelectedFiles: Bool { files.contains { selection.contains($0.url) } }

    /// 선택한 파일, 선택이 없으면 폴더의 전체 파일. 하위 폴더는 제외한다.
    var targetFiles: [FileItem] {
        let selected = files.filter { selection.contains($0.url) }
        return selected.isEmpty ? files : selected
    }

    /// Order 목록 수 / Select 목록의 파일 수(하위 폴더 제외)
    var countText: String {
        "\(orderedFiles.count) of \(files.count) files selected"
    }

    // MARK: - Rename

    /// Back으로 되돌릴 상태: 규칙, 적용된 결과, 불러와 있던 프리셋, 적용할 때 불러와 있던 프리셋
    struct RenameHistoryEntry {
        let settings: RenameSettings
        let applied: RenameSettings?
        let presetID: RenamePreset.ID?
        let appliedPresetID: RenamePreset.ID?
    }

    /// Apply하거나 프리셋을 불러오기 직전 상태를 쌓는다 (최대 renameHistoryLimit개)
    private(set) var renameHistory: [RenameHistoryEntry] = []
    static let renameHistoryLimit = 20

    /// settings·presetID는 Back했을 때 다섯 칸에 돌려놓을 규칙과 프리셋. 기본은 지금 다섯 칸
    private func pushHistory(settings: RenameSettings? = nil, presetID: RenamePreset.ID?? = nil) {
        renameHistory.append(RenameHistoryEntry(
            settings: settings ?? renameSettings,
            applied: appliedSettings,
            presetID: presetID ?? loadedPresetID,
            appliedPresetID: appliedPresetID
        ))
        if renameHistory.count > Self.renameHistoryLimit {
            renameHistory.removeFirst(renameHistory.count - Self.renameHistoryLimit)
        }
    }

    /// 마지막으로 불러온(또는 저장한) 프리셋
    private(set) var loadedPresetID: RenamePreset.ID?
    /// 지금 적용된 규칙을 Apply할 때 불러와 있던 프리셋 (Back으로 다섯 칸을 되돌릴 때 함께 돌려놓는다)
    private var appliedPresetID: RenamePreset.ID?

    var loadedPreset: RenamePreset? { PresetStore.shared.preset(loadedPresetID) }

    /// 불러온 프리셋과 규칙이 달라졌는지 (메뉴에 * 표시)
    var isPresetModified: Bool {
        guard let loadedPreset else { return false }
        return !loadedPreset.matches(renameSettings)
    }

    /// 프리셋을 다섯 칸에 불러온다. 새 이름은 Apply를 눌러야 바뀐다. Back으로 되돌릴 수 있다
    func loadPreset(_ preset: RenamePreset) {
        pushHistory()
        preset.apply(to: &renameSettings)
        loadedPresetID = preset.id
    }

    /// 지금 규칙을 불러온 프리셋에 덮어쓴다
    func saveToLoadedPreset() {
        guard var preset = loadedPreset else { return }
        preset.update(from: renameSettings)
        PresetStore.shared.update(preset)
    }

    /// 지금 규칙을 새 프리셋으로 저장하고, 그 프리셋을 불러온 상태로 둔다
    func saveAsPreset(named name: String) {
        if let id = PresetStore.shared.save(name: name, from: renameSettings) {
            loadedPresetID = id
        }
    }

    /// Go to Folder 시작 위치: 설정(마지막으로 이동한 폴더 / 현재 폴더 / 지정 폴더). 없으면 현재 폴더
    var goToFolderStart: URL {
        AppSettings.startFolder(
            modeKey: AppSettings.goToModeKey, defaultMode: AppSettings.defaultGoToMode,
            pathKey: AppSettings.goToPathKey, lastKey: AppSettings.lastGoToPathKey, current: folder
        )
    }

    /// Copy To 시작 위치: 이번에 이미 고른 복사 위치 → 설정(마지막으로 고른 폴더 / 현재 폴더 / 지정 폴더)
    var copyToStart: URL {
        renameSettings.copyFolder ?? AppSettings.startFolder(
            modeKey: AppSettings.copyToModeKey, defaultMode: AppSettings.defaultCopyToMode,
            pathKey: AppSettings.copyToPathKey, lastKey: AppSettings.lastCopyToPathKey, current: folder
        )
    }

    /// 칸에 오류가 있으면 적용하지 않는다
    /// 모든 칸이 None이거나 오류가 있거나 바뀐 게 없으면 적용할 수 없다
    var canApplyRenameSettings: Bool {
        renameSettings != appliedSettings
            && !renameSettings.tokens.allSatisfy { $0.kind == .none }
            && renameSettings.isValid
    }

    /// ⌘1~5로 칸 종류 드롭다운을 열어 달라는 요청. Rename 칸의 TokenGridEditor가 받아 처리한다
    struct KindMenuRequest: Equatable {
        let id = UUID()
        let slot: Int
    }
    var kindMenuRequest: KindMenuRequest?

    func requestKindMenu(slot: Int) {
        kindMenuRequest = KindMenuRequest(slot: slot)
    }

    /// ⌘L로 프리셋 메뉴를 열어 달라는 요청. Rename 칸이 받아 처리한다
    private(set) var presetMenuRequest: UUID?

    func requestPresetMenu() {
        presetMenuRequest = UUID()
    }

    /// Space·⌘Y로 미리보기 미디어를 재생/일시정지해 달라는 요청. Preview의 플레이어가 받아 처리한다
    private(set) var playbackToggleRequest: UUID?

    /// 미리보기에 동영상·오디오 하나가 보이고 있을 때
    var canTogglePreviewPlayback: Bool {
        guard AppSettings.isPreviewEnabled, previewSelection.count == 1, let url = previewSelection.first else { return false }
        return PreviewMediaKind(url) != nil
    }

    func togglePreviewPlayback() {
        guard canTogglePreviewPlayback else { return showNotice(playbackUnavailableMessage) }
        playbackToggleRequest = UUID()
    }

    var playbackUnavailableMessage: String {
        AppSettings.isPreviewEnabled ? "Select a video or audio file to play" : "Preview is off"
    }

    func applyRenameSettings() {
        guard renameSettings.isValid else { return }
        // Apply 직전 다섯 칸은 지금 적용하는 규칙과 같아서, Back하면 이전에 적용했던 규칙을 다섯 칸에 돌려놓는다
        if let appliedSettings {
            pushHistory(settings: appliedSettings, presetID: appliedPresetID)
        } else {
            pushHistory()
        }
        appliedSettings = renameSettings
        appliedPresetID = loadedPresetID
    }

    /// Apply나 프리셋 불러오기 직전 상태로 되돌린다 (규칙, 결과, 프리셋 이름). 복사 설정은 현재 값을 유지한다
    func backRenameSettings() {
        guard let entry = renameHistory.popLast() else { return }
        var settings = entry.settings
        settings.isCopy = renameSettings.isCopy
        settings.copyFolder = renameSettings.copyFolder
        renameSettings = settings
        appliedSettings = entry.applied.map { applied in
            var applied = applied
            applied.isCopy = settings.isCopy
            applied.copyFolder = settings.copyFolder
            return applied
        }
        loadedPresetID = entry.presetID
        appliedPresetID = entry.appliedPresetID
    }

    private func refreshRename() {
        let built = appliedSettings.map { applied in
            orderedFiles.enumerated().compactMap { index, item in
                applied.buildNewName(for: item.name, index: index).map { (item.url, $0) }
            }
        } ?? []
        newNames = Dictionary(built.map { ($0.0, $0.1.name) }, uniquingKeysWith: { first, _ in first })
        newNameHighlights = Dictionary(built.map { ($0.0, $0.1.highlights) }, uniquingKeysWith: { first, _ in first })
        renameConflicts = computeRenameConflicts()
        regexHighlights = appliedSettings.map { applied in
            Dictionary(orderedFiles.map { ($0.url, applied.highlights(for: $0.name)) }, uniquingKeysWith: { first, _ in first })
        } ?? [:]
        regexMisses = appliedSettings.map { applied in
            let regexSlots = applied.tokens.indices.filter { applied.tokens[$0].kind == .regex }
            return Dictionary(orderedFiles.compactMap { item in
                let stem = RenameSettings.stem(of: item.name)
                let missed = regexSlots.filter { applied.tokens[$0].regexRange(in: stem) == nil }
                return missed.isEmpty ? nil : (item.url, missed)
            }, uniquingKeysWith: { first, _ in first })
        } ?? [:]
        nameIssues = computeNameIssues()
    }

    /// 파일 이름으로 쓸 수 없는 새 이름. errors는 빨간 아이콘, warnings는 주황 아이콘
    struct NameIssues {
        var errors: [URL: String] = [:]
        var warnings: [URL: String] = [:]
    }

    private(set) var nameIssues = NameIssues()
    /// APFS 파일 이름 최대 길이 (UTF-8 바이트)
    static let maxFileNameBytes = 255

    private func computeNameIssues() -> NameIssues {
        guard appliedSettings != nil else { return NameIssues() }
        var issues = NameIssues()
        for item in orderedFiles {
            guard let name = newNames[item.url] else {
                issues.errors[item.url] = "No new name"
                continue
            }
            if name.utf8.count > Self.maxFileNameBytes {
                issues.errors[item.url] = "Name too long (\(name.utf8.count) of \(Self.maxFileNameBytes) bytes)"
            } else if name.hasPrefix(".") {
                issues.warnings[item.url] = "Starts with \".\" and will be hidden in Finder"
            }
        }
        return issues
    }

    /// 복사 위치. 지정하지 않으면 원본 폴더 안의 rename 폴더(실행할 때 만든다)
    var copyDestination: URL {
        renameSettings.copyFolder ?? folder.appending(path: AppSettings.copyFolderName)
    }

    /// 복사 위치 지정. 폴더가 아니면 false
    func setCopyFolder(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        renameSettings.copyFolder = url
        UserDefaults.standard.set(url.path, forKey: AppSettings.lastCopyToPathKey)
        return true
    }

    /// 새 이름 충돌 검사 결과
    struct RenameConflicts {
        /// Order에서 빨간색으로 표시할 파일 (새 이름끼리 겹치거나 결과 폴더의 기존 항목과 겹침)
        var order: Set<URL> = []
        /// Select에서 빨간색으로 표시할 항목 (원본 변경일 때 새 이름과 겹치는, 이름을 바꾸지 않는 항목)
        var select: Set<URL> = []
        /// 새 이름끼리 겹치는 파일
        var duplicates: Set<URL> = []
        /// 결과 폴더(원본 변경이면 원본 폴더, 복사면 복사 위치)에 같은 이름이 이미 있는 파일
        var existing: Set<URL> = []
        var duplicateCount: Int { duplicates.count }
        /// 복사 위치에 같은 이름이 이미 있는 파일 수
        var existingInCopyFolder = 0
    }

    /// 파일별로 일치하지 않은 정규식 조각 번호(0부터). 일치하지 않은 조각은 새 이름에서 빠진다
    private(set) var regexMisses: [URL: [Int]] = [:]

    /// 적용 후 실행에 문제가 없는 파일 수. 적용 전이면 nil
    var readyCount: Int? {
        guard appliedSettings != nil else { return nil }
        return orderedFiles.filter {
            newNames[$0.url] != nil && !renameConflicts.order.contains($0.url) && regexMisses[$0.url] == nil
                && nameIssues.errors[$0.url] == nil && nameIssues.warnings[$0.url] == nil
        }.count
    }

    /// New Name 앞 경고 아이콘 설명. 문제가 없으면 nil
    func issueDescription(for url: URL) -> String? {
        var lines: [String] = []
        if let error = nameIssues.errors[url] { lines.append(error) }
        if let warning = nameIssues.warnings[url] { lines.append(warning) }
        if renameConflicts.duplicates.contains(url) { lines.append("Duplicate new name") }
        if renameConflicts.existing.contains(url) {
            lines.append(appliedSettings?.isCopy == true
                ? "Same name already exists in copy folder"
                : "Same name already exists in this folder")
        }
        if let slots = regexMisses[url] {
            lines.append("Regex didn't match (slot \(slots.map { String($0 + 1) }.joined(separator: ", ")))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// 결과 폴더의 볼륨이 대소문자를 구분하는지에 따라 이름을 비교한다.
    /// 원본 변경이면 같은 폴더에서 이름을 바꾸지 않는 항목, 복사면 복사 위치의 기존 항목과 비교한다.
    private func computeRenameConflicts() -> RenameConflicts {
        guard let applied = appliedSettings else { return RenameConflicts() }
        let target = applied.isCopy
            ? (applied.copyFolder ?? folder.appending(path: AppSettings.copyFolderName))
            : folder
        let caseSensitive = FileNameComparer.isCaseSensitive(at: target)
        let key = { (name: String) in FileNameComparer.key(name, caseSensitive: caseSensitive) }

        let newKeys = newNames.mapValues(key)
        var counts: [String: Int] = [:]
        for newKey in newKeys.values { counts[newKey, default: 0] += 1 }
        let duplicates = Set(newKeys.filter { counts[$0.value, default: 0] > 1 }.keys)

        var result = RenameConflicts()
        result.duplicates = duplicates
        if applied.isCopy {
            let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? []).map(key))
            let colliding = Set(newKeys.filter { existing.contains($0.value) }.keys)
            result.existing = colliding
            result.existingInCopyFolder = colliding.count
            result.order = duplicates.union(colliding)
        } else {
            let ordered = Set(orderedFiles.map(\.url))
            let untouched = items.filter { !ordered.contains($0.url) }
            let newKeySet = Set(newKeys.values)
            result.select = Set(untouched.filter { newKeySet.contains(key($0.name)) }.map(\.url))
            let untouchedKeys = Set(untouched.map { key($0.name) })
            result.existing = Set(newKeys.filter { untouchedKeys.contains($0.value) }.keys)
            result.order = duplicates.union(result.existing)
        }
        return result
    }

    // MARK: - Folder

    /// 상위 폴더로 이동하고 지금 폴더를 선택한다 (←, ⌘↑)
    func openEnclosingFolder() {
        guard canNavigateByKeyboard() else { return }
        let current = folder
        let parent = current.deletingLastPathComponent()
        guard parent != current else { return }
        open(parent)
        selection = Set(items.filter { $0.url.standardizedFileURL.path == current.path }.map(\.url))
    }

    var canOpenEnclosingFolder: Bool { folder.path != "/" }

    /// 선택한 폴더 하나로 들어가 첫 항목을 선택한다 (→, Finder 칸 보기와 같은 방식). 폴더를 하나만 골랐을 때만 동작한다
    @discardableResult
    func enterSelectedFolder() -> Bool {
        let selected = items.filter { selection.contains($0.url) }
        guard selected.count == 1, let target = selected.first, target.isDirectory else { return false }
        guard canNavigateByKeyboard() else { return true }
        open(target.url)
        if let first = items.first { selection = [first.url] }
        return true
    }

    /// 방향키로 폴더를 옮기면 Order가 비워져서, Order에 파일이 있으면 막고 상태 바에 안내한다
    private func canNavigateByKeyboard() -> Bool {
        guard !orderedFiles.isEmpty else { return true }
        showNotice("Arrow-key navigation is off while Order has files")
        return false
    }

    /// 상태 바 2칸에 잠깐 보여줄 안내. 문장이 길어지면 표시 시간을 늘린다
    private(set) var notice: String?
    static let noticeDuration: Double = 5
    private var noticeTask: Task<Void, Never>?

    func showNotice(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.noticeDuration))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func open(_ url: URL) {
        let newFolder = url.standardizedFileURL
        // 다른 폴더로 가면 정렬 목록을 비운다 (정렬 목록은 현재 폴더 파일만 다룬다)
        if newFolder != folder {
            orderedFiles = []
            orderSelection = []
        }
        folder = newFolder
        selection = []
        reload()
        openCount += 1
        UserDefaults.standard.set(folder.path, forKey: Self.lastFolderKey)
    }

    func reload() {
        do {
            (items, fileSizes) = try FolderLoader.loadWithSizes(
                folder, showHidden: showHidden, sort: sort, foldersFirst: AppSettings.sortsFoldersFirst
            )
            loadError = nil
        } catch {
            items = []
            fileSizes = [:]
            loadError = error.localizedDescription
        }
        selection.formIntersection(items.map(\.url))
        // 폴더를 옮기거나 다시 읽어 항목이 사라지면 이름 바꾸기를 끝낸다
        if let url = renamingURL, !items.contains(where: { $0.url == url }) {
            renamingURL = nil
        }
    }

    /// Finder의 폴더로 이동(⇧⌘G)과 같이 경로로 이동한다. 파일 경로면 상위 폴더를 열고 그 파일을 선택한다.
    @discardableResult
    func go(to path: String) -> Bool {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue {
            open(url)
        } else {
            open(url.deletingLastPathComponent())
            selection = [url]
        }
        UserDefaults.standard.set(folder.path, forKey: AppSettings.lastGoToPathKey)
        return true
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    /// 선택한 항목을 연다 (⌘O). 폴더 하나만 골랐으면 그 폴더로 이동하고, 나머지는 기본 앱(폴더는 Finder)으로 연다
    func openSelection() {
        // Order 목록도 현재 폴더 파일만 담으므로 Select 목록에서 찾는다
        let selected = items.filter { previewSelection.contains($0.url) }
        if selected.count == 1, let item = selected.first, item.isDirectory {
            open(item.url)
            return
        }
        selected.forEach { NSWorkspace.shared.open($0.url) }
    }

    var canOpenSelection: Bool { !previewSelection.isEmpty }

    /// Select 목록에서 Return으로 이름을 바꾸는 중인 항목
    var renamingURL: URL?
    /// Select 목록의 이름 바꾸기 실패 이유 (알림용)
    var itemRenameError: String?

    /// Select 목록에서 항목 하나의 이름을 바로 바꾼다 (Finder의 Return).
    /// 빈 이름이나 같은 이름이면 그대로 두고, 문제가 있으면 itemRenameError에 이유를 남긴다
    func renameItem(_ url: URL, to newName: String) {
        guard let item = items.first(where: { $0.url == url }),
              !newName.isEmpty, newName != item.name else { return }
        if newName.contains("/") || newName.contains(":") {
            itemRenameError = "Names can't contain “/” or “:”."
            return
        }
        if newName.utf8.count > 255 {
            itemRenameError = "The name “\(newName)” is too long."
            return
        }
        if newName.hasPrefix("."), !item.name.hasPrefix(".") {
            itemRenameError = "Names that begin with “.” are reserved for hidden files."
            return
        }
        let caseSensitive = FileNameComparer.isCaseSensitive(at: folder)
        let isSameFile = FileNameComparer.key(newName, caseSensitive: caseSensitive)
            == FileNameComparer.key(item.name, caseSensitive: caseSensitive)
        let destination = folder.appending(path: newName)
        if !isSameFile, FileManager.default.fileExists(atPath: destination.path) {
            itemRenameError = "The name “\(newName)” is already taken. Please choose a different name."
            return
        }
        do {
            if isSameFile {
                // 대소문자나 정규화만 다른 이름은 임시 이름을 거쳐 바꾼다
                let temporary = folder.appending(path: ".wer-tmp-\(UUID().uuidString)")
                try FileManager.default.moveItem(at: item.url, to: temporary)
                do {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                } catch {
                    try? FileManager.default.moveItem(at: temporary, to: item.url)
                    throw error
                }
            } else {
                try FileManager.default.moveItem(at: item.url, to: destination)
            }
        } catch {
            itemRenameError = error.localizedDescription
            reload()
            return
        }
        reload()
        guard let renamed = items.first(where: { $0.name == newName }) else { return }
        // Order에 있던 파일이면 같은 자리에서 새 이름으로 바꾼다
        if let index = orderedFiles.firstIndex(where: { $0.url == item.url }) {
            orderedFiles[index] = renamed
            if orderSelection.remove(item.url) != nil { orderSelection.insert(renamed.url) }
        }
        selection = [renamed.url]
    }

    // MARK: - Order

    /// 대상 파일을 Select 순서에 맞춰 정렬 목록 사이에 넣고 Select 선택을 해제한다. 이미 있는 파일은 건너뛴다.
    func addToOrder() {
        let before = orderedFiles
        orderedFiles = OrderMover.insert(targetFiles, into: orderedFiles, reference: items)
        markRecentlyAdded(after: before)
        selection = []
    }

    /// 키보드로 추가한 뒤(⌘→, ⌥⌘→) 이어서 순서를 맞출 수 있도록, 추가한 파일을 선택하고 Order로 포커스를 옮긴다
    func focusOrder(selectingAddedSince before: [FileItem]) {
        let existing = Set(before.map(\.url))
        let added = orderedFiles.map(\.url).filter { !existing.contains($0) }
        if !added.isEmpty { orderSelection = Set(added) }
        requestFocus(.order)
    }

    /// Select의 모든 파일을 Select 순서에 맞춰 정렬 목록 사이에 넣는다 (⌥⌘→). 이미 있는 파일은 건너뛴다
    func addAllToOrder() {
        let before = orderedFiles
        orderedFiles = OrderMover.insert(files, into: orderedFiles, reference: items)
        markRecentlyAdded(after: before)
    }

    /// 아직 Order에 없는 파일이 있는지
    var canAddAllToOrder: Bool {
        let ordered = Set(orderedFiles.map(\.url))
        return files.contains { !ordered.contains($0.url) }
    }

    /// 정렬 목록을 비운다 (⌥⌘←). Order에 있던 포커스는 Select로 옮긴다
    func removeAllFromOrder() {
        orderedFiles = []
        orderSelection = []
        if focusedPane == .order { requestFocus(.select) }
    }

    /// 기존 목록 사이에 추가한 파일. 잠시 깜빡여 위치를 알려준다
    private(set) var recentlyAdded: Set<URL> = []
    private var recentlyAddedTask: Task<Void, Never>?

    /// 기존 목록이 있었을 때만 표시한다. 3초 뒤 지운다
    private func markRecentlyAdded(after before: [FileItem]) {
        guard !before.isEmpty else { return }
        let existing = Set(before.map(\.url))
        let added = Set(orderedFiles.map(\.url)).subtracting(existing)
        guard !added.isEmpty else { return }
        recentlyAddedTask?.cancel()
        recentlyAdded = added
        recentlyAddedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.recentlyAdded = []
        }
    }

    /// 정렬 목록을 Select 목록 순서로 되돌린다. 현재 폴더에 없는 파일은 기존 순서대로 뒤에 둔다.
    func resetOrder() {
        let index = Dictionary(items.enumerated().map { ($1.url, $0) }, uniquingKeysWith: { first, _ in first })
        let inFolder = orderedFiles.filter { index[$0.url] != nil }.sorted { index[$0.url]! < index[$1.url]! }
        let others = orderedFiles.filter { index[$0.url] == nil }
        orderedFiles = inFolder + others
    }

    func moveOrder(by offset: Int) {
        let indices = IndexSet(orderedFiles.indices.filter { orderSelection.contains(orderedFiles[$0].url) })
        orderedFiles = OrderMover.move(orderedFiles, selected: indices, by: offset).items
    }

    /// 연속 선택 구간마다 그 안에서 순서를 뒤집는다. 두 개 이상 이어진 구간이 없으면 목록 전체를 뒤집는다.
    func reverseOrder() {
        let indices = IndexSet(orderedFiles.indices.filter { orderSelection.contains(orderedFiles[$0].url) })
        orderedFiles = OrderMover.reverse(orderedFiles, selected: indices)
    }

    func moveOrderToTop() { moveOrder(by: -orderedFiles.count) }
    func moveOrderToBottom() { moveOrder(by: orderedFiles.count) }

    /// Order에 끌어다 놓기. 이미 목록에 있는 파일이면 순서 이동, Select에서 끌어온 파일이면 그 위치에 추가한다.
    func dropOnOrder(_ urls: [URL], at destination: Int) {
        let ordered = Set(orderedFiles.map(\.url))
        if urls.allSatisfy(ordered.contains) {
            dragOrder(urls, to: destination)
            return
        }
        // 끈 파일이 Select 선택에 포함되면 선택한 파일 전체를 넣는다
        var dropped = Set(urls)
        if !dropped.isDisjoint(with: selection) {
            dropped.formUnion(selection)
        }
        let newFiles = files.filter { dropped.contains($0.url) && !ordered.contains($0.url) }
        guard !newFiles.isEmpty else { return }
        let before = orderedFiles
        orderedFiles.insert(contentsOf: newFiles, at: min(destination, orderedFiles.count))
        markRecentlyAdded(after: before)
        selection = []
    }

    /// 끌어다 놓은 파일들을 destination 위치로 옮긴다. 목록에 없는 파일은 무시한다.
    func dragOrder(_ urls: [URL], to destination: Int) {
        let moving = Set(urls)
        let source = IndexSet(orderedFiles.indices.filter { moving.contains(orderedFiles[$0].url) })
        guard !source.isEmpty else { return }
        orderedFiles.move(fromOffsets: source, toOffset: destination)
    }

    /// Order에서 Select로 끌어다 놓은 파일을 정렬 목록에서 뺀다. 목록에 없던 파일이면 false
    @discardableResult
    func removeFromOrder(_ urls: [URL]) -> Bool {
        let removing = Set(urls)
        guard orderedFiles.contains(where: { removing.contains($0.url) }) else { return false }
        orderedFiles.removeAll { removing.contains($0.url) }
        orderSelection.subtract(removing)
        return true
    }

    /// 선택한 파일을 정렬 목록에서 뺀다. 선택이 없으면 목록을 비운다.
    /// 이어서 지울 수 있도록 지운 자리의 다음 파일을 선택하고, 목록이 비면 Order에 있던 포커스를 Select로 옮긴다
    func removeFromOrder() {
        let firstRemoved = orderedFiles.firstIndex { orderSelection.contains($0.url) }
        if orderSelection.isEmpty {
            orderedFiles = []
        } else {
            orderedFiles.removeAll { orderSelection.contains($0.url) }
        }
        if let firstRemoved, !orderedFiles.isEmpty {
            orderSelection = [orderedFiles[min(firstRemoved, orderedFiles.count - 1)].url]
        } else {
            orderSelection = []
        }
        if orderedFiles.isEmpty, focusedPane == .order {
            requestFocus(.select)
        }
    }
}

// MARK: - Run Rename

extension BrowserModel {
    /// 확인 창에 보여줄 실행 요청
    struct RunRequest: Identifiable {
        let id = UUID()
        let plan: RenamePlan
        /// 🟠 경고 (Regex 불일치, 숨김 이름)
        let warnings: [String]
    }

    /// 실행 상태. 상태 바 오른쪽과 버튼 활성화에 쓴다
    enum RunState: Equatable {
        case idle
        case running(done: Int, total: Int, reverting: Bool)
        case finished(String)
    }

    /// 되돌리기 기록: 실행한 계획과 실행 직전 화면 상태
    struct UndoRecord {
        let plan: RenamePlan
        let orderedFiles: [FileItem]
        let appliedSettings: RenameSettings?
    }

    var isRunning: Bool {
        if case .running = runState { true } else { false }
    }

    var isReverting: Bool {
        if case .running(_, _, true) = runState { true } else { false }
    }

    private func startRunProgress() {
        runProgress = 0
        isRunProgressVisible = false
        let id = UUID()
        runProgressID = id
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.runProgressID == id, self.isRunning else { return }
            self.isRunProgressVisible = true
        }
    }

    /// Apply된 상태이고 🔴 오류가 없을 때 실행할 수 있다
    var canRun: Bool {
        guard appliedSettings != nil, !isRunning, !orderedFiles.isEmpty else { return false }
        return renameConflicts.order.isEmpty && nameIssues.errors.isEmpty && !makePlan().items.isEmpty
    }

    var canUndoRun: Bool { lastRun != nil && !isRunning }

    /// 실행 계획. 원본 변경이면 새 이름이 지금 이름과 같은 파일은 뺀다 (복사는 같은 이름이어도 복사한다)
    func makePlan() -> RenamePlan {
        let isCopy = appliedSettings?.isCopy == true
        let destinationFolder = isCopy ? copyDestination : nil
        let items = orderedFiles.compactMap { item -> RenamePlan.Item? in
            guard let name = newNames[item.url] else { return nil }
            if let destinationFolder {
                return RenamePlan.Item(source: item.url, destination: destinationFolder.appending(path: name))
            }
            guard name != item.name else { return nil }
            return RenamePlan.Item(source: item.url, destination: item.url.deletingLastPathComponent().appending(path: name))
        }
        return RenamePlan(mode: destinationFolder.map { .copy(destination: $0) } ?? .rename, items: items)
    }

    /// Run Rename 버튼. 확인 창을 띄운다
    func requestRun() {
        guard canRun else { return }
        var warnings: [String] = []
        if !regexMisses.isEmpty { warnings.append("\(regexMisses.count) files: regex didn't match") }
        if !nameIssues.warnings.isEmpty { warnings.append("\(nameIssues.warnings.count) files: name starts with \".\" (hidden)") }
        runRequest = RunRequest(plan: makePlan(), warnings: warnings)
    }

    /// 확인 창에서 실행을 누르면 호출한다
    func performRun(_ plan: RenamePlan) async {
        let executor = RenameExecutor()
        let verb = plan.isCopy ? "Copy" : "Rename"
        runLog = [RenameLogEntry(kind: .info, message: "\(verb) \(plan.items.count) files")]
        isRunLogUndoable = false
        isShowingRunLog = true

        let issues = executor.preflight(plan)
        guard issues.isEmpty else {
            for issue in issues {
                if let item = issue.item {
                    runLog.append(.item(.failure, item, issue.reason))
                } else {
                    runLog.append(RenameLogEntry(kind: .failure, message: issue.reason))
                }
            }
            runLog.append(RenameLogEntry(kind: .info, message: "\(verb) not started. Nothing was changed."))
            runState = .finished("\(verb) not started")
            return
        }

        let snapshot = UndoRecord(plan: plan, orderedFiles: orderedFiles, appliedSettings: appliedSettings)
        runState = .running(done: 0, total: plan.items.count, reverting: false)
        startRunProgress()
        let outcome = await executor.execute(plan) { entry in
            runLog.append(entry)
            if case .running(let done, let total, let reverting) = runState {
                let isStep = entry.kind == .success || entry.kind == .revert
                runState = .running(done: done + (isStep ? 1 : 0), total: total, reverting: reverting || entry.kind == .revert)
            }
            if entry.kind == .revert { runProgress = nil }
        } progress: { value in
            runProgress = value
        }

        if outcome.succeeded {
            finishSuccessfulRun(plan, snapshot: snapshot)
        } else if outcome.notStarted {
            for failure in outcome.failures {
                runLog.append(RenameLogEntry(kind: .failure, message: failure.reason))
            }
            runLog.append(RenameLogEntry(kind: .info, message: "\(verb) not started. Nothing was changed."))
            runState = .finished("\(verb) not started")
        } else {
            for failure in outcome.failures {
                runLog.append(.item(.failure, failure.item, failure.reason))
            }
            for file in outcome.unreverted {
                runLog.append(RenameLogEntry(
                    kind: .warning,
                    message: "Could not revert: \(file.current.lastPathComponent) → \(file.original.lastPathComponent)",
                    detail: file.current.deletingLastPathComponent().path
                ))
            }
            runLog.append(RenameLogEntry(kind: .info, message: "\(verb) failed. All changes were reverted."))
            reload()
            runState = .finished("\(verb) failed, reverted")
        }
    }

    /// 성공: Order·New Name을 비우고(규칙은 유지) Select를 다시 읽어 바뀐 파일을 선택한다
    private func finishSuccessfulRun(_ plan: RenamePlan, snapshot: UndoRecord) {
        lastRun = snapshot
        isRunLogUndoable = true
        let count = plan.items.count
        runLog.append(RenameLogEntry(kind: .info, message: plan.isCopy ? "Copied \(count) files" : "Renamed \(count) files"))
        orderedFiles = []
        orderSelection = []
        appliedSettings = nil
        reload()
        if !plan.isCopy {
            selection = Set(plan.items.map(\.destination.standardizedFileURL)).intersection(items.map(\.url))
        }
        // Order가 비었으니 바뀐 파일이 보이는 Select로 포커스를 옮긴다
        requestFocus(.select)
        runState = .finished(plan.isCopy ? "Copied \(count) files" : "Renamed \(count) files")
    }

    /// 마지막 실행을 되돌린다. 파일과 Order·New Name을 실행 직전 상태로 돌린다
    func undoRun() async {
        guard let record = lastRun, !isRunning else { return }
        lastRun = nil
        let executor = RenameExecutor()
        runLog = [RenameLogEntry(kind: .info, message: "Undo \(record.plan.isCopy ? "copy" : "rename") of \(record.plan.items.count) files")]
        isRunLogUndoable = false
        isShowingRunLog = true
        runState = .running(done: 0, total: record.plan.items.count, reverting: true)
        startRunProgress()
        let outcome = await executor.undo(record.plan) { entry in
            runLog.append(entry)
            if case .running(let done, let total, _) = runState {
                runState = .running(done: done + 1, total: total, reverting: true)
            }
        } progress: { value in
            runProgress = value
        }
        for file in outcome.unreverted {
            runLog.append(RenameLogEntry(kind: .warning, message: "Skipped (moved or deleted): \(file.current.lastPathComponent)"))
        }
        reload()
        orderedFiles = record.orderedFiles
        appliedSettings = record.appliedSettings
        runLog.append(RenameLogEntry(kind: .info, message: "Undo finished"))
        runState = .finished("Undid last \(record.plan.isCopy ? "copy" : "rename")")
    }

    /// 강제 종료로 남은 작업 기록이 있으면 복구 확인을 띄운다 (앱을 켜고 처음 열린 창에서 한 번)
    func checkInterruptedRun() {
        guard !Self.didCheckJournal else { return }
        Self.didCheckJournal = true
        pendingRecovery = RenameJournal.load()
    }

    /// 작업 기록대로 원래 상태로 되돌리고 결과를 로그에 남긴다
    func recoverInterruptedRun() {
        guard let journal = pendingRecovery else { return }
        pendingRecovery = nil
        let unrecovered = RenameExecutor().recover(journal)
        runLog = [RenameLogEntry(kind: .info, message: "Recovered interrupted \(journal.isCopy ? "copy" : "rename") of \(journal.entries.count) files")]
        isRunLogUndoable = false
        for file in unrecovered {
            runLog.append(RenameLogEntry(
                kind: .warning,
                message: "Could not restore: \(file.current.lastPathComponent) → \(file.original.lastPathComponent)",
                detail: file.current.deletingLastPathComponent().path
            ))
        }
        isShowingRunLog = true
        reload()
        runState = .finished(unrecovered.isEmpty ? "Recovered interrupted run" : "Recovery incomplete")
    }

    /// 상태 바 오른쪽
    var runStatusText: String {
        switch runState {
        case .idle:
            return appliedSettings == nil ? "Apply to preview new names" : "Ready to rename"
        case .running(let done, let total, let reverting):
            return "\(reverting ? "Reverting" : "Renaming") \(done) / \(total)"
        case .finished(let message):
            return message
        }
    }
}
