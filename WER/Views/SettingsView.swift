//
//  SettingsView.swift
//  WER
//

import SwiftUI

/// 설정 창 (WER > Settings…, ⌘,)
struct SettingsView: View {
    enum Tab: String {
        case general
        case presets
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
            PresetsSettingsView()
                .tabItem { Label("Presets", systemImage: "bookmark") }
                .tag(Tab.presets.rawValue)
        }
        // 크기 조정 가능. General은 작아지면 스크롤, Presets는 커지면 목록이 늘어난다
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    private let presetStore = PresetStore.shared
    @AppStorage(AppSettings.startupPresetKey) private var startupPresetID = RenamePreset.defaultID.uuidString
    @AppStorage(AppSettings.copyFolderNameKey) private var copyFolderName = AppSettings.builtInCopyFolderName
    @AppStorage(AppSettings.removeCopiesToTrashKey) private var removesCopiesToTrash = false
    @AppStorage(AppSettings.previewAutoplaysMediaKey) private var previewAutoplaysMedia = false
    @AppStorage(AppSettings.sortFoldersFirstKey) private var sortsFoldersFirst = true

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
            FolderSettingRow(
                title: "Copy To",
                options: Self.chosenFolderOptions,
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
            Section("Sort") {
                Toggle("Folders First", isOn: $sortsFoldersFirst)
                    .help("In Select, list folders before files in either sort order")
            }
            Section("Preview") {
                Toggle("Play Media Automatically", isOn: $previewAutoplaysMedia)
                    .help("Start videos and audio as soon as they are shown in Preview")
            }
        }
        .formStyle(.grouped)
    }

    private static let chosenFolderOptions: [(AppSettings.FolderMode, String)] = [
        (.last, "Last Chosen"), (.current, "Current Folder"), (.custom, "Specific Folder"),
    ]
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

// MARK: - Presets

/// 프리셋 등록·편집. 목록 아래에서 고른 프리셋의 칸을 바로 고치고 예시 파일 이름으로 결과를 확인한다
private struct PresetsSettingsView: View {
    private let store = PresetStore.shared
    @State private var selection: Set<RenamePreset.ID> = []

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

            Divider()

            if let id = editingID, let preset = store.presets.first(where: { $0.id == id }) {
                PresetEditor(
                    preset: preset,
                    samples: store.samples(for: id),
                    onSampleChange: { store.setSample($1, at: $0, for: id) }
                ) { store.update($0) }
            } else {
                Text(store.presets.isEmpty ? "Add a preset with +." : "Select a preset to edit.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding()
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
    let onChange: (RenamePreset) -> Void


    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TokenGridEditor(
                tokens: binding(\.tokens),
                usesSeparator: preset.usesSeparator,
                omitsLastSeparator: preset.omitsLastSeparator
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
        } else if let built = previewSettings.buildNewName(for: sample, index: orderIndex(row)) {
            if built.name == sample {
                Text("No change")
                    .foregroundStyle(.secondary)
            } else {
                // 글자 선택을 켜면 배경색이 그려지지 않아 끈다
                Text(HighlightedText.make(built.name, highlights: built.highlights))
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
