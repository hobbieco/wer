//
//  FilePanel.swift
//  WER
//

import SwiftUI

/// 파일 선택
struct SelectPanel: View {
    @Bindable var model: BrowserModel
    let onCollapse: () -> Void
    @FocusState private var isListFocused: Bool
    @State private var sortMenuAnchor = MenuAnchorBox()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(
                title: "Select", isFocused: model.focusedPane == .select, onSelect: { model.requestFocus(.select) },
                onCollapse: onCollapse,
                trailing: AnyView(
                    // 창이 열리는 버튼이라 "…"를 붙인다. 좁아져도 글자를 줄이지 않는다
                    Button("Create Empty Files…", systemImage: "doc.badge.plus") { model.isEmptyFilesPresented = true }
                        .fixedSize()
                        .help("Create Empty Files… (⌥⌘N)")
                        .disabled(!model.canAddEmptyFiles)
                )
            )
            HStack {
                Button("Go to Folder") { model.isGoToFolderPresented = true }
                    .fixedSize()
                Button("Refresh", systemImage: "arrow.clockwise") { model.reload() }
                    .labelStyle(.iconOnly)
                    .help("Refresh (⌘R)")
                // 정렬 방식 메뉴. 마우스를 올리면 현재 방식을 보여준다
                Button("Sort", systemImage: "arrow.up.arrow.down", action: showSortMenu)
                    .labelStyle(.iconOnly)
                    .background(MenuAnchor { sortMenuAnchor.view = $0 })
                    .help("Sort: \(model.sort.title) (\(model.sort.example)). ⌃⌘S switches")
                Spacer()
                // 선택이 없으면 전체 파일을 추가
                Button("Add", systemImage: "text.badge.plus") { model.addSelectionToOrder() }
                    .help("Add selected files to Order (all files if none selected). ⌘→ adds selected files, ⌥⌘→ adds all")
                    .disabled(model.files.isEmpty)
                    // 좁아져도 글자를 줄이지 않는다 (최소 폭은 PaneLayout.minSelect)
                    .fixedSize()
            }

