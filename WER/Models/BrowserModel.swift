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
    /// 현재 폴더 항목의 등록일·수정일. 날짜 조각과 파일 정보에 쓴다
    private(set) var fileDates: [URL: FileDates] = [:]
    /// 현재 폴더 밖에 있는 Order 파일의 날짜. 처음 쓸 때 읽어 두고, 폴더를 다시 읽으면 비운다
    @ObservationIgnored private var outsideFileDates: [URL: FileDates] = [:]

    // 촬영일 백그라운드 수집 (아래 Taken Date Collection)
    /// 읽은 결과. 수정일이 바뀌면 다시 읽는다
    @ObservationIgnored private var mediaCache: [URL: MediaCacheEntry] = [:]
    @ObservationIgnored private var mediaQueue: [URL] = []
    @ObservationIgnored private var mediaInFlight: Set<URL> = []
    /// 동시에 읽는 작업들. 비어 있으면 수집 중이 아니다
    @ObservationIgnored private var mediaWorkers: [Task<Void, Never>] = []
    /// 읽었지만 아직 화면에 반영하지 않은 파일. 모아서 한 번에 반영한다
    @ObservationIgnored private var mediaUnflushed: Set<URL> = []
    @ObservationIgnored private var isMediaFlushScheduled = false
    /// 촬영일 조각을 쓰는데 아직 읽지 않은 Order의 이미지·영상
    private(set) var pendingMediaURLs: Set<URL> = []
    /// 수집 진행 상황. 수집 중이 아니면 nil
    private(set) var mediaProgress: MediaProgress?
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
    /// Create Empty Files 창 (⌥⌘N)
    var isEmptyFilesPresented = false

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

    /// 마지막으로 포커스를 받은 칸. 다른 칸에서 넘어왔는지 판단한다 (창을 다시 앞으로 가져온 경우는 제외)
    private var lastFocusedPane: Pane?

    /// 칸의 포커스가 바뀔 때 부른다. 다른 칸이 먼저 포커스를 받았으면 그대로 둔다.
    /// 다른 칸에서 넘어왔으면(⌘T, Tab 등) 목록에서 이어 볼 파일을 선택하고, 선택을 바꿨으면 true (스크롤용)
    @discardableResult
    func setFocus(_ pane: Pane, _ isFocused: Bool) -> Bool {
        guard isFocused else {
            if focusedPane == pane { focusedPane = nil }
            return false
        }
        let arrived = lastFocusedPane != nil && lastFocusedPane != pane
        lastFocusedPane = pane
        focusedPane = pane
        guard arrived else { return false }
        switch pane {
        case .select: return selectOnArrivingAtSelect()
        case .order: return selectOnArrivingAtOrder()
        case .rename: return false
        }
    }

    /// 다른 폴더로 가면 Order가 비워져서 확인을 기다리는 이동 (끌어다 놓기, 경로 표시줄, Places, Go to Folder 등)
    var pendingNavigation: PendingNavigation?

    // Run Rename 상태
    var runRequest: RunRequest?
    private(set) var runState: RunState = .idle {
        // 실행하는 동안 촬영일 수집을 멈추고, 끝나면 이어 간다
        didSet { if runState.isRunning != oldValue.isRunning { updateMediaCollection() } }
    }
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
    /// 마지막으로 만든 빈 파일. lastRun과 둘 중 나중에 한 작업 하나만 되돌린다
    private(set) var lastEmptyFiles: [EmptyFilePlan.File]?
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
    private(set) var previewSelection: Set<URL> = [] {
        // 다른 항목을 고르면 파일 정보 레이어를 닫고 미리보기로 돌아간다
        didSet {
            guard previewSelection != oldValue else { return }
            contextMenuURLs = []
            fileInfoAutoClose?.cancel()
            isFileInfoShown = false
            prioritizeMedia(previewSelection)
            refreshSelectionInfo()
        }
    }
    /// 미리보기 위의 파일 정보 레이어 (⌘I). 선택이 바뀌면 닫힌다. 미리보기가 꺼져 있으면 정보가 늘 보여 쓰지 않는다
    private(set) var isFileInfoShown = false
    /// 하나만 고른 항목의 파일 안 정보 (촬영일·크기·길이). 선택이 멈추면 백그라운드로 읽는다
    private(set) var selectionMedia: SelectionMedia?
    @ObservationIgnored private var selectionInfoTask: Task<Void, Never>?

    var canToggleFileInfo: Bool {
        AppSettings.isPreviewEnabled && (isFileInfoShown || !previewSelection.isEmpty)
    }

    func toggleFileInfo() {
        guard canToggleFileInfo else { return }
        // ⌘I·버튼으로 열면 자동으로 닫지 않는다
        fileInfoAutoClose?.cancel()
        isFileInfoShown.toggle()
    }

    @ObservationIgnored private var fileInfoAutoClose: Task<Void, Never>?
    static let briefInfoSeconds: Double = 5

    /// 우클릭 메뉴의 Show Info. 잠깐 확인하는 용도라, 값을 다 읽은 뒤 5초가 지나면 닫는다.
    /// 그 전에 ⌘I를 누르거나 선택을 바꾸면 타이머는 없어진다
    func showInfoBriefly() {
        guard AppSettings.isPreviewEnabled, previewSelection.count >= 1 else { return }
        fileInfoAutoClose?.cancel()
        isFileInfoShown = true
        let selection = previewSelection
        fileInfoAutoClose = Task { [weak self] in
            // 촬영일 등을 읽는 중이면 다 읽을 때까지 기다린다 (최대 10초)
            for _ in 0..<50 {
                guard let self, !Task.isCancelled else { return }
                if !self.isWaitingForSelectionMedia { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            try? await Task.sleep(for: .seconds(Self.briefInfoSeconds))
            guard let self, !Task.isCancelled, self.previewSelection == selection else { return }
            self.isFileInfoShown = false
        }
    }

    /// 하나만 고른 이미지·영상·오디오의 정보를 아직 읽는 중인지
    private var isWaitingForSelectionMedia: Bool {
        guard previewSelection.count == 1, let url = previewSelection.first,
              MediaInfoReader.kind(of: url) != nil else { return false }
        return selectionMedia?.url != url
    }

    /// 하나만 고르고 0.25초 멈추면 (방향키로 지나가는 파일은 읽지 않는다) 등록일·수정일·용량을 다시 읽고,
    /// 이미지·영상·오디오면 헤더를 읽어 촬영일 수집과 같은 캐시에 넣는다
    private func refreshSelectionInfo() {
        selectionInfoTask?.cancel()
        guard previewSelection.count == 1, let url = previewSelection.first else {
            if selectionMedia != nil { selectionMedia = nil }
            return
        }
        let cached = cachedMedia(for: url).map { SelectionMedia(url: url, result: $0) }
        if selectionMedia != cached { selectionMedia = cached }
        selectionInfoTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.refreshAttributes(of: url)
            guard !Task.isCancelled, MediaInfoReader.kind(of: url) != nil, self.cachedMedia(for: url) == nil else { return }
            let result = await MediaInfoReader.readInBackground(url)
            guard !Task.isCancelled else { return }
            if result != .timedOut { self.storeMedia(result, for: url) }
            self.selectionMedia = SelectionMedia(url: url, result: result)
        }
    }

    /// 폴더를 연 뒤 바뀐 등록일·수정일·용량을 반영한다. 같으면 아무것도 바꾸지 않는다
    private func refreshAttributes(of url: URL) async {
        let read = await Task.detached { () -> (dates: FileDates, size: Int64?)? in
            guard let values = try? url.resourceValues(
                forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
            ) else { return nil }
            let dates = FileDates(created: values.creationDate, modified: values.contentModificationDate)
            return (dates, values.isDirectory == true ? nil : values.fileSize.map(Int64.init))
        }.value
        guard let (dates, size) = read, !Task.isCancelled else { return }
        var changed = false
        if fileDates[url] != nil {
            if fileDates[url] != dates {
                fileDates[url] = dates
                changed = true
            }
            if let size, fileSizes[url] != size {
                fileSizes[url] = size
            }
        } else if outsideFileDates[url] != dates {
            outsideFileDates[url] = dates
            changed = true
        }
        if changed, appliedSettings?.usesDates == true { refreshRename() }
    }

    /// 파일 정보 레이어에 보여줄 선택 항목
    func fileInfoEntries() -> [FileInfoEntry] {
        let lookup = Dictionary(items.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = previewSelection.map { url in
            let item = lookup[url]
            return FileInfoEntry(
                url: url, isDirectory: item?.isDirectory ?? false, isInFolder: item != nil, size: fileSizes[url]
            )
        }
        return entries.sorted { $0.url.path < $1.url.path }
    }

    var renameSettings = RenameSettings() {
        didSet {
            if renameSettings.usesMediaMetadata != oldValue.usesMediaMetadata { updateMediaCollection() }
        }
    }
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
    /// Select 선택에 폴더가 섞였는지. 섞이면 Order에 넣지 않는다 (우클릭 메뉴와 같은 규칙)
    var selectionHasFolders: Bool { items.contains { $0.isDirectory && selection.contains($0.url) } }
    static let mixedSelectionMessage = "Select only files to add to Order"

    /// ⌘→·Add 버튼·더블클릭. 폴더가 섞인 선택이면 넣지 않고 안내한다. 선택이 없으면 Add 버튼은 전체 파일
    func addSelectionToOrder(keepsSelection: Bool = false) {
        guard !selectionHasFolders else { return showNotice(Self.mixedSelectionMessage) }
        addToOrder(keepsSelection: keepsSelection)
    }

    /// 우클릭 메뉴의 대상 (우클릭한 줄이 선택 밖이면 그 줄). Services에 넘길 파일로도 쓴다.
    /// 메뉴를 만들 때 정하고, 선택이 바뀌면 비운다
    @ObservationIgnored var contextMenuURLs: [URL] = []

    /// Services(WER > Services, 우클릭 메뉴)에 넘길 항목
    var serviceURLs: [URL] {
        contextMenuURLs.isEmpty ? Array(previewSelection) : contextMenuURLs
    }

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

    /// settings·presetID는 Back했을 때 여섯 칸에 돌려놓을 규칙과 프리셋. 기본은 지금 여섯 칸
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
    /// 지금 적용된 규칙을 Apply할 때 불러와 있던 프리셋 (Back으로 여섯 칸을 되돌릴 때 함께 돌려놓는다)
    private var appliedPresetID: RenamePreset.ID?

    var loadedPreset: RenamePreset? { PresetStore.shared.preset(loadedPresetID) }

    /// 불러온 프리셋과 규칙이 달라졌는지 (메뉴에 * 표시)
    var isPresetModified: Bool {
        guard let loadedPreset else { return false }
        return !loadedPreset.matches(renameSettings)
    }

    /// 프리셋을 여섯 칸에 불러온다. 새 이름은 Apply를 눌러야 바뀐다. Back으로 되돌릴 수 있다
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

    /// ⌘1~6로 칸 종류 드롭다운을 열어 달라는 요청. Rename 칸의 TokenGridEditor가 받아 처리한다
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

    /// Space로 미리보기 미디어를 재생/일시정지해 달라는 요청. Preview의 플레이어가 받아 처리한다
    private(set) var playbackToggleRequest: UUID?

    /// 미리보기 플레이어가 보이는 파일. 재생할 수 있는 오디오·영상만 플레이어를 띄운다 (PreviewPanel이 알린다)
    private(set) var previewPlayerURL: URL?
    /// 미리보기에서 재생 중인지. 재생은 늘 사용자가 시작한다 (Space, 재생 버튼)
    private(set) var isPreviewPlaying = false

    func previewPlayerChanged(_ url: URL, isShown: Bool) {
        if isShown {
            previewPlayerURL = url
        } else if previewPlayerURL == url {
            previewPlayerURL = nil
            isPreviewPlaying = false
        }
    }

    func previewPlayingChanged(_ isPlaying: Bool) {
        if isPreviewPlaying != isPlaying { isPreviewPlaying = isPlaying }
    }

    /// 재생 중 ←→로 앞뒤 이동 요청
    struct SeekRequest: Equatable {
        let id = UUID()
        let seconds: Double
    }
    private(set) var playbackSeekRequest: SeekRequest?
    static let playbackSeekStep: Double = 10
    static let volumeStep: Double = 0.1

    func seekPreview(forward: Bool) {
        guard isPreviewPlaying else { return }
        playbackSeekRequest = SeekRequest(seconds: forward ? Self.playbackSeekStep : -Self.playbackSeekStep)
    }

    /// 재생 중 ↑↓로 음량 조절. 음소거 상태에서 올리면 음소거를 푼다
    func changePreviewVolume(up: Bool) {
        guard isPreviewPlaying else { return }
        let defaults = UserDefaults.standard
        let current = defaults.object(forKey: VolumeControl.volumeKey) as? Double ?? 1
        let volume = ((current + (up ? Self.volumeStep : -Self.volumeStep)) * 10).rounded() / 10
        defaults.set(min(max(volume, 0), 1), forKey: VolumeControl.volumeKey)
        if up, defaults.bool(forKey: VolumeControl.mutedKey) { defaults.set(false, forKey: VolumeControl.mutedKey) }
    }

    /// 미리보기에 재생할 수 있는 동영상·오디오 하나가 보이고 있을 때
    var canTogglePreviewPlayback: Bool {
        guard AppSettings.isPreviewEnabled, previewSelection.count == 1, let url = previewSelection.first else { return false }
        return previewPlayerURL == url
    }

    func togglePreviewPlayback() {
        guard canTogglePreviewPlayback else { return showNotice(playbackUnavailableMessage) }
        playbackToggleRequest = UUID()
    }

    var playbackUnavailableMessage: String {
        guard AppSettings.isPreviewEnabled else { return "Preview is off" }
        if previewSelection.count == 1, let url = previewSelection.first, PreviewMediaKind(url) != nil {
            return "This file can't be played in Preview"
        }
        return "Select a video or audio file to play"
    }

    func applyRenameSettings() {
        guard renameSettings.isValid else { return }
        // Apply 직전 여섯 칸은 지금 적용하는 규칙과 같아서, Back하면 이전에 적용했던 규칙을 여섯 칸에 돌려놓는다
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

    /// 파일의 등록일·수정일. 현재 폴더 밖의 Order 파일은 그때 읽는다
    func dates(of url: URL) -> FileDates {
        if let dates = fileDates[url] ?? outsideFileDates[url] { return dates }
        let dates = FolderLoader.dates(of: url)
        outsideFileDates[url] = dates
        return dates
    }

    private func refreshRename() {
        updateMediaCollection()
        let built: [(URL, (name: String, highlights: [NameHighlight]))] = appliedSettings.map { applied in
            let usesDates = applied.usesDates
            let usesMedia = applied.usesMediaMetadata
            return orderedFiles.enumerated().compactMap { index, item in
                // 촬영일을 읽는 중이면 새 이름을 만들지 않는다 (Loading…)
                if usesMedia, pendingMediaURLs.contains(item.url) { return nil }
                var dates = usesDates ? dates(of: item.url) : FileDates()
                if usesMedia { dates.taken = cachedMedia(for: item.url)?.info?.taken }
                return applied.buildNewName(for: item.name, index: index, dates: dates).map { (item.url, $0) }
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
            if isMediaPending(item.url) { continue }
            guard let name = newNames[item.url] else {
                issues.errors[item.url] = "No new name"
                continue
            }
            // 날짜를 못 찾은 조각만 있으면 빈 이름이 된다
            if name.isEmpty {
                issues.errors[item.url] = "Empty name"
            } else if name.utf8.count > Self.maxFileNameBytes {
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
        if isMediaPending(url) { return "Reading the date taken…" }
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
        Places.remember(folder)
    }

    func reload() {
        do {
            let loaded = try FolderLoader.loadWithSizes(
                folder, showHidden: showHidden, sort: sort, foldersFirst: AppSettings.sortsFoldersFirst
            )
            // items를 바꾸면 새 이름을 다시 만들므로 용량·날짜를 먼저 넣는다
            fileSizes = loaded.sizes
            fileDates = loaded.dates
            outsideFileDates = [:]
            items = loaded.items
            loadError = nil
        } catch {
            fileSizes = [:]
            fileDates = [:]
            outsideFileDates = [:]
            items = []
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
            requestNavigation(to: [url])
        }
    }

    /// 선택한 항목을 연다 (⌘O). 하나만 연다: 폴더는 그 폴더로 이동, 파일은 기본 앱으로.
    /// 여러 개를 한꺼번에 여는 실수를 막아, 여러 개면 열지 않는다 (우클릭 메뉴와 같은 규칙)
    func openSelection() {
        guard canOpenSelection, let url = previewSelection.first else { return }
        openItem(url)
    }

    var canOpenSelection: Bool { previewSelection.count == 1 }

    func openItem(_ url: URL) {
        if Self.isDirectory(url) {
            requestNavigation(to: [url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

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

    /// 대상 파일을 Select 순서에 맞춰 정렬 목록 사이에 넣는다. 이미 있는 파일은 건너뛴다.
    /// keepsSelection이 false면 Select 선택을 해제한다 (⌘→는 선택을 남겨 목록 위치를 유지한다)
    func addToOrder(keepsSelection: Bool = false) {
        let before = orderedFiles
        orderedFiles = OrderMover.insert(targetFiles, into: orderedFiles, reference: items)
        markRecentlyAdded(after: before)
        if !keepsSelection { selection = [] }
    }

    /// 모두 추가(⌥⌘→)나 빈 파일 생성 뒤 이어서 순서를 맞출 수 있도록, 추가한 파일을 선택하고 Order로 포커스를 옮긴다
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

    /// Order에 추가한 파일과 추가 회차. 잠시 깜빡여 위치를 알려주고, 회차마다 색을 바꾼다
    private(set) var recentlyAdded: [URL: Int] = [:]
    /// 다음 추가 회차. 깜빡이는 파일이 모두 사라지면 0으로 되돌려 첫 색부터 쓴다
    private var nextAddBatch = 0

    /// 빈 목록에 처음 추가할 때도 표시한다. 추가할 때마다 각각 3초 뒤 지운다
    private func markRecentlyAdded(after before: [FileItem]) {
        let existing = Set(before.map(\.url))
        let added = Set(orderedFiles.map(\.url)).subtracting(existing)
        guard !added.isEmpty else { return }
        if recentlyAdded.isEmpty { nextAddBatch = 0 }
        let batch = nextAddBatch
        nextAddBatch += 1
        for url in added { recentlyAdded[url] = batch }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            // 그 사이 다시 추가된 파일은 새 회차의 타이머가 지운다
            for url in added where self.recentlyAdded[url] == batch {
                self.recentlyAdded[url] = nil
            }
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

    /// 다른 칸에서 Select로 왔을 때. Select 선택이 없으면 Order에서 고른 파일(이 폴더에 있는 것), 없으면 첫 항목을 선택한다.
    /// (Select를 고르면 Order 선택은 지워진다)
    private func selectOnArrivingAtSelect() -> Bool {
        guard selection.isEmpty, let first = items.first else { return false }
        let matched = Set(items.map(\.url)).intersection(orderSelection)
        selection = matched.isEmpty ? [first.url] : matched
        return true
    }

    /// 다른 칸에서 Order로 왔을 때. Order 선택이 없으면 Select에서 고른 파일(Order에 있는 것), 없으면 첫 파일을 선택한다.
    /// (Order를 고르면 Select 선택은 지워진다)
    private func selectOnArrivingAtOrder() -> Bool {
        guard orderSelection.isEmpty, let first = orderedFiles.first else { return false }
        let matched = Set(orderedFiles.map(\.url)).intersection(selection)
        orderSelection = matched.isEmpty ? [first.url] : matched
        return true
    }

    /// Select에서 고른 파일 중 Order에 있는 것이 있는지 (⌘←)
    var canRemoveSelectionFromOrder: Bool {
        orderedFiles.contains { selection.contains($0.url) }
    }

    /// Select에서 고른 파일을 Order에서 뺀다 (⌘←). Select 선택은 그대로 둔다
    func removeSelectionFromOrder() {
        _ = removeFromOrder(Array(selection))
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

// MARK: - 다른 폴더로 이동 (확인 포함)

extension BrowserModel {
    /// 이동 요청. 폴더면 그 폴더, 파일이면 그 파일이 든 폴더로 가서 파일을 선택한다
    struct PendingNavigation: Identifiable {
        let id = UUID()
        let urls: [URL]
        /// 이동할 폴더
        let folder: URL
        /// Order에 놓았으면 이동한 뒤 놓은 파일을 Order에 넣는다
        let addsToOrder: Bool
    }

    /// 다른 폴더로 이동한다. Order에 파일이 있으면 이동하면서 비워지므로 확인을 받는다.
    /// 같은 폴더거나 갈 수 없으면 false
    @discardableResult
    func requestNavigation(to urls: [URL], addsToOrder: Bool = false) -> Bool {
        guard !isRunning, let first = urls.first?.standardizedFileURL,
              FileManager.default.fileExists(atPath: first.path) else { return false }
        let target = Self.isDirectory(first) ? first : first.deletingLastPathComponent()
        guard target != folder else { return false }
        renamingURL = nil
        let navigation = PendingNavigation(urls: urls, folder: target, addsToOrder: addsToOrder)
        if orderedFiles.isEmpty {
            performNavigation(navigation)
        } else {
            pendingNavigation = navigation
        }
        return true
    }

    /// Go to Folder: 경로가 있으면 이동(필요하면 확인)한다. 없는 경로면 false
    func requestGo(to path: String) -> Bool {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        UserDefaults.standard.set(url.path, forKey: AppSettings.lastGoToPathKey)
        // 지금 폴더(또는 그 안의 파일)면 이동 없이 선택만
        if !requestNavigation(to: [url]), !Self.isDirectory(url) {
            selection = Set(items.filter { $0.url.standardizedFileURL == url }.map(\.url))
        }
        return true
    }

    /// Finder 등에서 다른 폴더의 항목을 놓으면 그 위치로 이동한다.
    /// 현재 폴더의 항목이면(창 안에서 끈 것 포함) false를 돌려 원래 놓기 동작을 하게 한다
    @discardableResult
    func dropFromOutside(_ urls: [URL], addsToOrder: Bool) -> Bool {
        guard renamingURL == nil, let first = urls.first?.standardizedFileURL else { return false }
        // 현재 폴더의 항목(창 안에서 끈 하위 폴더 포함)은 이동하지 않는다. 하위 폴더는 더블클릭으로 연다
        guard !items.contains(where: { $0.url.standardizedFileURL == first }) else { return false }
        return requestNavigation(to: urls, addsToOrder: addsToOrder)
    }

    /// 확인 창에서 이동을 누르거나, Order가 비어 있어 바로 이동한다
    func performNavigation(_ drop: PendingNavigation) {
        pendingNavigation = nil
        // 클라우드 저장소(Synology Drive 등)처럼 허용 창 없이 막히는 폴더는, 사용자가 열기 창에서 직접 고르면 열 수 있다
        var target = drop.folder
        if Self.isPermissionDenied(target) {
            guard let granted = Self.askAccess(to: target) else { return }
            target = granted
        }
        guard target == drop.folder else {
            // 열기 창에서 다른 폴더를 골랐으면 그 폴더만 연다
            open(target)
            return
        }
        open(drop.folder)
        // 놓은 파일 중 이동한 폴더에 있는 파일만 쓴다 (여러 폴더가 섞이면 첫 항목의 폴더)
        let dropped = Set(drop.urls.map(\.standardizedFileURL))
        let droppedFiles = files.filter { dropped.contains($0.url.standardizedFileURL) }
        if drop.addsToOrder, !droppedFiles.isEmpty {
            let before = orderedFiles
            orderedFiles.append(contentsOf: droppedFiles)
            markRecentlyAdded(after: before)
            requestFocus(.order)
        } else {
            selection = Set(droppedFiles.map(\.url))
            requestFocus(.select)
        }
        let skipped = drop.urls.count - (Self.isDirectory(drop.urls[0].standardizedFileURL) ? 1 : droppedFiles.count)
        if skipped > 0 {
            showNotice("\(skipped) items from other folders were skipped")
        }
    }

    /// Copy To 자리에 폴더를 놓으면 복사 위치로 지정하고 Copy를 켠다. 폴더가 아니면 받지 않는다
    func dropCopyFolder(_ urls: [URL]) -> Bool {
        guard !isRunning, urls.count == 1, let url = urls.first?.standardizedFileURL, Self.isDirectory(url),
              setCopyFolder(url.path) else { return false }
        renameSettings.isCopy = true
        return true
    }

    /// 이름 칸 입력칸에 파일을 놓으면 macOS가 경로를 글자로 넣는다. 넣은 글자가 실제 경로면 그 경로를 돌려준다
    static func droppedPath(old: String, new: String) -> URL? {
        guard new.count > old.count else { return nil }
        let prefix = old.commonPrefix(with: new).count
        let suffix = String(old.dropFirst(prefix).reversed()).commonPrefix(with: String(new.dropFirst(prefix).reversed())).count
        var inserted = String(new.dropFirst(prefix).dropLast(suffix)).trimmingCharacters(in: .whitespacesAndNewlines)
        if inserted.hasPrefix("file://"), let url = URL(string: inserted) { inserted = url.path }
        // 여러 파일이면 첫 경로만 본다
        if let first = inserted.split(whereSeparator: \.isNewline).first { inserted = String(first) }
        guard inserted.hasPrefix("/"), FileManager.default.fileExists(atPath: inserted) else { return nil }
        return URL(fileURLWithPath: inserted)
    }

    /// 지금 폴더가 없어졌는지 (다른 곳에서 지우거나 옮김, 볼륨 연결 끊김)
    var isFolderMissing: Bool {
        var isDirectory: ObjCBool = false
        return !(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    /// 없어진 폴더 대신 아직 있는 가장 가까운 상위 폴더로 간다 (Order가 있으면 확인)
    func goToNearestExistingFolder() {
        var candidate = folder.deletingLastPathComponent()
        while candidate.path != "/", !FileManager.default.fileExists(atPath: candidate.path) {
            candidate = candidate.deletingLastPathComponent()
        }
        requestNavigation(to: [candidate])
    }

    /// 지금 폴더를 읽지 못했을 때(상태 바의 Allow Access…) 열기 창으로 허용을 받아 다시 연다
    func requestAccessToCurrentFolder() {
        guard let granted = Self.askAccess(to: folder) else { return }
        if granted == folder { reload() } else { requestNavigation(to: [granted]) }
    }

    /// 폴더 목록을 읽을 수 없는지. 목록을 읽는 코드(FolderLoader)로 그대로 확인한다.
    /// 막히는 이유가 개인정보 보호·클라우드 저장소 등 여러 가지라, 읽지 못하면 모두 열기 창으로 허용을 받아 본다
    static func isPermissionDenied(_ folder: URL) -> Bool {
        do {
            _ = try FolderLoader.loadWithSizes(folder, showHidden: false)
            return false
        } catch let error as NSError {
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            NSLog("[WER] Can't read %@: %@ %d / %@ %d", folder.path, error.domain, error.code,
                  underlying?.domain ?? "-", underlying?.code ?? 0)
            return true
        }
    }

    /// 그 폴더를 미리 연 열기 창을 띄워 접근 허용을 받는다. 사용자가 고른 폴더를 돌려준다 (취소하면 nil)
    static func askAccess(to folder: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Allow"
        panel.message = "macOS needs your permission to open “\(FileManager.default.displayName(atPath: folder.path))”. Click Allow to open this folder."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.standardizedFileURL
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
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

        var isRunning: Bool { if case .running = self { true } else { false } }
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
        // 촬영일을 다 읽어야 새 이름이 정해진다
        if appliedSettings?.usesMediaMetadata == true, !pendingMediaURLs.isEmpty { return false }
        return renameConflicts.order.isEmpty && nameIssues.errors.isEmpty && !makePlan().items.isEmpty
    }

    var canUndoRun: Bool { (lastRun != nil || lastEmptyFiles != nil) && !isRunning }

    /// 메뉴·버튼의 되돌리기 이름
    var undoTitle: String { lastEmptyFiles != nil ? "Undo Create Empty Files" : "Undo Last Rename" }

    /// 실행 로그 제목 줄의 되돌리기 이름
    var runLogUndoTitle: String {
        if lastEmptyFiles != nil { return "Undo Create Empty Files" }
        return lastRun?.plan.isCopy == true ? "Undo Copy" : "Undo Rename"
    }

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
        let plan = makePlan()
        let extensionChanges = plan.items.filter { $0.source.pathExtension != $0.destination.pathExtension }.count
        if extensionChanges > 0 { warnings.append("\(extensionChanges) files: extension will change") }
        runRequest = RunRequest(plan: plan, warnings: warnings)
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
        lastEmptyFiles = nil
        isRunLogUndoable = true
        let count = plan.items.count
        runLog.append(RenameLogEntry(kind: .info, message: plan.isCopy ? "Copied \(count) files" : "Renamed \(count) files"))
        // 이름만 바뀐 파일은 촬영일을 다시 읽지 않는다
        if !plan.isCopy {
            for item in plan.items { moveMediaCache(from: item.source, to: item.destination) }
        }
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
        if let created = lastEmptyFiles, !isRunning {
            undoEmptyFiles(created)
            return
        }
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
        if !record.plan.isCopy {
            for item in record.plan.items { moveMediaCache(from: item.destination, to: item.source) }
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
        case .idle where mediaProgress?.isVisible == true, .finished where mediaProgress?.isVisible == true:
            return mediaProgressText
        case .idle:
            return appliedSettings == nil ? "Apply to preview new names" : "Ready to rename"
        case .running(let done, let total, let reverting):
            return "\(reverting ? "Reverting" : "Renaming") \(done) / \(total)"
        case .finished(let message):
            return message
        }
    }
}

// MARK: - Create Empty Files

extension BrowserModel {
    /// 지금 폴더에 빈 파일을 만들 수 있는지 (메뉴·버튼)
    var canAddEmptyFiles: Bool {
        loadError == nil && !isRunning && renamingURL == nil && !isFolderMissing
    }

    /// 빈 파일을 만든 뒤 부른다. 목록을 다시 읽고, 고르면 Order 끝에 넣는다 (실제 파일을 넣을 때와 같이 선택·포커스).
    /// 결과는 이름 바꾸기처럼 실행 로그로 보여주고, 로그 제목 줄에서 바로 되돌릴 수 있다
    func finishEmptyFiles(_ created: [EmptyFilePlan.File], fill: EmptyFileSpec.Fill, elapsed: Duration, addsToOrder: Bool) {
        guard !created.isEmpty else { return }
        lastEmptyFiles = created
        lastRun = nil
        reload()
        let byPath = Dictionary(files.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        let createdFiles = created.compactMap { byPath[$0.url.standardizedFileURL.path] }
        if addsToOrder {
            let before = orderedFiles
            let ordered = Set(orderedFiles.map(\.url))
            orderedFiles.append(contentsOf: createdFiles.filter { !ordered.contains($0.url) })
            markRecentlyAdded(after: before)
            selection = []
            focusOrder(selectingAddedSince: before)
        } else {
            selection = Set(createdFiles.map(\.url))
            requestFocus(.select)
        }
        let format = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        let total = created.reduce(Int64(0)) { $0 + $1.size }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        runLog = [RenameLogEntry(kind: .info, message: "Create \(created.count) empty files (\(fill.title))")]
        runLog += created.map {
            RenameLogEntry(kind: .success, message: $0.url.lastPathComponent, detail: "\(format($0.size)) (\($0.size.formatted()) bytes)")
        }
        runLog.append(RenameLogEntry(
            kind: .info,
            message: "Created \(created.count) files (\(format(total))) in \(seconds.formatted(.number.precision(.fractionLength(1))))s"
        ))
        // 선택을 바꾸면 로그가 닫히므로 마지막에 연다
        isRunLogUndoable = true
        isShowingRunLog = true
        runState = .finished("Created \(created.count) files")
    }

    /// 만든 빈 파일을 지운다(휴지통, 안 되면 삭제). 그사이 용량이 바뀌었거나 옮겨지거나 지워진 파일은 건너뛴다
    private func undoEmptyFiles(_ created: [EmptyFilePlan.File]) {
        lastEmptyFiles = nil
        isRunLogUndoable = false
        let fileManager = FileManager.default
        var removed: Set<URL> = []
        var log = [RenameLogEntry(kind: .info, message: "Undo create empty files: \(created.count) files")]
        for file in created {
            let name = file.url.lastPathComponent
            let size = (try? file.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            guard let size else {
                log.append(RenameLogEntry(kind: .warning, message: "Skipped (moved or deleted): \(name)"))
                continue
            }
            guard Int64(size) == file.size else {
                log.append(RenameLogEntry(kind: .warning, message: "Skipped (size changed): \(name)"))
                continue
            }
            do {
                try fileManager.trashItem(at: file.url, resultingItemURL: nil)
                log.append(RenameLogEntry(kind: .revert, message: name, detail: "Moved to Trash"))
            } catch {
                // 휴지통이 없는 볼륨(NFS, SMB 등)
                do {
                    try fileManager.removeItem(at: file.url)
                    log.append(RenameLogEntry(kind: .revert, message: name, detail: "Deleted (Trash isn't available on this volume)"))
                } catch {
                    log.append(RenameLogEntry(kind: .warning, message: "Could not remove: \(name)", detail: error.localizedDescription))
                    continue
                }
            }
            removed.insert(file.url.standardizedFileURL)
        }
        orderedFiles.removeAll { removed.contains($0.url.standardizedFileURL) }
        orderSelection = orderSelection.filter { !removed.contains($0.standardizedFileURL) }
        reload()
        log.append(RenameLogEntry(kind: .info, message: "Undo finished"))
        runLog = log
        isShowingRunLog = true
        runState = .finished("Removed \(removed.count) empty files")
    }
}

// MARK: - Taken Date Collection

/// 촬영일 수집에서 파일 하나의 결과. 읽을 때의 수정일과 함께 둔다
nonisolated struct MediaCacheEntry {
    let modified: Date?
    let result: MediaReadResult
}

extension BrowserModel {
    struct MediaProgress: Equatable {
        var done = 0
        var total = 0
        /// 촬영일이 없거나 읽지 못한 파일
        var notFound = 0
        /// 금방 끝나면 깜빡이지 않도록 0.5초가 지나도 수집 중일 때만 보여준다
        var isVisible = false
        let id = UUID()
    }

    private static let mediaWorkerCount = 3
    /// 이만큼 모이면 기다리지 않고 바로 반영한다
    private static let mediaFlushBatch = 20

    var mediaProgressText: String {
        guard let progress = mediaProgress else { return "" }
        return "Reading dates \(progress.done) / \(progress.total)"
    }

    /// 촬영일 조각을 쓰고 있고, 이 파일을 아직 읽지 않았는지 (New Name에 Loading…)
    func isMediaPending(_ url: URL) -> Bool {
        appliedSettings?.usesMediaMetadata == true && pendingMediaURLs.contains(url)
    }

    /// 편집 중이거나 Apply된 규칙에 촬영일 조각이 있는지
    var needsMediaMetadata: Bool {
        renameSettings.usesMediaMetadata || appliedSettings?.usesMediaMetadata == true
    }

    /// 읽어 둔 결과. 읽은 뒤 파일이 바뀌었으면(수정일이 다르면) nil
    func cachedMedia(for url: URL) -> MediaReadResult? {
        guard let entry = mediaCache[url], entry.modified == dates(of: url).modified else { return nil }
        return entry.result
    }

    /// 파일 정보 레이어가 읽은 결과도 함께 쓴다
    func storeMedia(_ result: MediaReadResult, for url: URL) {
        storeMedia(result, for: url, modified: dates(of: url).modified)
    }

    /// 수집 조건과 Order를 보고 큐를 다시 맞춘다. 규칙·Order·실행 상태가 바뀔 때 부른다
    func updateMediaCollection() {
        guard needsMediaMetadata else { return stopMediaCollection(clearsPending: true) }
        let needed = Set(orderedFiles.map(\.url).filter {
            MediaInfoReader.kind(of: $0) != nil && cachedMedia(for: $0) == nil
        })
        if pendingMediaURLs != needed { pendingMediaURLs = needed }
        guard !needed.isEmpty else { return stopMediaCollection(clearsPending: false) }
        // 실행하는 동안은 파일 이름이 바뀌므로 읽지 않는다
        if isRunning {
            cancelMediaWorkers()
            return
        }
        mediaQueue = orderedFiles.map(\.url).filter { needed.contains($0) && !mediaInFlight.contains($0) }
        prioritizeMedia(previewSelection)
        if var progress = mediaProgress {
            let total = progress.done + needed.count
            if progress.total != total {
                progress.total = total
                mediaProgress = progress
            }
        } else {
            let progress = MediaProgress(total: needed.count)
            mediaProgress = progress
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.mediaProgress?.id == progress.id else { return }
                self.mediaProgress?.isVisible = true
            }
        }
        startMediaWorkers()
    }

    /// 미리보기에서 고른 파일을 먼저 읽는다
    private func prioritizeMedia(_ selection: Set<URL>) {
        guard selection.count == 1, let url = selection.first, let index = mediaQueue.firstIndex(of: url) else { return }
        mediaQueue.insert(mediaQueue.remove(at: index), at: 0)
    }

    private func stopMediaCollection(clearsPending: Bool) {
        cancelMediaWorkers()
        if clearsPending, !pendingMediaURLs.isEmpty { pendingMediaURLs = [] }
        if mediaProgress != nil { mediaProgress = nil }
    }

    private func cancelMediaWorkers() {
        mediaWorkers.forEach { $0.cancel() }
        mediaWorkers = []
        mediaQueue = []
        mediaInFlight = []
    }

    private func startMediaWorkers() {
        guard mediaWorkers.isEmpty, !mediaQueue.isEmpty else { return }
        mediaWorkers = (0..<Self.mediaWorkerCount).map { _ in
            Task { [weak self] in await self?.runMediaWorker() }
        }
    }

    /// 큐가 빌 때까지 하나씩 읽는다. 마지막 작업이 끝나면 남은 결과를 반영한다
    private func runMediaWorker() async {
        while !Task.isCancelled, let url = nextMediaURL() {
            let modified = dates(of: url).modified
            let result = await MediaInfoReader.readInBackground(url)
            guard !Task.isCancelled else { return }
            storeMedia(result, for: url, modified: modified)
        }
        guard !Task.isCancelled else { return }
        if mediaInFlight.isEmpty, mediaQueue.isEmpty {
            mediaWorkers = []
            flushMedia()
        }
    }

    private func nextMediaURL() -> URL? {
        while !mediaQueue.isEmpty {
            let url = mediaQueue.removeFirst()
            if pendingMediaURLs.contains(url), !mediaInFlight.contains(url), cachedMedia(for: url) == nil {
                mediaInFlight.insert(url)
                return url
            }
        }
        return nil
    }

    private func storeMedia(_ result: MediaReadResult, for url: URL, modified: Date?) {
        mediaInFlight.remove(url)
        mediaCache[url] = MediaCacheEntry(modified: modified, result: result)
        // 수집이 먼저 읽은 파일을 고르고 있으면 파일 정보에 바로 보여준다
        if previewSelection.count == 1, previewSelection.first == url, selectionMedia?.result != result {
            selectionMedia = SelectionMedia(url: url, result: result)
        }
        mediaUnflushed.insert(url)
        if mediaUnflushed.count >= Self.mediaFlushBatch {
            flushMedia()
        } else if !isMediaFlushScheduled {
            isMediaFlushScheduled = true
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.flushMedia()
            }
        }
    }

    /// 모아 둔 결과를 화면에 반영한다
    private func flushMedia() {
        isMediaFlushScheduled = false
        guard !mediaUnflushed.isEmpty else { return }
        let flushed = mediaUnflushed.intersection(pendingMediaURLs)
        mediaUnflushed = []
        guard !flushed.isEmpty else { return }
        let wasVisible = mediaProgress?.isVisible == true
        if var progress = mediaProgress {
            progress.done += flushed.count
            progress.notFound += flushed.filter { mediaCache[$0]?.result.info?.taken == nil }.count
            mediaProgress = progress
        }
        let finished = mediaProgress
        pendingMediaURLs.subtract(flushed)
        // 다 읽었으면 결과를 한 번 알린다 (금방 끝나 진행 상황을 보여주지 않았으면 알리지 않는다)
        if pendingMediaURLs.isEmpty, wasVisible, let finished {
            let notFound = finished.notFound > 0 ? " (\(finished.notFound) not found)" : ""
            showNotice("Read dates of \(finished.done) files\(notFound)")
        }
        if appliedSettings?.usesMediaMetadata == true {
            refreshRename()
        } else {
            updateMediaCollection()
        }
    }

    private func moveMediaCache(from source: URL, to destination: URL) {
        guard let entry = mediaCache.removeValue(forKey: source.standardizedFileURL) ?? mediaCache.removeValue(forKey: source)
        else { return }
        mediaCache[destination.standardizedFileURL] = entry
    }
}
