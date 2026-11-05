//
//  ContentView.swift
//  WER
//

import SwiftUI

struct ContentView: View {
    @Environment(\.appearsActive) private var appearsActive
    @State private var model = BrowserModel()
    @AppStorage(AppSettings.sortFoldersFirstKey) private var sortsFoldersFirst = true
    @SceneStorage("isSelectCollapsed") private var isSelectCollapsed = false
    // Select와 Rename 칸 폭(pt). Order는 나머지를 갖고, 창 크기를 바꾸면 Order가 늘고 준다
    @SceneStorage("selectWidth") private var selectWidth = PaneLayout.defaultSelectWidth
    @SceneStorage("renameWidth") private var renameWidth = PaneLayout.defaultRenameWidth
    @State private var dragStart: PaneLayout.Widths?
    /// 경계를 끌기 시작할 때의 창 폭. 다른 칸이 최소라 막히면 창을 넓히는 기준
    @State private var dragStartWindowWidth: CGFloat?
    // 메뉴로 넘기는 동작의 비교용 ID (창마다 고정)
    @State private var resetActionID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            // ② 경로 정보, 선택 파일 수
            HStack {
                // Finder 사이드바처럼 자주 가는 곳 (즐겨찾기, iCloud, 볼륨, 최근 폴더)
                PlacesButton(current: model.folder) { model.requestNavigation(to: [$0]) }
                PathBar(url: model.folder) { model.requestNavigation(to: [$0]) }
                Spacer()
                Text(model.countText)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            GeometryReader { geometry in
                let total = geometry.size.width
                let widths = paneWidths(total: total)
                HStack(spacing: 0) {
                    Group {
                        if isSelectCollapsed {
                            CollapsedPanel(title: "Select") { isSelectCollapsed = false }
                        } else {
                            SelectPanel(model: model) { isSelectCollapsed = true }
                        }
                    }
                    .frame(width: widths.select)
                    .clipped()
                    // Tab 이동을 칸 안에서 먼저 돌게 칸마다 묶는다 (기본은 창 전체를 위에서 아래로)
                    .focusSection()
                    if isSelectCollapsed {
                        Divider()
                    } else {
                        SplitHandle { dragSelectOrder(by: $0, total: total) } onEnded: { endDrag() }
                    }
                    OrderPanel(model: model)
                        .frame(width: widths.order)
                        .clipped()
                        .focusSection()
                    SplitHandle { dragOrderRename(by: $0, total: total) } onEnded: { endDrag() }
                    RenamePanel(model: model)
                        .frame(width: widths.rename)
                        .clipped()
                        .focusSection()
                }
            }

            Divider()

            // ⑥ 상태 바: 1칸 파일 상태(남는 폭) | 2칸 단축키 안내(고정) | 3칸 실행 상태(고정)
            HStack(spacing: 12) {
                // 표시할 내용이 없으면 statusMessage가 빈 뷰가 되어 폭을 차지하지 않으므로, Spacer로 1칸 자리를 항상 채운다
                HStack(spacing: 0) {
                    statusMessage
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                // 긴 안내가 칸 밖으로 넓어지지 않도록 고정 폭에서 자른다
                NoticeTicker(text: model.notice)
                    .frame(width: 360, alignment: .leading)
                    .clipped()
                HStack(spacing: 6) {
                    // 이름 바꾸기는 파일 개수, 복사는 용량 기준. 되돌리는 중에는 주황색
                    if model.isRunning && model.isRunProgressVisible {
                        ProgressView(value: model.runProgress)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .tint(model.isReverting ? .orange : .accentColor)
                            .frame(width: 100)
                    }
                    Text(model.runStatusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if model.canUndoRun {
                        Button("Undo", systemImage: "arrow.uturn.backward") { Task { await model.undoRun() } }
                            .buttonStyle(.borderless)
                            .fixedSize()
                            .help(model.undoTitle)
                    }
                }
                .frame(width: 260, alignment: .trailing)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(minWidth: PaneLayout.minWidth(isSelectCollapsed: isSelectCollapsed), minHeight: PaneLayout.minHeight)
        .onChange(of: isSelectCollapsed, initial: true) { model.isSelectCollapsed = isSelectCollapsed }
        // 설정에서 폴더 먼저 정렬을 바꾸면 바로 다시 정렬한다
        .onChange(of: sortsFoldersFirst) { model.reload() }
        // 단축키 안내를 받을 창. 설정 창 등 다른 창이 앞에 오면 해제한다
        .onChange(of: appearsActive, initial: true) { wasActive, _ in
            if appearsActive {
                BrowserModel.active = model
                // Finder 등에서 파일을 바꾸고 돌아오면 목록과 중복 검사(복사 위치 포함)를 다시 읽는다
                if !wasActive, !model.isRunning, model.renamingURL == nil { model.reload() }
            } else if BrowserModel.active === model {
                BrowserModel.active = nil
            }
        }
        // Finder에서 폴더·파일을 창 어디에 놓아도 그 위치로 이동한다 (Select·Order·Copy To는 각자 먼저 처리한다)
        .dropDestination(for: URL.self) { urls, _ in
            model.dropFromOutside(urls, addsToOrder: false)
        }
        .navigationTitle(model.folder.lastPathComponent)
        // open -a WER <폴더|파일>: SwiftUI가 새 창을 만들어 넘겨준다. 파일이면 상위 폴더를 열고 그 파일을 선택한다
        .onOpenURL { url in
            model.go(to: url.path)
        }
        // Order 작업이 있으면 창을 닫거나 종료할 때 확인한다
        .background(WindowCloseGuard(model: model))
        // Quick Look이 열려 있으면 목록 선택을 따라간다
        .onChange(of: model.previewSelection) { QuickLook.shared.selectionChanged(in: model) }
        .onAppear { BrowserModel.open.add(model) }
        .onDisappear { BrowserModel.open.remove(model) }
        // 이전 실행이 중간에 끊겼으면 복구할지 묻는다
        .onAppear { model.checkInterruptedRun() }
        .alert(
            "Previous rename was interrupted",
            isPresented: Binding { model.pendingRecovery != nil } set: { if !$0 { model.pendingRecovery = nil } }
        ) {
            Button("Restore Original Names") { model.recoverInterruptedRun() }
            Button("Ignore", role: .cancel) { RenameJournal.clear() }
        } message: {
            if let journal = model.pendingRecovery {
                Text(journal.isCopy
                    ? "\(journal.entries.count) files were being copied. Restoring removes the partial copies (originals are kept)."
                    : "\(journal.entries.count) files were being renamed. Some may have temporary names (.wer-tmp-…).")
            }
        }
        // Finder에서 다른 폴더의 항목을 놓았는데 Order에 파일이 있으면 비워도 되는지 묻는다
        .alert(
            "Go to “\(model.pendingNavigation?.folder.lastPathComponent ?? "")”?",
            isPresented: Binding { model.pendingNavigation != nil } set: { if !$0 { model.pendingNavigation = nil } },
            presenting: model.pendingNavigation
        ) { drop in
            Button("Go") { model.performNavigation(drop) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Order has \(model.orderedFiles.count) files. Going to another folder clears Order (files are not changed).")
        }
        // 실행 확인 (항상)
        .alert(
            runAlertTitle,
            isPresented: Binding { model.runRequest != nil } set: { if !$0 { model.runRequest = nil } },
            presenting: model.runRequest
        ) { request in
            Button(request.plan.isCopy ? "Copy" : "Rename") {
                Task { await model.performRun(request.plan) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(runAlertMessage(request))
        }
        .sheet(isPresented: $model.isGoToFolderPresented) {
            GoToFolderSheet(initialFolder: model.goToFolderStart) { model.requestGo(to: $0) }
        }
        .sheet(isPresented: $model.isEmptyFilesPresented) {
            EmptyFilesSheet(model: model)
        }
        .sheet(isPresented: $model.isCopyFolderPresented) {
            GoToFolderSheet(
                title: "Copy To",
                confirmTitle: "Choose",
                initialFolder: model.copyToStart,
                showsNewFolder: true
            ) { model.setCopyFolder($0) }
        }
        .focusedSceneValue(\.browserModel, model)
        .focusedSceneValue(\.resetPaneLayout, SceneAction(id: resetActionID) {
            selectWidth = PaneLayout.defaultSelectWidth
            renameWidth = PaneLayout.defaultRenameWidth
        })
    }

    private func paneWidths(total: CGFloat) -> PaneLayout.Widths {
        PaneLayout.widths(
            total: total,
            selectWidth: selectWidth,
            renameWidth: renameWidth,
            isSelectCollapsed: isSelectCollapsed
        )
    }

    private func beginDrag(total: CGFloat) {
        guard dragStart == nil else { return }
        dragStart = paneWidths(total: total)
        dragStartWindowWidth = NSApp.keyWindow?.frame.width
    }

    private func endDrag() {
        dragStart = nil
        dragStartWindowWidth = nil
    }

    /// 경계를 끌다가 다른 칸이 최소라 막히면 모자란 만큼 창을 오른쪽으로 넓힌다 (화면 끝까지).
    /// 다시 되돌려 끌면 끌기 시작할 때의 창 폭까지 줄어든다. 실제로 넓힌 폭을 돌려준다
    private func growWindow(by overflow: CGFloat) -> CGFloat {
        guard let window = NSApp.keyWindow, let startWidth = dragStartWindowWidth else { return 0 }
        let maxWidth = (window.screen?.visibleFrame.maxX ?? .greatestFiniteMagnitude) - window.frame.minX
        let target = max(min(startWidth + overflow, maxWidth), startWidth)
        if abs(window.frame.width - target) > 0.5 {
            var frame = window.frame
            frame.size.width = target
            window.setFrame(frame, display: true)
        }
        return target - startWidth
    }

    /// Select | Order 경계를 끈다. Rename 폭은 그대로. Order가 최소면 창을 넓힌다 (Order는 나머지라 저절로 맞는다)
    private func dragSelectOrder(by translation: CGFloat, total: CGFloat) {
        beginDrag(total: total)
        guard let start = dragStart else { return }
        let pair = start.select + start.order
        let desired = max(start.select + translation, PaneLayout.minSelect)
        let grown = growWindow(by: max(0, desired - (pair - PaneLayout.minOrder)))
        selectWidth = min(desired, pair + grown - PaneLayout.minOrder)
    }

    /// Order | Rename 경계를 끈다. Select 폭은 그대로. Rename이 최소면 창을 넓혀 Order를 키운다
    private func dragOrderRename(by translation: CGFloat, total: CGFloat) {
        beginDrag(total: total)
        guard let start = dragStart else { return }
        let pair = start.order + start.rename
        let desiredRename = start.rename - translation
        _ = growWindow(by: max(0, PaneLayout.minRename - desiredRename))
        renameWidth = min(max(desiredRename, PaneLayout.minRename), pair - PaneLayout.minOrder)
    }
}

extension ContentView {
    private var runAlertTitle: String {
        guard let request = model.runRequest else { return "" }
        let count = request.plan.items.count
        return request.plan.isCopy ? "Copy \(count) files?" : "Rename \(count) files?"
    }

    private func runAlertMessage(_ request: BrowserModel.RunRequest) -> String {
        var lines: [String] = []
        if case .copy(let destination) = request.plan.mode {
            lines.append("To: \((destination.path as NSString).abbreviatingWithTildeInPath)")
        }
        if !request.warnings.isEmpty {
            lines.append("Warnings:")
            lines += request.warnings.map { "• " + $0 }
        }
        lines.append("If any file fails, all changes are reverted.")
        return lines.joined(separator: "\n")
    }

    /// 상태 바 1칸. 오류 > 문제 목록 > 정상(녹색) 순. Apply 전에는 비운다
    @ViewBuilder
    private var statusMessage: some View {
        if let loadError = model.loadError {
            HStack(spacing: 8) {
                if model.isFolderMissing {
                    // 폴더가 없어졌으면 허용이 아니라 상위 폴더로 갈 수 있게 한다
                    Text("Folder not found: \(model.folder.lastPathComponent)")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    Button("Go to Enclosing Folder") { model.goToNearestExistingFolder() }
                        .controlSize(.small)
                        .help("Go to the nearest folder above that still exists")
                } else {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    // 클라우드 저장소처럼 허용 창 없이 막히는 폴더는 열기 창에서 직접 고르면 열린다
                    Button("Allow Access…") { model.requestAccessToCurrentFolder() }
                        .controlSize(.small)
                        .help("Choose this folder in the Open dialog to give WER access")
                }
            }
        } else if !conflictText.isEmpty || !noMatchText.isEmpty {
            HStack(spacing: 8) {
                if !conflictText.isEmpty {
                    Text(conflictText).foregroundStyle(.red)
                }
                if !noMatchText.isEmpty {
                    Text(noMatchText).foregroundStyle(.orange)
                }
            }
        } else if let ready = model.readyCount, ready > 0 {
            Label("\(ready) files ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var conflictText: String {
        let conflicts = model.renameConflicts
        var messages: [String] = []
        if model.appliedSettings?.isCopy == true {
            if conflicts.duplicateCount > 0 { messages.append("\(conflicts.duplicateCount) files name conflict") }
            if conflicts.existingInCopyFolder > 0 {
                messages.append("\(conflicts.existingInCopyFolder) files already exist in copy folder")
            }
        } else if !conflicts.order.isEmpty {
            messages.append("\(conflicts.order.count) files name conflict")
        }
        let invalid = model.nameIssues.errors.count
        if invalid > 0 { messages.append("\(invalid) files invalid name") }
        return messages.joined(separator: " · ")
    }

    private var noMatchText: String {
        var messages: [String] = []
        if !model.regexMisses.isEmpty { messages.append("\(model.regexMisses.count) files no match") }
        if !model.nameIssues.warnings.isEmpty { messages.append("\(model.nameIssues.warnings.count) files hidden name") }
        return messages.joined(separator: " · ")
    }
}

extension FocusedValues {
    @Entry var browserModel: BrowserModel?
    @Entry var resetPaneLayout: SceneAction?
}

/// 메뉴에서 실행할 창 단위 동작. 클로저는 비교할 수 없어 id로 비교한다
struct SceneAction: Equatable {
    let id: UUID
    let perform: () -> Void

    func callAsFunction() { perform() }

    static func == (lhs: SceneAction, rhs: SceneAction) -> Bool {
        lhs.id == rhs.id
    }
}

#Preview {
    ContentView()
}