            ScrollViewReader { proxy in
                List(selectRows, selection: $model.selection) { row in
                    Group {
                        if row.isRenaming {
                            InlineRenameField(item: row.item) { name in
                                finishRename(row.item.url, name: name)
                            }
                        } else {
                            FileRow(item: row.item, size: row.size, showsSize: true)
                        }
                    }
                        // 새 이름과 겹치는 항목은 빨간색
                        .foregroundStyle(row.isCollision ? .red : .primary)
                        // Order에서 선택한 파일은 약하게 강조
                        .softHighlight(row.isHighlighted)
                        // Order로 끌어다 놓아 위치를 지정해 추가
                        .draggable(row.item.url)
                }
                // 창을 열면 Select 목록에 포커스
                .focused($isListFocused)
                .defaultFocus($isListFocused, true)
                .onAppear { isListFocused = true }
                .onChange(of: isListFocused, initial: true) {
                    // 다른 칸에서 넘어와 선택을 정했으면 그 파일이 보이게 한다
                    guard model.setFocus(.select, isListFocused),
                          let target = model.items.first(where: { model.selection.contains($0.url) }) else { return }
                    proxy.scrollTo(target.url, anchor: .center)
                }
                .onChange(of: model.focusRequest) { _, request in
                    if request?.pane == .select { isListFocused = true }
                }
                // Finder처럼 항목 하나를 고르고 Return을 누르면 이름 바꾸기
                .onKeyPress(.return) {
                    startRename() ? .handled : .ignored
                }
                // Finder 칸 보기처럼 →는 선택한 폴더로 들어가고, ←는 상위 폴더로 나온다 (Order가 비어 있을 때만).
                // onKeyPress는 ⌘·⌥가 붙은 화살표도 받아서, 보조 키 없이 누른 경우만 처리한다
                // Quick Look이 열린 동안에는 폴더를 옮기지 않는다
                .onKeyPress(keys: [.rightArrow]) { press in
                    // 이름을 고치는 중이면 입력칸의 커서 이동
                    guard model.renamingURL == nil, press.modifiers.isDisjoint(with: Self.shortcutModifiers) else { return .ignored }
                    if QuickLook.shared.isVisible { return .handled }
                    return model.enterSelectedFolder() ? .handled : .ignored
                }
                .onKeyPress(keys: [.leftArrow]) { press in
                    guard model.renamingURL == nil, press.modifiers.isDisjoint(with: Self.shortcutModifiers) else { return .ignored }
                    if QuickLook.shared.isVisible { return .handled }
                    model.openEnclosingFolder()
                    return .handled
                }
                // Space: 미리보기 미디어 재생/일시정지 (이름을 고치는 중이면 공백 입력).
                // Quick Look이 열린 동안에는 뒤의 미리보기가 함께 재생되지 않게 무시한다
                .onKeyPress(keys: [.space]) { press in
                    guard model.renamingURL == nil, press.modifiers.isDisjoint(with: Self.shortcutModifiers) else { return .ignored }
                    if QuickLook.shared.isVisible { return .handled }
                    model.togglePreviewPlayback()
                    return .handled
                }
                .alert("Can't Rename", isPresented: Binding {
                    model.itemRenameError != nil
                } set: {
                    if !$0 { model.itemRenameError = nil }
                }) {
                    Button("OK") {}
                } message: {
                    Text(model.itemRenameError ?? "")
                }
                // 우클릭 메뉴. 빈 곳은 메뉴 없음. 대상은 우클릭한 줄이 선택 안이면 선택 전체, 밖이면 그 줄
                .contextMenu(forSelectionType: URL.self) { urls in
                    contextMenu(for: urls)
                } primaryAction: { urls in
                    // List는 Return도 기본 동작으로 보내서, 키 입력이면 이름 바꾸기를 시작한다
                    if NSApp.currentEvent?.type == .keyDown {
                        _ = startRename()
                        return
                    }
                    // 폴더 하나를 더블클릭하면 이동, 파일은 Order에 추가 (여러 개 선택했으면 선택한 파일 전체)
                    let clicked = model.items.filter { urls.contains($0.url) }
                    if clicked.count == 1, let folder = clicked.first, folder.isDirectory {
                        model.requestNavigation(to: [folder.url])
                    } else if clicked.contains(where: { !$0.isDirectory }) {
                        model.addSelectionToOrder()
                    }
                }
                // Order에서 끌어다 놓으면 Order 목록에서 제거. Finder에서 다른 폴더의 항목을 놓으면 그 위치로 이동
                .dropDestination(for: URL.self) { urls, _ in
                    _ = model.removeFromOrder(urls) || model.dropFromOutside(urls, addsToOrder: false)
                }
                .onChange(of: model.openCount) {
                    // 폴더를 열면 선택한 항목(상위 폴더로 나오면 방금 있던 폴더)으로, 선택이 없으면 맨 위로
                    if let selected = model.items.first(where: { model.selection.contains($0.url) }) {
                        proxy.scrollTo(selected.url, anchor: .center)
                    } else if let first = model.items.first {
                        proxy.scrollTo(first.url, anchor: .top)
                    }
                }
                .onChange(of: model.orderSelection) {
                    // Order 목록에서 가장 위에 있는 선택 파일 중 이 폴더에 있는 것으로 스크롤
                    let urls = Set(model.items.map(\.url))
                    guard let target = model.orderedFiles.first(where: {
                        model.orderSelection.contains($0.url) && urls.contains($0.url)
                    }) else { return }
                    withAnimation {
                        proxy.scrollTo(target.url, anchor: .center)
                    }
                }
            }
        }
        .padding(8)
    }

    private func showSortMenu() {
        guard let anchor = sortMenuAnchor.view, anchor.window != nil else { return }
        let menu = NSMenu()
        for sort in [FileSort.natural, .lexicographic] {
            let item = MenuAction.item(title: "\(sort.title) — \(sort.example)") { model.setSort(sort) }
            item.state = sort == model.sort ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(below: anchor)
    }

    /// 화살표 키에는 숫자 패드 표시가 붙어 있어서, 단축키에 쓰는 보조 키만 본다
    private static let shortcutModifiers: EventModifiers = [.command, .option, .control, .shift]

    /// 항목 하나를 골랐으면 이름 바꾸기를 시작한다
    @discardableResult
    @ViewBuilder
    private func contextMenu(for urls: Set<URL>) -> some View {
        // Select 목록 순서대로 (경로를 여러 줄로 복사할 때의 순서)
        let targets = model.items.filter { urls.contains($0.url) }
        if !targets.isEmpty {
            let _ = model.contextMenuURLs = targets.map(\.url)
            SelectContextMenu(targets: targets, model: model) { url in
                model.selection = [url]
                _ = startRename()
            }
        }
    }

    private func startRename() -> Bool {
        guard model.renamingURL == nil, model.selection.count == 1 else {
            if model.renamingURL == nil { model.explainUnavailableListKey("↩") }
            return false
        }
        model.renamingURL = model.selection.first
        return true
    }

    /// List는 행 값이 바뀌어야 행을 다시 그려서, 행에 보여줄 값을 모두 행에 담는다
    private var selectRows: [SelectListRow] {
        let collisions = model.renameConflicts.select
        return model.items.map { item in
            SelectListRow(
                item: item,
                isRenaming: model.renamingURL == item.url,
                isCollision: collisions.contains(item.url),
                isHighlighted: model.orderSelection.contains(item.url),
                size: model.fileSizes[item.url]
            )
        }
    }

    /// 이름 바꾸기를 끝내고 목록으로 포커스를 돌린다. name이 nil이면 취소
    private func finishRename(_ url: URL, name: String?) {
        guard model.renamingURL == url else { return }
        model.renamingURL = nil
        if let name { model.renameItem(url, to: name) }
        isListFocused = true
    }
}

