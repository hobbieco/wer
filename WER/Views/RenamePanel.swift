//
//  RenamePanel.swift
//  WER
//

import SwiftUI

/// 리네임 설정(상단 고정)과 미리보기
struct RenamePanel: View {
    @Bindable var model: BrowserModel
    private let presetStore = PresetStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isSavingPreset = false
    @State private var presetName = ""
    @State private var presetMenuAnchor = MenuAnchorBox()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PanelHeader(title: "Rename", isFocused: model.focusedPane == .rename, onSelect: { model.requestFocus(.rename) })
                presetsMenu
            }
            TokenGridEditor(
                tokens: $model.renameSettings.tokens,
                usesSeparator: model.renameSettings.usesSeparator,
                omitsLastSeparator: model.renameSettings.omitsLastSeparator,
                onFocusChange: { model.setFocus(.rename, $0) },
                kindMenuRequest: model.kindMenuRequest,
                focusRequest: model.focusRequest?.pane == .rename ? model.focusRequest?.id : nil,
                extensionCounts: RenameSettings.extensionCounts(of: model.orderedFiles.map(\.name))
            )

            HStack {
                Toggle("Separator", isOn: $model.renameSettings.usesSeparator)
                    .toggleStyle(.checkbox)
                    .help("Turn off to ignore all separators")
                Spacer()
                Button("Back", systemImage: "arrow.uturn.backward") { model.backRenameSettings() }
                    .help("Restore previously applied settings (\(model.renameHistory.count) of \(BrowserModel.renameHistoryLimit)) (⌘[)")
                    .disabled(model.renameHistory.isEmpty)
                Button("Apply") { model.applyRenameSettings() }
                    .help(applyHelp)
                    .disabled(!model.canApplyRenameSettings)
            }

            HStack {
                Toggle("Copy", isOn: $model.renameSettings.isCopy)
                    .toggleStyle(.checkbox)
                Button { model.isCopyFolderPresented = true } label: {
                    Label("Copy To…", systemImage: "folder")
                        .frame(width: actionButtonWidth)
                }
                .disabled(!model.renameSettings.isCopy)
                Spacer()
                // 확인 창을 거쳐 실행한다
                Button { model.requestRun() } label: {
                    Label("Run Rename", systemImage: "play.fill")
                        .frame(width: actionButtonWidth)
                }
                .disabled(!model.canRun)
                .help(model.canRun ? "Rename files in Order" : "Apply first, and fix files marked red")
            }
            if model.renameSettings.isCopy {
                Text(copyDestinationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(model.copyDestination.path)
            }

            Divider()

            // 실행하면 미리보기 자리에 처리 로그를 보여준다
            if model.isShowingRunLog {
                RunLogView(
                    entries: model.runLog,
                    isRunning: model.isRunning,
                    onUndo: model.isRunLogUndoable && model.canUndoRun ? { Task { await model.undoRun() } } : nil,
                    undoTitle: model.lastRun?.plan.isCopy == true ? "Undo Copy" : "Undo Rename"
                ) {
                    model.isShowingRunLog = false
                }
            } else {
                PreviewPanel(selection: model.previewSelection, playbackToggleRequest: model.playbackToggleRequest)
            }
        }
        .padding(8)
    }

    // Copy To와 Run Rename 버튼 폭을 맞춘다
    private let actionButtonWidth: CGFloat = 110

    /// 프리셋 불러오기·저장. 메뉴 버튼에 불러온 프리셋 이름을 보여주고 고쳤으면 *를 붙인다.
    /// 불러오기만 하고 Apply는 직접 누른다. ⌘L로도 열고, 창 밖으로 나가지 않게 버튼 오른쪽 끝에 맞춰 연다
    private var presetsMenu: some View {
        Button(action: showPresetMenu) {
            HStack(spacing: 4) {
                Label(presetTitle, systemImage: "bookmark")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .background(MenuAnchor { presetMenuAnchor.view = $0 })
        .fixedSize()
        .help("Load or save a preset (⌘L)")
        .onChange(of: model.presetMenuRequest) {
            // 메뉴 명령 처리 중에는 다른 메뉴를 열 수 없어서 다음 차례에 연다
            DispatchQueue.main.async { showPresetMenu() }
        }
        .alert("Save Preset", isPresented: $isSavingPreset) {
            TextField("Name", text: $presetName)
            Button("Save") { model.saveAsPreset(named: presetName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A preset with the same name is replaced.")
        }
    }

    private func showPresetMenu() {
        guard let anchor = presetMenuAnchor.view, anchor.window != nil else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for preset in presetStore.presets {
            let item = MenuAction.item(title: preset.name) { model.loadPreset(preset) }
            item.state = preset.id == model.loadedPresetID ? .on : .off
            item.toolTip = preset.summary
            // 빈 칸이 있는 프리셋은 불러온 뒤 채워야 한다
            if let note = preset.needsInputNote {
                item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: note)
                item.toolTip = note + "\n" + preset.summary
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        // 형식 오류가 있는 규칙은 저장하지 않는다. 빈 칸은 불러온 뒤 채우는 틀로 저장할 수 있다
        let formatErrors = model.renameSettings.formatErrors
        let blockedNote = formatErrors.isEmpty ? nil
            : "Fix errors first:\n" + formatErrors.map { "Slot \($0.slot + 1): \($0.message)" }.joined(separator: "\n")
        let save = MenuAction.item(title: "Save to “\(model.loadedPreset?.name ?? "")”") { model.saveToLoadedPreset() }
        save.isEnabled = model.isPresetModified && formatErrors.isEmpty
        save.toolTip = blockedNote
        menu.addItem(save)
        let saveAs = MenuAction.item(title: "Save as New Preset…") {
            presetName = ""
            isSavingPreset = true
        }
        saveAs.isEnabled = !model.renameSettings.tokens.allSatisfy { $0.kind == .none } && formatErrors.isEmpty
        saveAs.toolTip = blockedNote
        menu.addItem(saveAs)
        menu.addItem(.separator())
        menu.addItem(MenuAction.item(title: "Manage Presets…") {
            // Presets 탭을 지정하고 연다. 이미 열려 있으면 탭만 바뀐다
            UserDefaults.standard.set(SettingsView.Tab.presets.rawValue, forKey: SettingsView.selectedTabKey)
            openWindow(id: SettingsView.windowID)
        })
        menu.popUp(below: anchor, alignRight: true)
    }

    private var applyHelp: String {
        let errors = model.renameSettings.validationErrors
        guard !errors.isEmpty else { return "Show new names in Order (⌘↩)" }
        return errors.map { "Slot \($0.slot + 1): \($0.message)" }.joined(separator: "\n")
    }

    private var presetTitle: String {
        guard let preset = model.loadedPreset else { return "Load Preset" }
        return preset.name + (model.isPresetModified ? "*" : "")
    }

    private var copyDestinationText: String {
        let path = (model.copyDestination.path as NSString).abbreviatingWithTildeInPath
        return model.renameSettings.copyFolder == nil ? "\(path) (created when renaming)" : path
    }
}
