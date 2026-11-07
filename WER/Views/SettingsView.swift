//
//  SettingsView.swift
//  WER
//

import SwiftUI
import UniformTypeIdentifiers

/// 설정 창 (WER > Settings…, ⌘,)
struct SettingsView: View {
    enum Tab: String {
        case general
        case display
        case copy
        case presets
        case emptyFiles
        case kitty
    }

    /// 설정 창 id. SwiftUI의 Settings 창은 크기를 조정할 수 없어서 일반 창(Window)으로 연다
    static let windowID = "settings"

    /// 선택된 탭. 다른 곳에서 바꾸고 설정 창을 열면 그 탭이 열린다 (예: Manage Presets…)
    static let selectedTabKey = "settings.selectedTab"
    @AppStorage(selectedTabKey) private var selectedTab = Tab.general.rawValue

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general.rawValue)
            DisplaySettingsView()
                .tabItem { Label("Display", systemImage: "textformat.size") }
                .tag(Tab.display.rawValue)
            CopySettingsView()
                .tabItem { Label("Copy", systemImage: "doc.on.doc") }
                .tag(Tab.copy.rawValue)
            PresetsSettingsView()
                .tabItem { Label("Presets", systemImage: "bookmark") }
                .tag(Tab.presets.rawValue)
            EmptyFilesSettingsView()
                .tabItem { Label("Empty Files", systemImage: "doc.badge.plus") }
                .tag(Tab.emptyFiles.rawValue)
            Form { KittySettingsSection() }
                .formStyle(.grouped)
                .tabItem { Label("kitty", systemImage: "terminal") }
                .tag(Tab.kitty.rawValue)
        }
        // 크기 조정 가능. 각 탭은 작아지면 스크롤. 폭은 탭 6개가 모두 보이게 (좁으면 넘친 탭이 » 버튼으로 숨는다), Presets는 커지면 목록이 늘어난다
        .frame(minWidth: 660, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    private let presetStore = PresetStore.shared
    @AppStorage(AppSettings.startupPresetKey) private var startupPresetID = RenamePreset.defaultID.uuidString

    var body: some View {
        Form {
            Section("Rename") {
                // 지워진 프리셋을 가리키면 Default로 보여준다
                Picker("Startup Preset", selection: Binding {
                    presetStore.preset(UUID(uuidString: startupPresetID))?.id.uuidString ?? RenamePreset.defaultID.uuidString
                } set: {
                    startupPresetID = $0
                }) {
                    ForEach(presetStore.presets) { preset in
                        Text(preset.name).tag(preset.id.uuidString)
                    }
                }
                .help("Loaded when a window opens")
            }
            // 앱을 시작할 때는 현재 폴더가 없어서 두 가지만 둔다
            FolderSettingRow(
                title: "Startup Folder",
                options: [(.last, "Last Folder"), (.custom, "Specific Folder")],
                defaultMode: .last,
                modeKey: AppSettings.startupModeKey,
                pathKey: AppSettings.startupPathKey,
                fallbackNote: "Falls back to the last folder, then Home"
            )
            FolderSettingRow(
                title: "Go to Folder",
                options: Self.chosenFolderOptions,
                defaultMode: AppSettings.defaultGoToMode,
                modeKey: AppSettings.goToModeKey,
                pathKey: AppSettings.goToPathKey,
                fallbackNote: "Falls back to the current folder"
            )
        }
        .formStyle(.grouped)
    }

    static let chosenFolderOptions: [(AppSettings.FolderMode, String)] = [
        (.last, "Last Chosen"), (.current, "Current Folder"), (.custom, "Specific Folder"),
    ]
}

// MARK: - Display

private struct DisplaySettingsView: View {
    @AppStorage(AppSettings.listTextSizeKey) private var listTextSize = AppSettings.ListTextSize.small
    @AppStorage(AppSettings.monospacedNamesKey) private var monospacedNames = true
    @AppStorage(AppSettings.sortFoldersFirstKey) private var sortsFoldersFirst = true
    @AppStorage(AppSettings.previewStartModeKey) private var previewStartMode = AppSettings.PreviewStartMode.last
    @AppStorage(AppSettings.showsInputGuideKey) private var showsInputGuide = true