/// Select 목록의 한 행
struct SelectListRow: Identifiable, Hashable {
    let item: FileItem
    let isRenaming: Bool
    let isCollision: Bool
    let isHighlighted: Bool
    /// 파일 용량. 폴더는 nil
    let size: Int64?

    var id: URL { item.url }
}

/// Select 목록 행의 이름 입력칸. Finder처럼 확장자를 뺀 부분을 골라 둔 채 시작한다.
/// Return이나 다른 곳을 누르면 확정, Esc는 취소 (onFinish(nil))
struct InlineRenameField: View {
    @AppStorage(AppSettings.monospacedNamesKey) private var monospacedNames = true
    @AppStorage(AppSettings.listTextSizeKey) private var textSize = AppSettings.ListTextSize.small
    let item: FileItem
    let onFinish: (String?) -> Void

    @State private var name: String
    @State private var textSelection: TextSelection?
    @State private var isFinished = false
    @State private var hasFocused = false
    @FocusState private var isFocused: Bool

    init(item: FileItem, onFinish: @escaping (String?) -> Void) {
        self.item = item
        self.onFinish = onFinish
        _name = State(initialValue: item.name)
    }

    var body: some View {
        Label {
            TextField("Name", text: $name, selection: $textSelection)
                .font(textSize.nameFont(monospaced: monospacedNames))
                .labelsHidden()
                .focused($isFocused)
                .onSubmit { finish(name) }
                .onExitCommand { finish(nil) }
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        hasFocused = true
                        textSelection = TextSelection(range: stemRange)
                    } else if hasFocused {
                        // 포커스를 받기 전에 빠지는 경우는 무시하고, 받은 뒤 다른 곳을 누르면 확정
                        finish(name)
                    }
                }
                // List 행 안의 입력칸은 SwiftUI 포커스로 포커스를 받지 못해서, AppKit 입력칸을 찾아 직접 첫 응답자로 만든다
                .task {
                    for _ in 0..<10 where !isFocused {
                        try? await Task.sleep(for: .milliseconds(30))
                        if Self.makeFirstResponder(fieldNamed: item.name) { break }
                    }
                }
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: textSize.iconSize, height: textSize.iconSize)
        }
        .listRowSeparator(.hidden)
    }

    /// 창의 목록(NSTableView) 안에서 이 이름을 가진 편집 가능한 입력칸을 찾아 첫 응답자로 만든다
    private static func makeFirstResponder(fieldNamed name: String) -> Bool {
        guard let window = NSApp.keyWindow, let root = window.contentView else { return false }
        func find(_ view: NSView, inTable: Bool) -> NSTextField? {
            let inTable = inTable || view is NSTableView
            if inTable, let field = view as? NSTextField, field.isEditable, field.stringValue == name,
               !field.isHiddenOrHasHiddenAncestor {
                return field
            }
            return view.subviews.lazy.compactMap { find($0, inTable: inTable) }.first
        }
        guard let field = find(root, inTable: false) else { return false }
        return window.makeFirstResponder(field)
    }

    /// 처음 골라 둘 부분. 파일은 마지막 "." 앞까지, 폴더와 점으로 시작하는 이름은 전체
    private var stemRange: Range<String.Index> {
        guard !item.isDirectory, let dot = name.lastIndex(of: "."), dot > name.startIndex else {
            return name.startIndex..<name.endIndex
        }
        return name.startIndex..<dot
    }

    private func finish(_ result: String?) {
        guard !isFinished else { return }
        isFinished = true
        onFinish(result)
    }
}

