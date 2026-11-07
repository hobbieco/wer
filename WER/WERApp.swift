//
//  WERApp.swift
//  WER
//

import SwiftUI

@main
struct WERApp: App {
    // ⌘Q를 눌렀을 때 Order 작업이 있으면 확인한다
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // ⌘ 단축키를 메뉴에 먼저 보낸다 (목록이 가져가는 키, 한글 입력 상태)
        KeyEquivalentRouter.install()
        // 미리보기 재생 중에는 방향키로 10초 이동·음량 조절
        PlaybackKeyRouter.install()
        // 설정 > Preview > Start with
        AppSettings.applyPreviewStartMode()
        // 화면을 채운 창을 다른 모니터로 옮기면 그 화면에 맞게 다시 채운다
        WindowFillKeeper.install()
        // 창 탭은 쓰지 않는다 (View 메뉴의 Show Tab Bar 등을 없앤다)
        NSWindow.allowsAutomaticWindowTabbing = false
        AppSettings.migrateFolderModes()
        // Finder처럼 파일·폴더를 Services에 넘긴다. 대상은 AppDelegate가 정한다 (우클릭 메뉴에는 아직 나오지 않음, 보류 중)
        NSApplication.shared.registerServicesMenuSendTypes([.fileURL], returnTypes: [])
        #if DEBUG
        // -resetAll YES 실행 인자를 주면 저장된 상태를 모두 지우고 시작 (Debug 빌드만)
        DebugReset.performIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            FolderCommands()
            OrderCommands()
            RenameCommands()
            AboutCommands()
        }

        // 설정은 크기를 조정할 수 있도록 일반 창으로 연다. 메뉴의 Settings…(⌘,)는 AboutCommands가 바꾼다
        Window("Settings", id: SettingsView.windowID) {
            SettingsView()
        }
        // 최소 크기보다 크게 연다 (화면보다 크면 화면에 맞춘다)
        .defaultSize(width: 660, height: 820)
        .windowResizability(.contentMinSize)
        // 앱을 시작할 때 저절로 열리지 않게 한다. 열린 채로 종료(Xcode Stop 등)해도 다음 실행 때 복원하지 않는다
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
    }
}

/// ① 메뉴 > 파일. 새 창(⌘N)은 WindowGroup이 기본 제공한다.
private struct FolderCommands: Commands {
    @FocusedValue(\.browserModel) private var model
    @FocusedValue(\.resetPaneLayout) private var resetPaneLayout