    var body: some View {
        Form {
            Section("List") {
                Picker("Text Size", selection: $listTextSize) {
                    ForEach(AppSettings.ListTextSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .help("Text size of the Select and Order lists")
                Toggle("Monospaced Names and Fields", isOn: $monospacedNames)
                    .help("Show file names in Select and Order, and the name, pattern and path fields, in a fixed-width font so numbers line up")
            }
            Section("Sort") {
                Toggle("Folders First", isOn: $sortsFoldersFirst)
                    .help("In Select, list folders before files in either sort order")
            }
            Section("Preview") {
                Picker("Start with", selection: $previewStartMode) {
                    ForEach(AppSettings.PreviewStartMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .help("What the Preview pane shows when WER starts. Last Used keeps the eye button state. Info shows file details without opening files")
            }
            Section("Input") {
                Toggle("Show Input Guide", isOn: $showsInputGuide)
                    .help("While typing in Rename, show how to fill the field next to it. Turning it off also hides field description tooltips. Error tooltips stay")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Copy

private struct CopySettingsView: View {
    @AppStorage(AppSettings.copyFolderNameKey) private var copyFolderName = AppSettings.builtInCopyFolderName
    @AppStorage(AppSettings.removeCopiesToTrashKey) private var removesCopiesToTrash = false

    var body: some View {
        Form {
            FolderSettingRow(
                title: "Copy To",
                options: GeneralSettingsView.chosenFolderOptions,
                defaultMode: AppSettings.defaultCopyToMode,
                modeKey: AppSettings.copyToModeKey,
                pathKey: AppSettings.copyToPathKey,
                fallbackNote: "Falls back to the current folder"
            )
            Section {
                LabeledContent("Default Copy Folder Name") {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("Default Copy Folder Name", text: $copyFolderName)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(AppSettings.isValidFolderName(copyFolderName) ? Color.primary : Color.red)
                        if !AppSettings.isValidFolderName(copyFolderName) {
                            Text("Invalid name. \"\(AppSettings.builtInCopyFolderName)\" is used.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .help("Created in the original folder when Copy To is not chosen")
                Picker("Remove Copies", selection: $removesCopiesToTrash) {
                    Text("Move to Trash").tag(true)
                    Text("Delete Permanently").tag(false)
                }
                if removesCopiesToTrash {
                    // 휴지통이 없는 볼륨에서는 휴지통 이동이 안 되어 영구 삭제로 넘어간다
                    Label(
                        "Network drives (NFS, SMB, etc.) and some external volumes have no Trash. Copies there are deleted permanently.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Copy")
            } footer: {
                Text("Used when a failed copy is reverted, when undoing a copy, and when recovering an interrupted copy. Originals are never touched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// [마지막으로 고른 폴더 | 현재 폴더 | 지정 폴더] 선택과 지정 폴더 경로
private struct FolderSettingRow: View {
    let title: String
    let options: [(AppSettings.FolderMode, String)]
    let fallbackNote: String

    @AppStorage private var mode: String
    @AppStorage private var path: String
    @State private var isChoosing = false

    init(
        title: String, options: [(AppSettings.FolderMode, String)], defaultMode: AppSettings.FolderMode,
        modeKey: String, pathKey: String, fallbackNote: String
    ) {
        self.title = title
        self.options = options
        self.fallbackNote = fallbackNote
        _mode = AppStorage(wrappedValue: defaultMode.rawValue, modeKey)
        _path = AppStorage(wrappedValue: "", pathKey)
    }

    private var isCustom: Bool { mode == AppSettings.FolderMode.custom.rawValue }

    var body: some View {
        Section(title) {
            Picker("Start at", selection: $mode) {
                ForEach(options, id: \.0) { option, label in
                    Text(label).tag(option.rawValue)
                }
            }
            if isCustom {
                HStack {
                    if !path.isEmpty, !AppSettings.isDirectory(path) {
                        // 지정한 폴더가 사라졌으면 대체 위치를 쓴다
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("Folder not found. \(fallbackNote).")
                    }
                    Text(path.isEmpty ? "Not selected" : (path as NSString).abbreviatingWithTildeInPath)
                        .foregroundStyle(path.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Choose…") { isChoosing = true }
                }
            }
        }
        .sheet(isPresented: $isChoosing) {
            GoToFolderSheet(
                title: "Choose \(title) Folder",
                confirmTitle: "Choose",
                initialFolder: AppSettings.isDirectory(path)
                    ? URL(fileURLWithPath: path)
                    : FileManager.default.homeDirectoryForCurrentUser,
                showsNewFolder: true
            ) { selected in
                let expanded = (selected as NSString).expandingTildeInPath
                guard AppSettings.isDirectory(expanded) else { return false }
                path = URL(fileURLWithPath: expanded).standardizedFileURL.path
                return true
            }
        }
    }
}

// MARK: - Empty Files

/// Create Empty Files 창을 열 때 채울 기본값. 비워 두면 창에서도 빈 칸으로 시작한다
private struct EmptyFilesSettingsView: View {
    @State private var spec = EmptyFileSpec.saved
    @FocusState private var focus: EmptyFileSpec.Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EmptyFileSpecFields(spec: $spec, focus: $focus)
            Text("Create Empty Files (⌥⌘N) starts with these values each time. Changes made there are not saved. Files are named <Name>-<size in bytes>.<Ext>. Empty fields use: Name wer-create, Max = Min (or 10), Count 1.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: spec) { spec.save() }
    }
}

// MARK: - Presets

/// 프리셋 등록·편집. 목록 아래에서 고른 프리셋의 칸을 바로 고치고 예시 파일 이름으로 결과를 확인한다
private struct PresetsSettingsView: View {
    private let store = PresetStore.shared
    @State private var selection: Set<RenamePreset.ID> = []
    /// 편집할 프리셋을 골랐을 때의 내용. Reset이 이 상태로 되돌린다
    @State private var loadedPreset: RenamePreset?
    /// 프리셋을 고르지 않았을 때 비활성으로 보여줄 빈 편집기 (높이를 유지한다)
    /// 구분자는 새 프리셋과 같게 채운다 (비우면 "Separator" 안내 글자가 잘려 보인다)
    @State private var placeholder = RenamePreset(
        name: "",
        tokens: PresetStore.shared.defaultPreset.tokens.map { NameToken(separator: $0.separator) },
        usesSeparator: true,
        omitsLastSeparator: PresetStore.shared.defaultPreset.omitsLastSeparator
    )

    /// 하나만 골랐을 때 편집한다
    private var editingID: RenamePreset.ID? {
        selection.count == 1 ? selection.first : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            list
            HStack(spacing: 4) {
                // 아이콘 높이가 달라(minus가 납작함) 버튼 크기가 달라 보이지 않게 아이콘 틀을 고정한다
                Button { selection = [store.add()] } label: { Self.iconLabel("Add", "plus") }
                // Default는 지울 수 없다
                Button { store.delete(selection); selection = [] } label: { Self.iconLabel("Delete", "minus") }
                    .disabled(selection.subtracting([RenamePreset.defaultID]).isEmpty)
                Button("Duplicate") {
                    if let id = editingID, let copy = store.duplicate(id) { selection = [copy] }
                }
                .disabled(editingID == nil)
                Spacer()
                Text("Drag to reorder. Click a name to rename.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .labelStyle(.iconOnly)
            // 목록 버튼 줄과 편집기 상자 사이 (VStack 간격 8 + 8)
            .padding(.bottom, 8)

            if let id = editingID, let preset = store.presets.first(where: { $0.id == id }) {
                PresetEditor(
                    preset: preset,
                    samples: store.samples(for: id),
                    onSampleChange: { store.setSample($1, at: $0, for: id) },
                    resetTarget: loadedPreset?.id == id ? loadedPreset : nil
                ) { store.update($0) }
            } else {
                PresetEditor(
                    preset: placeholder,
                    samples: Array(repeating: "", count: PresetStore.sampleCount),
                    onSampleChange: { _, _ in },
                    resetTarget: nil,
                    placeholderTitle: store.presets.isEmpty ? "No Presets. Add one with +"
                        : selection.count > 1 ? "\(selection.count) Presets Selected" : "No Preset Selected"
                ) { _ in }
            }
        }
        .padding()
        .onChange(of: editingID, initial: true) { _, id in
            loadedPreset = id.flatMap { id in store.presets.first { $0.id == id } }
        }
    }

    private static func iconLabel(_ title: String, _ systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: 14, height: 14)
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.presets) { preset in
                VStack(alignment: .leading, spacing: 2) {
                    if preset.isDefault {
                        // Default는 이름을 바꿀 수 없다
                        Label(preset.name, systemImage: "lock.fill")
                            .labelStyle(.titleAndIcon)
                            .help("The Default preset can't be renamed or deleted")
                    } else {
                        TextField("Name", text: nameBinding(preset))
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 4) {
                        // 빈 칸이 있는 프리셋은 불러온 뒤 채워야 한다
                        if let note = preset.needsInputNote {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help(note)
                        }
                        Text(preset.summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 2)
            }
            .onMove { store.move(from: $0, to: $1) }
        }
        .frame(minHeight: 160, maxHeight: .infinity)
    }

    private func nameBinding(_ preset: RenamePreset) -> Binding<String> {
        Binding {
            preset.name
        } set: {
            store.rename(preset.id, to: $0)
        }
    }
}

/// 고른 프리셋의 여섯 칸, 구분자 옵션, 예시 파일 이름 미리보기(최대 3줄)
private struct PresetEditor: View {
    let preset: RenamePreset
    /// 프리셋별 예시 이름. 빈 줄은 건너뛴다
    let samples: [String]
    let onSampleChange: (Int, String) -> Void
    /// 골랐을 때의 내용. 지금과 다르면 Reset으로 되돌린다 (이름은 그대로 둔다)
    let resetTarget: RenamePreset?
    /// 프리셋을 고르지 않았을 때의 제목. 있으면 편집기 전체를 비활성으로 보여준다
    var placeholderTitle: String?
    let onChange: (RenamePreset) -> Void

    @AppStorage(AppSettings.monospacedNamesKey) private var monospacedNames = true

    private var canReset: Bool {
        guard let resetTarget else { return false }
        return resetTarget.tokens != preset.tokens || resetTarget.usesSeparator != preset.usesSeparator
            || resetTarget.omitsLastSeparator != preset.omitsLastSeparator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 편집기 제목 줄. 상자 전체를 되돌리는 Reset을 함께 둔다
            HStack {
                Text(placeholderTitle ?? preset.name)
                    .font(.headline)
                    .foregroundStyle(placeholderTitle == nil ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button("Reset") {
                    guard var restored = resetTarget else { return }
                    restored.name = preset.name
                    onChange(restored)
                }
                .disabled(!canReset)
                .help("Restore the slots and separator options as they were when this preset was selected")
            }
            GroupBox {
                editor
                    .padding(6)
                    .disabled(placeholderTitle != nil)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TokenGridEditor(
                tokens: binding(\.tokens),
                usesSeparator: preset.usesSeparator,
                omitsLastSeparator: preset.omitsLastSeparator,
                showsGuidePopover: true
            )
            .textFieldStyle(.roundedBorder)

            HStack {
                Toggle("Separator", isOn: binding(\.usesSeparator))
                Toggle("Omit separator after the last slot", isOn: binding(\.omitsLastSeparator))
            }
            .toggleStyle(.checkbox)

            // 설정 창에는 실제 파일이 없어 예시 이름으로 결과를 보여준다. 줄 순서가 Order 순서라 Number가 줄마다 늘어난다
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Sample")
                    Text("Result")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(samples.indices, id: \.self) { row in
                    GridRow {
                        TextField("Sample file name", text: Binding {
                            samples[row]
                        } set: {
                            onSampleChange(row, $0)
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(AppSettings.fieldFont(monospaced: monospacedNames))
                        sampleResult(row)
                            .gridColumnAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// 줄의 Order 번호. 빈 줄은 세지 않는다
    private func orderIndex(_ row: Int) -> Int {
        samples.prefix(row).filter { !$0.isEmpty }.count
    }

    @ViewBuilder
    private func sampleResult(_ row: Int) -> some View {
        let sample = samples[row]
        if sample.isEmpty {
            Text("")
        // 샘플은 실제 파일이 아니라 날짜 조각에 지금 시각을 넣는다
        } else if let built = previewSettings.buildNewName(
            for: sample, index: orderIndex(row), dates: FileDates(created: .now, modified: .now)
        ) {
            if built.name == sample {
                Text("No change")
                    .foregroundStyle(.secondary)
            } else {
                // 글자 선택을 켜면 배경색이 그려지지 않아 끈다
                Text(HighlightedText.make(
                    built.name, highlights: built.highlights, font: AppSettings.fieldFont(monospaced: monospacedNames)
                ))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(built.name)
            }
        } else {
            Text("No name")
                .foregroundStyle(.secondary)
                .help("All slots are empty or invalid, or nothing matched")
        }
    }

    /// 프리셋을 Rename 설정으로 바꿔 예시 이름에 적용한다
    private var previewSettings: RenameSettings {
        var settings = RenameSettings()
        settings.tokens = preset.tokens
        settings.usesSeparator = preset.usesSeparator
        settings.omitsLastSeparator = preset.omitsLastSeparator
        return settings
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<RenamePreset, Value>) -> Binding<Value> {
        Binding {
            preset[keyPath: keyPath]
        } set: { newValue in
            var updated = preset
            updated[keyPath: keyPath] = newValue
            onChange(updated)
        }
    }
}

/// Select 우클릭 > Open in kitty 설정. kitty 위치, 여는 방식(기본 탭), 원격 제어 소켓, 홈 폴더로 실제 열어 보는 Test
private struct KittySettingsSection: View {
    @AppStorage(AppSettings.kittyPathKey) private var path = ""
    @AppStorage(AppSettings.kittyOpenModeKey) private var openMode = KittyLauncher.OpenMode.tab
    @AppStorage(AppSettings.kittySocketKey) private var socket = KittyLauncher.defaultSocket
    @State private var isChoosing = false
    @State private var testResult: KittyLauncher.Outcome?
    @State private var isTesting = false

    var body: some View {
        // path(AppStorage)를 읽는 화면이라 바뀌면 다시 그리며 다시 찾는다
        let location = KittyLauncher.location
        Section("kitty") {
            LabeledContent("kitty") {
                HStack {
                    Text(location.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Not found")
                        .foregroundStyle(location == nil ? Color.orange : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { isChoosing = true }
                    if !path.isEmpty {
                        Button("Reset") { path = "" }
                            .help("Use the installed kitty")
                    }
                }
            }
            .help("kitty.app or the kitty executable. Empty uses the installed kitty. Without kitty, Open in kitty isn't shown in the Select menu")
            .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.application, .unixExecutable]) { result in
                if case .success(let url) = result { path = url.path }
            }
            Picker("Open as", selection: $openMode) {
                ForEach(KittyLauncher.OpenMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .help("Open in kitty opens a new tab in the current kitty window, or a new window")
            TextField("Remote control socket", text: $socket, prompt: Text(KittyLauncher.defaultSocket))
                .help("Same as listen_on in kitty.conf")
            VStack(alignment: .leading, spacing: 2) {
                Text("Tabs need remote control. Add to kitty.conf, then restart kitty:")
                Text("allow_remote_control socket-only\nlisten_on \(socket.isEmpty ? KittyLauncher.defaultSocket : socket)")
                    .monospaced()
                    .textSelection(.enabled)
                Text("Without it, a new kitty window opens instead.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            LabeledContent("Test") {
                HStack {
                    if let testResult {
                        Text(testResult.message)
                            .foregroundStyle(testResult.isProblem ? Color.orange : Color.secondary)
                            .lineLimit(2)
                    }
                    Button("Open Home in kitty") { test() }
                        .disabled(location == nil || isTesting)
                }
            }
            .help("Opens your home folder in kitty with these settings")
        }
    }

    private func test() {
        isTesting = true
        testResult = nil
        Task {
            testResult = await KittyLauncher.open(directory: FileManager.default.homeDirectoryForCurrentUser)
            isTesting = false
        }
    }
}