/// 파일 정렬. Add로 추가한 파일을 리네임 순서대로 정렬한다.
struct OrderPanel: View {
    @AppStorage(AppSettings.listTextSizeKey) private var textSize = AppSettings.ListTextSize.small
    @AppStorage(AppSettings.monospacedNamesKey) private var monospacedNames = true
    @Bindable var model: BrowserModel
    @FocusState private var isTableFocused: Bool

    private let pageStep = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelHeader(
                title: "Order", isFocused: model.focusedPane == .order, onSelect: { model.requestFocus(.order) },
                // 직접 정한 순서를 되돌려서, 자주 쓰는 이동 버튼과 떨어뜨려 둔다
                trailing: AnyView(
                    Button("Reset", systemImage: "arrow.counterclockwise") { model.resetOrder() }
                        .help("Reset to Select order")
                        .disabled(model.orderedFiles.isEmpty)
                )
            )
            HStack(spacing: 6) {
                // 선택이 없으면 목록 전체를 비운다
                Button("Remove", systemImage: "text.badge.minus") { model.removeFromOrder() }
                    .buttonStyle(.bordered)
                    .help("Remove selected files from Order (all files if none selected). ⌘← or ⌫ removes selected files, ⌥⌘← removes all")
                    .disabled(model.orderedFiles.isEmpty)
                Group {
                    orderButton("arrow.up.to.line", help: "Move to Top (⌥⌘↑)") { model.moveOrderToTop() }
                    orderButton("chevron.up.2", help: "Move Up 10") { model.moveOrder(by: -pageStep) }
                    orderButton("chevron.up", help: "Move Up (⌘↑)") { model.moveOrder(by: -1) }
                    orderButton("chevron.down", help: "Move Down (⌘↓)") { model.moveOrder(by: 1) }
                    orderButton("chevron.down.2", help: "Move Down 10") { model.moveOrder(by: pageStep) }
                    orderButton("arrow.down.to.line", help: "Move to Bottom (⌥⌘↓)") { model.moveOrderToBottom() }
                }
                .buttonStyle(.borderless)
                .disabled(model.orderSelection.isEmpty)
                // Select 버튼 줄처럼 오른쪽 끝에 붙여, 칸을 넓혀도 제목 줄의 Reset과 함께 움직인다
                Spacer(minLength: 0)
                // 두 개 이상 이어진 선택 구간마다 뒤집고, 그런 구간이 없으면 전체를 뒤집는다
                Button("Reverse", systemImage: "arrow.up.arrow.down") { model.reverseOrder() }
                    .buttonStyle(.bordered)
                    .help("Reverse each selected block (all if no block of 2 or more is selected). Press again to undo (⇧⌘R)")
                    .disabled(model.orderedFiles.count < 2)
            }