    var body: some Commands {
        CommandGroup(after: .newItem) {
            // Finder처럼 ⌘O는 선택 항목 열기, 폴더 고르기는 ⇧⌘O
            Button("Open") { model?.openSelection() }
                .keyboardShortcut("o")
                .disabled(model?.canOpenSelection != true)
            Button("Open Folder…") { model?.chooseFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("Go to Folder…") { model?.isGoToFolderPresented = true }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(model == nil)
            // Order의 Move Up과 같은 키라서 Select에 포커스가 있을 때만 켠다.
            // Order에 파일이 있으면 이동하지 않고 상태 바에 안내한다
            Button("Enclosing Folder") { model?.openEnclosingFolder() }
                .keyboardShortcut(.upArrow)
                // Quick Look이 열린 동안에는 폴더를 옮기지 않는다
                .disabled(model?.shortcutPane != .select || model?.canOpenEnclosingFolder != true || QuickLook.shared.isVisible)
            Divider()
            // 업로드 용량 제한 테스트용 파일을 지금 폴더에 만든다
            Button("Create Empty Files…") { model?.isEmptyFilesPresented = true }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(model?.canAddEmptyFiles != true)
        }
        // ⌘Z는 입력칸의 실행 취소에 쓰여서 별도 단축키를 둔다
        CommandGroup(after: .undoRedo) {
            Button(model?.undoTitle ?? "Undo Last Rename") {
                if let model { Task { await model.undoRun() } }
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(model?.canUndoRun != true)
        }
        // ① 메뉴 > 보기
        CommandGroup(before: .toolbar) {
            Button("Refresh") { model?.reload() }
                .keyboardShortcut("r")
                .disabled(model == nil)
            Menu("Sort By") {
                ForEach([FileSort.natural, .lexicographic], id: \.self) { sort in
                    Toggle("\(sort.title) — \(sort.example)", isOn: Binding {
                        model?.sort == sort
                    } set: { _ in
                        model?.setSort(sort)
                    })
                }
                Divider()
                Button("Switch Sort Order") { model?.toggleSort() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
            .disabled(model == nil)
            Toggle("Show Hidden Files", isOn: Binding {
                model?.showHidden ?? false
            } set: {
                model?.showHidden = $0
            })
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(model == nil)
            // Finder처럼 ⌘Y로 Quick Look을 열고 닫는다. 열린 동안에는 Quick Look 창이 키 창이라 model이 nil일 수 있다
            Button("Quick Look") { QuickLook.shared.toggle(for: model) }
                .keyboardShortcut("y")
                .disabled(!QuickLook.shared.isVisible && (model?.previewSelection.count != 1 || model?.isPreviewPlaying == true))
            // Finder의 정보 가져오기와 같은 키. 미리보기 위에 파일 정보를 띄운다
            Button(model?.isFileInfoShown == true ? "Hide Info" : "Show Info") { model?.toggleFileInfo() }
                .keyboardShortcut("i")
                .disabled(model?.canToggleFileInfo != true)
            // 단축키는 목록의 Space
            Button("Play/Pause Preview") { model?.togglePreviewPlayback() }
                .disabled(model?.canTogglePreviewPlayback != true)
            Divider()
            // 접힌 Select 칸은 건너뛴다
            Button("Next Pane") { model?.focusNextPane() }
                .keyboardShortcut("t")
                .disabled(model == nil)
            Button("Previous Pane") { model?.focusNextPane(forward: false) }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(model == nil)
            // 창 크기 기준으로 Select : Order : Rename = 1 : 2 : 1
            Button("Reset Panel Sizes") { resetPaneLayout?() }
                .disabled(resetPaneLayout == nil)
            Divider()
        }
    }
}

/// ① 메뉴 > Order. 화살표 단축키는 입력칸의 ⌘←/⌘→/⌘↑/⌘↓(줄·문서 처음과 끝)를 가로채지 않도록
/// 해당 목록에 포커스가 있을 때만 켠다 (꺼진 메뉴 항목은 키를 가로채지 않는다)
private struct OrderCommands: Commands {
    @FocusedValue(\.browserModel) private var model

    var body: some Commands {
        CommandMenu("Order") {
            // 이어서 다른 파일을 고를 수 있도록 포커스와 선택은 Select에 그대로 둔다
            Button("Add to Order") { model?.addSelectionToOrder(keepsSelection: true) }
                .keyboardShortcut(.rightArrow)
                .disabled(model?.shortcutPane != .select || model?.hasSelectedFiles != true || model?.selectionHasFolders == true)
            // Select의 전체 파일을 Order에 넣는다 (화살표는 파일이 움직이는 방향)
            Button("Add All to Order") {
                guard let model else { return }
                let before = model.orderedFiles
                model.addAllToOrder()
                model.focusOrder(selectingAddedSince: before)
            }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!isListFocused || model?.canAddAllToOrder != true)
            // Select에서는 고른 파일 중 Order에 있는 것을 뺀다 (포커스와 선택은 Select에 그대로)
            Button("Remove from Order") {
                guard let model else { return }
                if model.shortcutPane == .select {
                    model.removeSelectionFromOrder()
                } else {
                    model.removeFromOrder()
                }
            }
                .keyboardShortcut(.leftArrow)
                .disabled(!canChangeOrderSelection && !(model?.shortcutPane == .select && model?.canRemoveSelectionFromOrder == true))
            // Order를 전부 비운다
            Button("Remove All from Order") { model?.removeAllFromOrder() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!isListFocused || model?.orderedFiles.isEmpty != false)
            Divider()
            Button("Move Up") { model?.moveOrder(by: -1) }
                .keyboardShortcut(.upArrow)
                .disabled(!canChangeOrderSelection)
            Button("Move Down") { model?.moveOrder(by: 1) }
                .keyboardShortcut(.downArrow)
                .disabled(!canChangeOrderSelection)
            Button("Move to Top") { model?.moveOrderToTop() }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!canChangeOrderSelection)
            Button("Move to Bottom") { model?.moveOrderToBottom() }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!canChangeOrderSelection)
            Divider()
            // 선택이 그대로면 한 번 더 누를 때 원래 순서로 돌아온다
            Button("Reverse") { model?.reverseOrder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled((model?.orderedFiles.count ?? 0) < 2)
            // 직접 맞춘 순서를 되돌릴 수 없어서 단축키를 두지 않는다
            Button("Reset to Select Order") { model?.resetOrder() }
                .disabled(model?.orderedFiles.isEmpty != false)
        }
    }

    /// Select나 Order 목록에 포커스가 있을 때 (입력칸의 ⌥⌘←/→를 가로채지 않도록)
    private var isListFocused: Bool {
        model?.shortcutPane == .select || model?.shortcutPane == .order
    }

    /// Order 표에 포커스가 있고 선택한 파일이 있을 때
    private var canChangeOrderSelection: Bool {
        model?.shortcutPane == .order && model?.orderSelection.isEmpty == false
    }
}

/// ① 메뉴 > Rename. ⌘1~6는 칸 종류 드롭다운, ⌘↩는 Apply
private struct RenameCommands: Commands {
    @FocusedValue(\.browserModel) private var model

    var body: some Commands {
        CommandMenu("Rename") {
            ForEach(0..<RenameSettings.tokenCount, id: \.self) { slot in
                Button("Slot \(slot + 1) Type…") { model?.requestKindMenu(slot: slot) }
                    .keyboardShortcut(KeyEquivalent(Character("\(slot + 1)")))
                    .disabled(model == nil)
            }
            Divider()
            // Select 목록에서 파일 이름을 고치는 중에는 끈다
            Button("Apply") { model?.applyRenameSettings() }
                .keyboardShortcut(.return)
                .disabled(model?.canApplyRenameSettings != true || model?.renamingURL != nil)
            Button("Back") { model?.backRenameSettings() }
                .keyboardShortcut("[")
                .disabled(model?.renameHistory.isEmpty != false)
            Divider()
            Button("Presets…") { model?.requestPresetMenu() }
                .keyboardShortcut("l")
                .disabled(model == nil)
        }
    }
}
