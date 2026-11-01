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
    // 칸 너비 비율. 처음엔 1 : 2 : 1이고 경계를 끌어 바꾼다 (Rename은 나머지)
    @SceneStorage("selectFraction") private var selectFraction = PaneLayout.defaultSelectFraction
    @SceneStorage("orderFraction") private var orderFraction = PaneLayout.defaultOrderFraction
    @State private var dragStart: PaneLayout.Widths?
    // 메뉴로 넘기는 동작의 비교용 ID (창마다 고정)
    @State private var resetActionID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            // ② 경로 정보, 선택 파일 수
            HStack {
                PathBar(url: model.folder) { model.open($0) }
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
                    if isSelectCollapsed {
                        Divider()
                    } else {
                        SplitHandle { dragSelectOrder(by: $0, total: total) } onEnded: { dragStart = nil }
                    }
                    OrderPanel(model: model)
                        .frame(width: widths.order)
                        .clipped()
                    SplitHandle { dragOrderRename(by: $0, total: total) } onEnded: { dragStart = nil }
                    RenamePanel(model: model)
                        .frame(width: widths.rename)
                        .clipped()
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
                            .help("Undo the last rename")
                    }
                }
                .frame(width: 260, alignment: .trailing)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(minWidth: PaneLayout.minWidth(isSelectCollapsed: isSelectCollapsed), minHeight: 500)
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
        .navigationTitle(model.folder.lastPathComponent)
        // open -a WER <폴더|파일>: SwiftUI가 새 창을 만들어 넘겨준다. 파일이면 상위 폴더를 열고 그 파일을 선택한다
        .onOpenURL { url in
            model.go(to: url.path)
        }
        // Order 작업이 있으면 창을 닫거나 종료할 때 확인한다
        .background(WindowCloseGuard(model: model))
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
            GoToFolderSheet(initialFolder: model.goToFolderStart) { model.go(to: $0) }
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
            selectFraction = PaneLayout.defaultSelectFraction
            orderFraction = PaneLayout.defaultOrderFraction
        })
    }

    private func paneWidths(total: CGFloat) -> PaneLayout.Widths {
        PaneLayout.widths(
            total: total,
            selectFraction: selectFraction,
            orderFraction: orderFraction,
            isSelectCollapsed: isSelectCollapsed
        )
    }

    /// Select | Order 경계를 끈다. Rename 폭은 그대로
    private func dragSelectOrder(by translation: CGFloat, total: CGFloat) {
        let start = dragStart ?? paneWidths(total: total)
        dragStart = start
        let available = PaneLayout.available(total: total)
        let pair = start.select + start.order
        let select = min(max(start.select + translation, PaneLayout.minSelect), pair - PaneLayout.minOrder)
        selectFraction = select / available
        orderFraction = (pair - select) / available
    }

    /// Order | Rename 경계를 끈다. Select 폭은 그대로
    private func dragOrderRename(by translation: CGFloat, total: CGFloat) {
        let start = dragStart ?? paneWidths(total: total)
        dragStart = start
        let pair = start.order + start.rename
        let order = min(max(start.order + translation, PaneLayout.minOrder), pair - PaneLayout.minRename)
        if isSelectCollapsed {
            // 접힌 동안은 Order가 차지하는 몫을 펼쳤을 때의 비율로 환산해 저장한다
            let rest = PaneLayout.available(total: total) - PaneLayout.collapsedWidth
            orderFraction = order / rest * (1 - selectFraction)
        } else {
            orderFraction = order / PaneLayout.available(total: total)
        }
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
            Text(loadError)
                .foregroundStyle(.red)
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