            ScrollViewReader { proxy in
                Table(of: OrderRow.self, selection: $model.orderSelection) {
                    TableColumn("Name") { row in
                        FileRow(item: row.item, highlights: row.highlights)
                            // Select에서 선택한 파일이 이미 목록에 있으면 약하게 강조
                            .softCellHighlight(row.isHighlighted)
                            .blinkCell(row.addBatch)
                    }
                    TableColumn("New Name") { row in
                        HStack(spacing: 4) {
                            // 경고 아이콘 자리는 항상 비워 둬 이름 시작 위치를 맞춘다
                            issueIcon(row)
                                .frame(width: 14)
                                .help(row.issue ?? "")
                            // Apply 전에는 비워 둔다
                            if row.isLoading {
                                Text("Loading…")
                                    .font(textSize.nameFont(monospaced: monospacedNames))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(HighlightedText.make(
                                    row.newName ?? "", highlights: row.newNameHighlights,
                                    font: textSize.nameFont(monospaced: monospacedNames)
                                ))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(row.isConflict ? .red : .primary)
                            }
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .blinkCell(row.addBatch)
                    }
                } rows: {
                    ForEach(orderRows) { row in
                        TableRow(row)
                            .draggable(row.item.url)
                    }
                    .dropDestination(for: URL.self) { index, urls in
                        // Finder에서 다른 폴더의 파일을 놓으면 그 폴더로 이동해 Order에 넣는다
                        if !model.dropFromOutside(urls, addsToOrder: true) {
                            model.dropOnOrder(urls, at: index)
                        }
                    }
                }
                .focused($isTableFocused)
                .onChange(of: isTableFocused) {
                    // 다른 칸에서 넘어와 선택을 정했으면 그 파일이 보이게 한다
                    guard model.setFocus(.order, isTableFocused),
                          let target = model.orderedFiles.first(where: { model.orderSelection.contains($0.url) }) else { return }
                    proxy.scrollTo(target.url, anchor: .center)
                }
                // Space: 미리보기 미디어 재생/일시정지 (Quick Look이 열린 동안에는 무시)
                .onKeyPress(.space) {
                    if QuickLook.shared.isVisible { return .handled }
                    model.togglePreviewPlayback()
                    return .handled
                }
                .onChange(of: model.focusRequest) { _, request in
                    if request?.pane == .order { isTableFocused = true }
                }
                // ⌫: 선택한 파일을 Order에서 뺀다 (파일은 지우지 않는다. 선택이 없으면 아무것도 하지 않는다).
                // 표는 ⌫를 자체 삭제 명령으로 처리해서 onKeyPress로는 받을 수 없다
                .onDeleteCommand {
                    guard !model.orderSelection.isEmpty else { return model.explainUnavailableListKey("⌫") }
                    model.removeFromOrder()
                }
                // 행이 없거나 마지막 행 아래에 놓으면 맨 끝에 추가
                .dropDestination(for: URL.self) { urls, _ in
                    if !model.dropFromOutside(urls, addsToOrder: true) {
                        model.dropOnOrder(urls, at: model.orderedFiles.count)
                    }
                    return true
                }
                .onChange(of: model.recentlyAdded) { old, new in
                    // 방금 추가한 파일 중 가장 위에 있는 것으로 스크롤 (깜빡임이 끝나 빠질 때는 무시)
                    let fresh: Set<URL> = Set(new.keys.filter { new[$0] != old[$0] })
                    guard let target = model.orderedFiles.first(where: { fresh.contains($0.url) }) else { return }
                    withAnimation {
                        proxy.scrollTo(target.url, anchor: .center)
                    }
                }
                .onChange(of: model.selection) {
                    // Order 목록에서 가장 위에 있는 강조 파일로 스크롤
                    guard let target = model.orderedFiles.first(where: { model.selection.contains($0.url) }) else { return }
                    withAnimation {
                        proxy.scrollTo(target.url, anchor: .center)
                    }
                }
            }
        }
        .padding(8)
    }

    /// Table은 행 값이 바뀌어야 셀을 다시 그려서, 셀에 보여줄 값을 모두 행에 담는다
    private var orderRows: [OrderRow] {
        model.orderedFiles.map { item in
            OrderRow(
                item: item,
                newName: model.newNames[item.url],
                isConflict: model.renameConflicts.order.contains(item.url) || model.nameIssues.errors[item.url] != nil,
                isNoMatch: model.regexMisses[item.url] != nil || model.nameIssues.warnings[item.url] != nil,
                issue: model.issueDescription(for: item.url),
                isLoading: model.isMediaPending(item.url),
                isHighlighted: model.selection.contains(item.url),
                highlights: model.regexHighlights[item.url] ?? [],
                newNameHighlights: model.newNameHighlights[item.url] ?? [],
                addBatch: model.recentlyAdded[item.url]
            )
        }
    }

    /// 충돌은 빨간 아이콘, 정규식 불일치는 주황 아이콘. 충돌이 우선
    @ViewBuilder
    private func issueIcon(_ row: OrderRow) -> some View {
        if row.isLoading {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        } else if row.isConflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if row.isNoMatch {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            Color.clear
        }
    }

    private func orderButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // 아이콘마다 폭이 달라 고정 프레임으로 간격을 맞춘다
            Image(systemName: symbol)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .help(help)
    }
}

/// Order 표의 한 행
struct OrderRow: Identifiable, Hashable {
    let item: FileItem
    let newName: String?
    let isConflict: Bool
    let isNoMatch: Bool
    /// 경고 아이콘에 마우스를 올렸을 때 보여줄 설명
    let issue: String?
    /// 촬영일을 읽는 중이라 새 이름이 아직 없다
    let isLoading: Bool
    let isHighlighted: Bool
    let highlights: [NameHighlight]
    let newNameHighlights: [NameHighlight]
    /// 방금 추가된 회차. 아니면 nil
    let addBatch: Int?

    var id: URL { item.url }
}

/// 접힌 패널. 세로 막대에 펼치기 버튼과 세로 제목을 보여준다.
struct CollapsedPanel: View {
    let title: String
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // 접기 버튼과 같은 크기·누르는 영역
            Button(action: onExpand) {
                Image(systemName: "chevron.right")
                    .imageScale(.large)
                    .frame(width: PanelHeader.height, height: PanelHeader.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Expand")
            .help("Expand \(title)")
            Text(title)
                .font(.headline)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(width: 20, height: 120)
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 28)
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
    }
}

/// 패널 제목. trailing은 오른쪽에 두는 버튼, onCollapse가 있으면 우측 끝에 접기 버튼을 둔다.
/// isFocused를 주면 키 입력을 받는 칸은 강조색, 나머지는 흐리게 표시한다. 제목을 누르면 onSelect(포커스 이동).
/// 버튼이 있든 없든 칸마다 제목 줄 높이가 같도록 기본 버튼 높이로 맞춘다
struct PanelHeader: View {
    let title: String
    var isFocused: Bool?
    var onSelect: (() -> Void)?
    var onCollapse: (() -> Void)?
    var trailing: AnyView?
    /// 오른쪽 끝 버튼의 오른쪽 여백
    var trailingInset = PanelHeader.trailingInset

    /// 기본(bordered) 버튼 높이
    static let height: CGFloat = 22
    /// 제목 줄 오른쪽 끝 버튼의 오른쪽 여백 기본값. 아래 줄도 오른쪽 끝에 버튼이 붙어 있어 여백 없이 맞는다
    static let trailingInset: CGFloat = 0

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(titleStyle)
                .contentShape(Rectangle())
                .onTapGesture { onSelect?() }
            Spacer()
            trailing
            if let onCollapse {
                // 아이콘을 한 단계 키우고 누르는 영역을 버튼 높이만큼 넓힌다.
                // 영역 안에서 오른쪽에 붙여 아래 줄 버튼 끝과 맞춘 위치를 유지한다
                Button(action: onCollapse) {
                    Image(systemName: "chevron.left")
                        .imageScale(.large)
                        .frame(width: Self.height, height: Self.height, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Collapse")
                .help("Collapse \(title)")
            }
        }
        .padding(.trailing, trailing != nil || onCollapse != nil ? trailingInset : 0)
        .frame(minHeight: Self.height)
    }

    private var titleStyle: AnyShapeStyle {
        switch isFocused {
        case true?: AnyShapeStyle(Color.accentColor)
        case false?: AnyShapeStyle(.secondary)
        case nil: AnyShapeStyle(.primary)
        }
    }
}

extension View {
    /// 다른 목록의 선택과 연결된 행을 일반 선택보다 옅게 강조한다
    func softHighlight(_ isOn: Bool) -> some View {
        listRowBackground(
            isOn ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.15)) : nil
        )
    }
}

extension View {
    /// 셀 배경을 깜빡인다 (방금 추가한 행 표시). 연속으로 추가하면 회차마다 색을 바꾼다
    func blinkCell(_ batch: Int?) -> some View {
        background {
            if let batch {
                BlinkPalette.color(for: batch)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
                    .phaseAnimator([0.0, 0.45]) { content, opacity in
                        content.opacity(opacity)
                    } animation: { _ in
                        .easeInOut(duration: 0.5)
                    }
                    // 회차가 바뀌면 새 색으로 처음부터 깜빡인다
                    .id(batch)
            }
        }
    }

    /// Table은 행 배경을 바꿀 수 없어 셀 배경으로 약하게 강조한다
    func softCellHighlight(_ isOn: Bool) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // 셀 안쪽 여백까지 칠하도록 배경을 바깥으로 넓힌다
                (isOn ? Color.accentColor.opacity(0.15) : .clear)
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            }
    }
}

/// 추가 회차별 깜빡임 색. 첫 회차는 노란색
enum BlinkPalette {
    static let colors: [Color] = [.yellow, .cyan, .pink, .green, .orange, .purple]

    static func color(for batch: Int) -> Color {
        colors[batch % colors.count]
    }
}

/// 정규식 조각별 강조 색. 조각 번호(0~4) 순서
enum RegexPalette {
    static let colors: [Color] = [.orange, .green, .blue, .purple, .pink, .teal]

    static func color(_ slot: Int) -> Color {
        colors[slot % colors.count]
    }
}

extension AppSettings {
    /// 이름 조각·패턴·경로를 넣는 입력칸 글꼴. 크기는 기본 그대로 두고 종류만 고정폭으로 바꾼다
    /// (목록 글자 크기를 따라가면 Rename 칸 높이·폭이 맞지 않는다)
    static func fieldFont(monospaced: Bool) -> Font {
        Font(monospaced
            ? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : NSFont.systemFont(ofSize: NSFont.systemFontSize))
    }
}

extension AppSettings.ListTextSize {
    /// 목록의 파일 이름 글꼴. 고정폭이면 AppKit 고정폭 시스템 글꼴(SF Mono)
    func nameFont(monospaced: Bool) -> Font {
        Font(monospaced
            ? NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
            : NSFont.systemFont(ofSize: pointSize))
    }
}

enum HighlightedText {
    /// highlights 위치를 조각 색 배경으로 칠한 문자열. font를 주면 문자열 자체에 넣는다
    /// (뷰의 .font 수정자는 표 칸 안의 AttributedString에 적용되지 않는 경우가 있다)
    static func make(_ string: String, highlights: [NameHighlight], font: Font? = nil) -> AttributedString {
        var text = AttributedString(string)
        if let font { text.font = font }
        let characters = text.characters
        for highlight in highlights where highlight.start + highlight.length <= characters.count {
            let lower = characters.index(characters.startIndex, offsetBy: highlight.start)
            let upper = characters.index(lower, offsetBy: highlight.length)
            text[lower..<upper].backgroundColor = RegexPalette.color(highlight.slot).opacity(0.35)
            // 날짜를 못 찾아 대신 넣은 값은 점선 밑줄로 구분한다
            if highlight.isFallback {
                text[lower..<upper].underlineStyle = Text.LineStyle(pattern: .dot, color: RegexPalette.color(highlight.slot))
            }
        }
        return text
    }
}

struct FileRow: View {
    let item: FileItem
    /// 정규식이 추출한 부분을 조각 색으로 칠한다
    var highlights: [NameHighlight] = []
    /// Select 목록만 오른쪽에 용량을 보여준다 (폴더는 Finder처럼 --)
    var size: Int64?
    var showsSize = false

    @AppStorage(AppSettings.listTextSizeKey) private var textSize = AppSettings.ListTextSize.small
    @AppStorage(AppSettings.monospacedNamesKey) private var monospacedNames = true

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(highlightedName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsSize {
                    Spacer(minLength: 0)
                    Text(size.map { $0.formatted(.byteCount(style: .file)) } ?? "--")
                        .font(.system(size: textSize.pointSize - 3))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        } icon: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: textSize.iconSize, height: textSize.iconSize)
        }
        .listRowSeparator(.hidden)
    }

    private var highlightedName: AttributedString {
        HighlightedText.make(item.name, highlights: highlights, font: textSize.nameFont(monospaced: monospacedNames))
    }
}

/// Select 목록 우클릭 메뉴. 파일을 바꾸는 동작은 Rename 하나뿐이고, 여러 개를 한꺼번에 여는 동작은 두지 않는다.
/// 단축키도 같은 규칙이다 (⌘O·⌘Y는 하나만, ⌘→는 파일만 골랐을 때만).
/// macOS Services(예: New Terminal at Folder)는 이 메뉴에도, AppKit 메뉴로 바꿔 봐도 나오지 않아 보류 중이다 (2026-11-07).
/// AppKit 메뉴에서는 Open With 앱 아이콘도 보이지 않아 SwiftUI 메뉴로 되돌렸다
private struct SelectContextMenu: View {
    let targets: [FileItem]
    let model: BrowserModel
    let rename: (URL) -> Void

    private var urls: [URL] { targets.map(\.url) }
    private var single: FileItem? { targets.count == 1 ? targets.first : nil }
    private var isFilesOnly: Bool { !targets.contains(where: \.isDirectory) }

    /// kitty를 열 폴더. 폴더 하나는 그 폴더, 파일은 그 파일들이 있는 폴더. 폴더 여러 개나 섞이면 nil
    private var kittyDirectory: URL? {
        if let single, single.isDirectory { return single.url }
        return isFilesOnly ? model.folder : nil
    }

    var body: some View {
        Button("Open") { single.map { model.openItem($0.url) } }
            .keyboardShortcut("o")
            .disabled(single == nil)
        openWithMenu
        Button("Add to Order") {
            select()
            model.addSelectionToOrder(keepsSelection: true)
        }
        .keyboardShortcut(.rightArrow)
        .disabled(!isFilesOnly)
        Button("Rename") { single.map { rename($0.url) } }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(single == nil)
        Divider()
        Button("Quick Look") {
            select()
            QuickLook.shared.toggle(for: model)
        }
        .keyboardShortcut("y")
        .disabled(single == nil || model.isPreviewPlaying)
        // 잠깐 확인하는 용도라 다 읽고 5초 뒤 닫힌다 (⌘I로 연 것은 그대로). 미리보기를 끄면 정보가 늘 보인다
        Button("Show Info") {
            select()
            model.showInfoBriefly()
        }
        .keyboardShortcut("i")
        .disabled(!AppSettings.isPreviewEnabled)
        // 파일 하나·폴더 하나·파일 여러 개만 (폴더 여러 개나 섞이면 Finder 창이 여럿 열릴 수 있다)
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            .disabled(!(single != nil || isFilesOnly))
        // kitty가 없으면 항목을 뺀다
        if KittyLauncher.location != nil {
            Button("Open in kitty") {
                guard let directory = kittyDirectory else { return }
                Task {
                    let outcome = await KittyLauncher.open(directory: directory)
                    if outcome.isProblem { model.showNotice(outcome.message) }
                }
            }
            .disabled(kittyDirectory == nil)
        }
        Divider()
        Button("Copy Name") { copy(targets.map(\.name)) }
        // Select 항목은 모두 같은 폴더 안이라 한 줄
        Button("Copy Path") { copy([model.folder.path]) }
        Button("Copy Full Path") { copy(urls.map(\.path)) }
    }

    /// 여기서 고른 동작은 우클릭한 항목을 Select에서 고른 뒤 실행한다 (Finder처럼)
    private func select() {
        model.selection = Set(urls)
    }

    private func copy(_ lines: [String]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    /// 파일 하나만. 기본 앱을 맨 위에, 그 밖에 열 수 있는 앱을 이름순으로
    @ViewBuilder
    private var openWithMenu: some View {
        if let file = single, !file.isDirectory {
            let workspace = NSWorkspace.shared
            let defaultApp = workspace.urlForApplication(toOpen: file.url)
            let others = workspace.urlsForApplications(toOpen: file.url)
                .filter { $0 != defaultApp }
                .sorted { Self.name(of: $0).localizedStandardCompare(Self.name(of: $1)) == .orderedAscending }
            Menu("Open With") {
                if let defaultApp {
                    appButton(defaultApp, file: file.url, suffix: " (default)")
                    if !others.isEmpty { Divider() }
                }
                ForEach(others, id: \.self) { appButton($0, file: file.url) }
            }
        } else {
            // 비활성 하위 메뉴는 회색으로 그려지지 않아 비활성 버튼으로 보여준다
            Button("Open With") {}
                .disabled(true)
        }
    }

    private func appButton(_ app: URL, file: URL, suffix: String = "") -> some View {
        Button {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } label: {
            Label {
                Text(Self.name(of: app) + suffix)
            } icon: {
                Image(nsImage: Self.icon(of: app))
                    .renderingMode(.original)
            }
            .labelStyle(.titleAndIcon)
        }
    }

    private static func name(of app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    /// 메뉴는 여러 크기가 든 앱 아이콘을 그리지 않는 경우가 있어, 16pt 이미지 한 장으로 다시 그린다
    private static func icon(of app: URL) -> NSImage {
        let source = NSWorkspace.shared.icon(forFile: app.path)
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }
}
