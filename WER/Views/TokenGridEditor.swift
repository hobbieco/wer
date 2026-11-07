//
//  TokenGridEditor.swift
//  WER
//

import SwiftUI

/// 이름 조각 여섯 칸 편집. Rename 칸과 설정의 프리셋 편집에서 함께 쓴다
struct TokenGridEditor: View {
    @Binding var tokens: [NameToken]
    let usesSeparator: Bool
    let omitsLastSeparator: Bool
    /// 입력칸 중 하나라도 포커스를 받거나 모두 잃을 때 부른다 (Rename 칸 제목 강조용)
    var onFocusChange: ((Bool) -> Void)?
    /// ⌘1~6 요청. 바뀌면 그 칸의 종류 드롭다운을 연다 (Rename 칸만)
    var kindMenuRequest: BrowserModel.KindMenuRequest?
    /// ⌘T로 Rename 칸에 온 요청. 바뀌면 1번 칸의 종류 드롭다운에 포커스를 준다 (입력칸은 None이면 꺼져 있어서)
    var focusRequest: UUID?
    /// Order 파일의 확장자별 개수. 확장자 규칙 줄의 구분자 자리에 일치 파일 수로 보여준다 (설정의 프리셋 편집은 nil)
    var extensionCounts: [String: Int]?
    /// 입력칸에 Finder의 파일·폴더를 놓았을 때 (Rename 칸은 그 위치로 이동, 설정은 nil이라 무시).
    /// 입력칸에는 경로가 글자로 들어가지 않게 되돌린다
    var onFileDrop: (([URL]) -> Void)?
    /// 커서가 있는 줄의 입력 안내를 올려 보낸다 (Rename 칸만. ContentView가 Order 칸 위에 그린다)
    var showsInputGuide = false
    /// 입력 안내를 손잡이에 붙인 팝오버로 띄운다 (설정의 프리셋 편집. 창 밖으로 나갈 수 있다)
    var showsGuidePopover = false
    @AppStorage(AppSettings.monospacedNamesKey) private var monospacedNames = true
    /// 끄면 입력 안내 풍선과 입력칸 설명 툴팁을 숨긴다. 오류·경고 툴팁은 남긴다
    @AppStorage(AppSettings.showsInputGuideKey) private var isInputGuideOn = true
    /// 안내할 칸. 칸 사이를 옮길 때 잠깐 비는 포커스로 풍선이 깜빡이지 않게 비울 때만 늦춘다
    @State private var guideField: FieldID?
    /// 팝오버가 스스로 닫힘 (다른 앱으로 가거나 바깥을 누름). 앱으로 돌아오거나 칸을 옮기면 다시 띄운다
    @State private var isGuidePopoverDismissed = false

    @State private var hoveredSlot: Int?
    // 손잡이를 끄는 중인 칸과 놓을 자리
    @State private var dragSource: Int?
    @State private var dropTargetSlot: Int?
    @State private var gridHeight: CGFloat = 0
    @State private var gridWidth: CGFloat = 0
    @FocusState private var focusedField: FieldID?
    @State private var menuAnchors = MenuAnchors()

    /// 입력칸 구분: 칸 id와 열(-1 종류 드롭다운, 0 값, 1 두 번째 칸, 2 구분자)
    private struct FieldID: Hashable {
        let token: NameToken.ID
        let column: Int
    }

    private static let rowSpacing: CGFloat = 6
    private static let kindWidth: CGFloat = 90
    private static let separatorWidth: CGFloat = 26
    private static let handleWidth: CGFloat = 18
    // 줄 간격(rowSpacing)과 같게. 두 칸 사이 폭 조절 손잡이도 이 폭이다
    private static let columnSpacing: CGFloat = 6
    private static let minOptionWidth: CGFloat = 64

    /// 두 번째 칸 폭. 칸이 넓어지면 첫 칸과 2:1로 함께 늘고, 최소 폭 아래로는 줄지 않는다 (첫 칸이 나머지를 갖는다)
    private var optionWidth: CGFloat {
        let available = valueAndOptionWidth
        guard let optionFraction else { return max(Self.minOptionWidth, available / 3) }
        // 끌어서 정한 비율. 칸 폭이 바뀌어도 비율대로 함께 늘고 준다
        return min(max(available * optionFraction, Self.minDraggedOptionWidth), max(available - Self.minValueWidth, Self.minDraggedOptionWidth))
    }

    /// 첫 칸과 두 번째 칸이 나눠 쓰는 폭
    private var valueAndOptionWidth: CGFloat {
        gridWidth - (Self.handleWidth + Self.kindWidth + Self.separatorWidth + Self.columnSpacing * 4)
    }

    /// 두 칸 사이를 끌어 정한 두 번째 칸 비율. nil이면 기본(2:1, 최소 64). 저장하지 않아 새 창·다시 실행하면 기본으로 시작한다
    @State private var optionFraction: CGFloat?
    /// 끌기 시작할 때의 두 번째 칸 폭
    @State private var dragStartOptionWidth: CGFloat?
    private static let minDraggedOptionWidth: CGFloat = 40
    private static let minValueWidth: CGFloat = 60

    /// 첫 칸과 두 번째 칸 사이(간격 4pt)를 끌어 폭을 나눈다. 더블클릭하면 기본 비율로 돌아간다
    private var optionResizeHandle: some View {
        Color.clear
            .frame(width: Self.columnSpacing)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStartOptionWidth ?? optionWidth
                        dragStartOptionWidth = start
                        let available = valueAndOptionWidth
                        guard available > 0 else { return }
                        // 왼쪽으로 끌면 두 번째 칸이 넓어진다
                        let width = min(max(start - drag.translation.width, Self.minDraggedOptionWidth), available - Self.minValueWidth)
                        optionFraction = width / available
                    }
                    .onEnded { _ in dragStartOptionWidth = nil }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { optionFraction = nil })
            .help(description("Drag to resize the two fields. Double-click to reset"))
    }

    /// 종류 이름을 줄인 후보. 긴 것부터, 뒷단어는 그대로 두고 앞 단어만 줄인다 (Created Date → … → Cre… Date → C… Date → Date)
    static func shortTitles(for title: String) -> [String] {
        guard let space = title.firstIndex(of: " ") else { return [title] }
        let first = title[..<space]
        let rest = title[title.index(after: space)...]
        return [title] + stride(from: first.count - 1, through: 1, by: -1).map { "\(first.prefix($0))… \(rest)" } + [String(rest)]
    }

    /// 한 줄이 차지하는 높이 (줄 높이 + 간격). 끈 거리를 줄 수로 바꾸는 데 쓴다
    private var rowPitch: CGFloat {
        guard !tokens.isEmpty, gridHeight > 0 else { return 28 }
        return (gridHeight + Self.rowSpacing) / CGFloat(tokens.count)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Self.columnSpacing, verticalSpacing: Self.rowSpacing) {
            ForEach(Array($tokens.enumerated()), id: \.element.id) { slot, $token in
                GridRow {
                    handle(slot: slot, token: token)
                    // 종류 선택. SwiftUI Picker는 글자를 가운데 정렬해 종류마다 앞 여백이 달라서,
                    // 왼쪽 정렬 버튼으로 그리고 ⌘1~6과 같은 AppKit 메뉴를 띄운다
                    Button { openKindMenu(slot: slot) } label: {
                        HStack(spacing: 4) {
                            // 좁으면 뒷단어는 그대로 두고 앞 단어를 줄인다 (예: Cre… Date)
                            ViewThatFits(in: .horizontal) {
                                ForEach(Self.shortTitles(for: Self.title(for: token.kind)), id: \.self) {
                                    Text($0).lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Separator 체크박스보다 조금 넓게. 긴 이름은 앞 단어를 줄여 보여준다
                    .frame(width: Self.kindWidth)
                    .help(Self.title(for: token.kind))
                    // 키보드 탐색 설정과 관계없이 포커스를 받는다. Space·Return으로 메뉴를 연다
                    .focusable()
                    .focused($focusedField, equals: FieldID(token: token.id, column: -1))
                    .onKeyPress(keys: [.space, .return]) { _ in
                        openKindMenu(slot: slot)
                        return .handled
                    }
                    .accessibilityLabel("Slot \(slot + 1) type")
                    .accessibilityValue(Self.title(for: token.kind))
                    // ⌘1~6 메뉴를 띄울 자리
                    .background(MenuAnchor { menuAnchors.views[token.id] = $0 })
                    // 비활성 칸은 회색 배경으로 구분한다 (None 줄 전체, 쓰지 않는 구분자)
                    let isNone = token.kind == .none
                    let isOptionDisabled = isNone || token.kind == .removeExtension || token.kind == .addExtension
                    let isSeparatorDisabled = !token.kind.isNamePart || !usesSeparator || isOmittedSeparator(slot)
                    // 형식 오류는 빨강, 빈 칸은 주황 테두리.
                    // Text 두 칸이 모두 비면 커서가 있는 칸에 표시한다 (커서가 없으면 첫 칸)
                    let isEmptyTextOnOption = token.isEmptyText && focusedField == FieldID(token: token.id, column: 1)
                    // 대상 확장자가 다른 확장자 규칙과 겹치면 첫 칸에 오류를 표시한다
                    let conflictError = extensionConflicts[slot].map(RenameSettings.conflictMessage)
                    // 예시(placeholder)는 값으로 오해해 지우려 하게 되어 두지 않는다. 형식은 도움말로 안내한다
                    TextField("", text: $token.value)
                        .font(AppSettings.fieldFont(monospaced: monospacedNames))
                        .fileDropGuard($token.value, onDrop: onFileDrop)
                        .focused($focusedField, equals: FieldID(token: token.id, column: 0))
                        .multilineTextAlignment(.center)
                        .invalidBorder(
                            (token.validationError != nil && !token.needsValue) || conflictError != nil,
                            needsInput: (token.needsValue && !isEmptyTextOnOption) || token.valueWarning != nil
                        )
                        .help(token.validationError ?? conflictError ?? token.valueWarning ?? description(Self.help(for: token.kind)))
                        .disabled(isNone)
                        .disabledBackground(isNone)
                    // 두 번째 칸: Text 뒤 문자열(비우면 무시), Number 증가 폭, Regex 채우기 모양
                    TextField("", text: $token.option)
                        .font(AppSettings.fieldFont(monospaced: monospacedNames))
                        .fileDropGuard($token.option, onDrop: onFileDrop)
                        .focused($focusedField, equals: FieldID(token: token.id, column: 1))
                        .multilineTextAlignment(.center)
                        // 첫 칸과 2:1로 늘고 줄며 최소 64. 두 칸 사이를 끌어 바꿀 수 있다 (저장하지 않음)
                        .frame(width: optionWidth)
                        .invalidBorder(
                            token.optionError != nil && !token.needsOption,
                            needsInput: token.needsOption || isEmptyTextOnOption || token.warning != nil
                        )
                        .help(token.optionError ?? (isEmptyTextOnOption ? token.validationError : nil) ?? token.warning
                            ?? description(Self.optionHelp(for: token.kind)))
                        .disabled(isOptionDisabled)
                        .disabledBackground(isOptionDisabled)
                        // 첫 칸과의 간격에 폭 조절 손잡이를 겹친다 (비활성 칸이어도 끌 수 있다)
                        .overlay(alignment: .leading) {
                            optionResizeHandle.offset(x: -Self.columnSpacing)
                        }
                    if token.kind.isExtensionRule {
                        // 확장자 규칙은 구분자를 쓰지 않아 그 자리에 Order의 일치 파일 수를 보여준다
                        extensionCountLabel(token)
                    } else {
                        TextField("Sep", text: $token.separator)
                            .font(AppSettings.fieldFont(monospaced: monospacedNames))
                            .fileDropGuard($token.separator, onDrop: onFileDrop)
                            .focused($focusedField, equals: FieldID(token: token.id, column: 2))
                            .multilineTextAlignment(.center)
                            .frame(width: Self.separatorWidth)
                            .invalidBorder(token.separatorError != nil)
                            .help(token.separatorError ?? description(isOmittedSeparator(slot) ? "Omitted after the last slot" : "Separator"))
                            .disabled(isSeparatorDisabled)
                            .disabledBackground(isSeparatorDisabled)
                    }
                }
                // 끄는 중인 칸은 흐리게
                .opacity(dragSource == slot ? 0.5 : 1)
                // 형식 오류가 있는 칸은 줄 전체를 옅은 빨간색, 빈 칸만 있으면 옅은 주황색, 끌어다 놓을 자리는 강조색으로
                .background {
                    if dropTargetSlot == slot, dragSource != slot {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.2))
                            .padding(-2)
                    } else if (token.validationError != nil && !token.needsValue) || (token.optionError != nil && !token.needsOption)
                                || token.separatorError != nil || extensionConflicts[slot] != nil {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.12))
                            .padding(-2)
                    } else if token.needsInput {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.12))
                            .padding(-2)
                    }
                }
            }
        }
        .labelsHidden()
        .onChange(of: focusedField) { _, field in
            onFocusChange?(field != nil)
            if let field {
                guideField = field
                isGuidePopoverDismissed = false
            } else {
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    if focusedField == nil { guideField = nil }
                }
            }
        }
        // 커서가 있던 칸이 비활성이 되면(None으로 바꿈 등) 포커스를 비운다
        .onChange(of: tokens) { clearDisabledFocus() }
        .onChange(of: usesSeparator) { clearDisabledFocus() }
        .onChange(of: omitsLastSeparator) { clearDisabledFocus() }
        .onChange(of: focusRequest) { _, request in
            guard request != nil, let first = tokens.first else { return }
            focusedField = FieldID(token: first.id, column: -1)
        }
        .onChange(of: kindMenuRequest) { _, request in
            if let request { openKindMenu(slot: request.slot) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isGuidePopoverDismissed = false
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { gridHeight = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    /// 줄 앞 손잡이. 칸 색을 보여주고, 끌어서 순서를 바꾸며, 우클릭하면 이동 메뉴를 연다
    private func handle(slot: Int, token: NameToken) -> some View {
        ZStack {
            // Order 표에서 이 조각을 칠하는 색 (None이어도 항상 표시)
            RoundedRectangle(cornerRadius: 4)
                .fill(RegexPalette.color(slot))
                .frame(width: 14, height: 18)
            // 평소에는 칸 번호(⌘1~6), 마우스를 올리면 끌기 표시
            if hoveredSlot == slot {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(slot + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: Self.handleWidth, height: 22)
        .anchorPreference(key: InputGuideKey.self, value: .bounds) { anchor in
            guideAnchor(slot: slot, token: token, anchor: anchor)
        }
        .popover(isPresented: guidePopoverBinding(slot: slot, token: token), arrowEdge: .leading) {
            if let field = guideInfo(slot: slot, token: token) {
                InputGuideBubble(field: field, corner: .topTrailing, isPlain: true)
                    .frame(width: 320)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                hoveredSlot = slot
                NSCursor.openHand.push()
            } else {
                if hoveredSlot == slot { hoveredSlot = nil }
                NSCursor.pop()
            }
        }
        .help("Slot \(slot + 1). ⌘\(slot + 1) opens its type menu. Drag to reorder. Right-click for more")
        // 시스템 끌어다 놓기 대신, 위아래로 끈 거리를 줄 수로 바꿔 놓을 자리를 정한다
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { drag in
                    if dragSource == nil {
                        dragSource = slot
                        NSCursor.closedHand.push()
                    }
                    let offset = Int((drag.translation.height / rowPitch).rounded())
                    dropTargetSlot = min(max(slot + offset, 0), tokens.count - 1)
                }
                .onEnded { _ in
                    if let target = dropTargetSlot {
                        moveToken(id: token.id, to: target)
                    }
                    dragSource = nil
                    dropTargetSlot = nil
                    NSCursor.pop()
                }
        )
        .contextMenu {
            Button("Move Up") { moveToken(id: token.id, to: slot - 1) }
                .disabled(slot == 0)
            Button("Move Down") { moveToken(id: token.id, to: slot + 1) }
                .disabled(slot == tokens.count - 1)
            Button("Move to Top") { moveToken(id: token.id, to: 0) }
                .disabled(slot == 0)
            Button("Move to Bottom") { moveToken(id: token.id, to: tokens.count - 1) }
                .disabled(slot == tokens.count - 1)
            Divider()
            Button("Clear") {
                tokens[slot].kind = .none
                tokens[slot].value = ""
            }
            .disabled(token.kind == .none)
        }
    }

    /// 칸의 종류 메뉴를 열고, 고른 뒤 그 칸의 값 입력칸으로 커서를 옮긴다.
    /// SwiftUI Picker는 코드로 열 수 없어서, 같은 항목의 AppKit 메뉴를 Picker 자리에 띄운다
    private func openKindMenu(slot: Int) {
        guard tokens.indices.contains(slot),
              let anchor = menuAnchors.views[tokens[slot].id], anchor.window != nil else { return }
        let tokenID = tokens[slot].id
        let menu = NSMenu()
        var current: NSMenuItem?
        // Picker와 같은 순서 (None은 구분선으로 분리)
        for kind in [
            NameToken.Kind.none, .text, .regex, .replace, .number, .createdDate, .modifiedDate, .takenDate,
            .changeExtension, .removeExtension, .addExtension,
        ] {
            let item = MenuAction.item(title: Self.title(for: kind)) {
                guard let index = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
                Self.select(kind, for: &tokens[index])
            }
            if kind == tokens[slot].kind {
                item.state = .on
                current = item
            }
            menu.addItem(item)
            if kind == .none || kind == .takenDate { menu.addItem(.separator()) }
        }
        // 메뉴 명령 처리 중에는 다른 메뉴를 열 수 없어서 다음 차례에 연다. popUp은 메뉴를 닫을 때까지 기다린다
        DispatchQueue.main.async {
            menu.popUp(positioning: current, at: NSPoint(x: 0, y: anchor.isFlipped ? 0 : anchor.bounds.height), in: anchor)
            // None이면 커서를 둘 칸이 없어서, 다른 칸에 커서가 남아 엉뚱한 칸에 입력되지 않도록 포커스를 비운다
            let field = FieldID(token: tokenID, column: 0)
            focusedField = isEnabled(field) ? field : nil
        }
    }

    /// 입력칸 설명 툴팁. 입력 안내를 끄면 숨긴다
    private func description(_ text: String) -> String {
        isInputGuideOn ? text : ""
    }

    /// 이 줄에 커서가 있으면 입력 안내 위치와 내용
    private func guideAnchor(slot: Int, token: NameToken, anchor: Anchor<CGRect>) -> InputGuideAnchor? {
        guard showsInputGuide, let field = guideInfo(slot: slot, token: token) else { return nil }
        return InputGuideAnchor(anchor: anchor, field: field)
    }

    /// 이 줄에 커서가 있으면 안내할 칸
    private func guideInfo(slot: Int, token: NameToken) -> InputGuideField? {
        guard isInputGuideOn, let field = guideField, field.token == token.id else { return nil }
        return InputGuideField(
            token: token, slot: slot, column: field.column, isOmittedSeparator: isOmittedSeparator(slot),
            conflict: extensionConflicts[slot].map(RenameSettings.conflictMessage)
        )
    }

    private func guidePopoverBinding(slot: Int, token: NameToken) -> Binding<Bool> {
        Binding {
            showsGuidePopover && !isGuidePopoverDismissed && guideInfo(slot: slot, token: token) != nil
        } set: { isShown in
            // 커서는 칸에 남아 있으므로 안내 칸은 비우지 않는다
            if !isShown, guideField?.token == token.id { isGuidePopoverDismissed = true }
        }
    }

    static func title(for kind: NameToken.Kind) -> String {
        switch kind {
        case .none: "None"
        case .text: "Text"
        case .regex: "Regex"
        case .replace: "Replace"
        case .number: "Number"
        case .changeExtension: "Change Ext"
        case .removeExtension: "Remove Ext"
        case .addExtension: "Add Ext"
        case .createdDate: "Created Date"
        case .modifiedDate: "Modified Date"
        case .takenDate: "Taken Date"
        }
    }

    /// 확장자 규칙의 Order 일치 파일 수. 0이면 주황색
    private func extensionCountLabel(_ token: NameToken) -> some View {
        // 파일 정보가 없거나(설정의 프리셋 편집) 대상이 비었거나 잘못되면 일치 파일이 없는 것으로 보고 0
        let count = token.validationError == nil
            ? token.extensionTarget.flatMap { extensionCounts?[$0] } ?? 0
            : 0
        // Add Ext는 확장자가 없는 파일 수
        let target = token.kind == .addExtension ? "no extension" : ".\(token.value)"
        let help = if extensionCounts == nil {
            token.kind == .addExtension
                ? "Number of files in Order without an extension"
                : "Number of files in Order with this extension (exact match, case-sensitive)"
        } else if count == 0 {
            token.value.isEmpty ? "Enter an extension first" : "No files with \(target) in Order"
        } else {
            "\(count) files with \(target) in Order"
        }
        // 구분자 칸과 크기·회색 배경이 같도록 비활성 입력칸 위에 숫자를 얹는다
        return TextField("", text: .constant(""))
            .disabled(true)
            .frame(width: Self.separatorWidth)
            .disabledBackground(true)
            .overlay {
                // 다른 입력칸과 같은 글꼴 (고정폭 설정을 따른다). "99+"는 칸에 맞춰 줄어든다
                Text(count > 99 ? "99+" : String(count))
                    .font(AppSettings.fieldFont(monospaced: monospacedNames))
                    .foregroundStyle(count == 0 ? Color.orange : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .help(help)
    }

    /// 칸별 확장자 대상 겹침 (칸 → 겹치는 칸)
    private var extensionConflicts: [Int: Int] {
        RenameSettings.extensionConflicts(in: tokens)
    }

    /// 사용자가 종류를 고르면 두 칸을 비운다. 채워야 하는 칸은 주황 테두리로 보인다 (자주 쓰는 값은 프리셋으로)
    private static func select(_ kind: NameToken.Kind, for token: inout NameToken) {
        guard kind != token.kind else { return }
        token.kind = kind
        token.value = ""
        token.option = ""
    }

    /// 칸을 target 위치로 옮긴다. 종류·값·구분자가 함께 움직이고 색은 위치를 따른다
    private func moveToken(id: NameToken.ID, to target: Int) {
        guard let source = tokens.firstIndex(where: { $0.id == id }),
              tokens.indices.contains(target), source != target else { return }
        tokens.insert(tokens.remove(at: source), at: target)
    }

    /// 프리셋을 불러와 종류가 바뀔 때는 값을 채우지 않도록 선택 동작에서만 select를 부른다
    private func kindBinding(_ token: Binding<NameToken>) -> Binding<NameToken.Kind> {
        Binding {
            token.wrappedValue.kind
        } set: { kind in
            Self.select(kind, for: &token.wrappedValue)
        }
    }

    private func clearDisabledFocus() {
        if let field = focusedField, !isEnabled(field) { focusedField = nil }
    }

    /// 입력칸이 켜져 있는지. 화면의 비활성 조건과 같다
    private func isEnabled(_ field: FieldID) -> Bool {
        guard let slot = tokens.firstIndex(where: { $0.id == field.token }) else { return false }
        let kind = tokens[slot].kind
        switch field.column {
        case -1: return true
        case 0: return kind != .none
        case 1: return kind != .none && kind != .removeExtension && kind != .addExtension
        default: return kind.isNamePart && usesSeparator && !isOmittedSeparator(slot)
        }
    }

    /// 마지막 칸 뒤 구분자를 빼는 옵션이면, 이름 조각인 마지막 칸의 구분자는 쓰이지 않는다
    private func isOmittedSeparator(_ slot: Int) -> Bool {
        omitsLastSeparator && slot == tokens.lastIndex { $0.kind.isNamePart }
    }

    /// 확장자 규칙은 파일마다 원래 확장자에 한 번만 적용한다. 한 규칙이 바꾼 결과를 다른 규칙이 다시 바꾸지 않는다
    private static let dateFormatNote =
        "yyyy year, MM month, dd day, HH hour, mm minute, ss second, e.g. yyyy-MM-dd or yyyyMMdd_HHmmss. Quote other letters, e.g. 'at'"

    private static let singlePassNote =
        "Each file uses at most one extension rule, on its original extension. A changed result is not changed again by another rule, e.g. a.jpeg.bak → a.jpeg"

    static func help(for kind: NameToken.Kind) -> String {
        switch kind {
        case .none: "Not used"
        case .text: "Fixed text. Either field must have a value"
        case .number: "Start number. Digits follow its length, e.g. 0001. Negative is allowed, e.g. -01"
        case .regex: "Extract from original name. First capture group, or whole match. To change or reorder parts of the name, use Replace"
        case .replace: "Find in original name (regex) and replace every match. No match: name unchanged. To pad a number, use Regex"
        case .changeExtension: "Extension to change, without dot (exact match, case-sensitive), e.g. jpeg. Order is ignored. \(Self.singlePassNote)"
        case .addExtension: "Extension to add to files without one, without dot, e.g. jpg: IMG_sample → IMG_sample.jpg. Order is ignored. \(Self.singlePassNote)"
        case .removeExtension: "Extension to remove, without dot (exact match, case-sensitive), e.g. bak: a.docx.bak → a.docx, or html for extensionless server files. Order is ignored. \(Self.singlePassNote)"
        case .createdDate: "Creation date format. \(Self.dateFormatNote)"
        case .modifiedDate: "Modification date format. \(Self.dateFormatNote)"
        case .takenDate: "Date taken, from photo EXIF or video metadata. Original photos and videos only; shared or edited files may have none. \(Self.dateFormatNote)"
        }
    }

    static func optionHelp(for kind: NameToken.Kind) -> String {
        switch kind {
        case .none: "Not used"
        case .text: "Appended to the text. Ignored if empty. Either field must have a value"
        case .number: "Step. Empty means 1, negative counts down. 0 isn't allowed"
        case .regex: "Pad on the left to this length with its character, e.g. 0000 → 0012. $2 picks group 2, $2:0000 picks and pads it. Empty: first group, no padding"
        case .replace: "Replacement. $1, $2 insert groups, $0 the whole match, \\$ a dollar sign. Empty deletes the matches"
        case .changeExtension: "New extension, without dot, e.g. jpg"
        case .removeExtension, .addExtension: "Not used"
        case .createdDate, .modifiedDate, .takenDate: "Used when the date isn't found. Empty: nothing, so the separators stay, e.g. a--b"
        }
    }
}

private extension View {
    /// 입력칸에 파일·폴더를 놓으면 경로를 글자로 넣지 않고 onDrop으로 넘긴다.
    /// SwiftUI의 놓기 처리가 먼저 받으면 그대로 넘기고, 입력칸이 먼저 경로를 넣었으면 되돌린 뒤 넘긴다
    func fileDropGuard(_ text: Binding<String>, onDrop: (([URL]) -> Void)?) -> some View {
        dropDestination(for: URL.self) { urls, _ in
            onDrop?(urls)
            return true
        }
        .onChange(of: text.wrappedValue) { old, new in
            guard let url = BrowserModel.droppedPath(old: old, new: new) else { return }
            text.wrappedValue = old
            onDrop?([url])
        }
    }

    /// 값 오류가 있는 입력칸에 빨간 테두리 (빈 값은 글자가 없어 테두리로 표시)
    /// 형식 오류는 빨간 테두리, 빈 칸(채워야 함)은 주황 테두리. 둘 다면 빨강
    func invalidBorder(_ isInvalid: Bool, needsInput: Bool = false) -> some View {
        overlay {
            if isInvalid || needsInput {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isInvalid ? Color.red : Color.orange, lineWidth: 1.5)
            }
        }
    }
}

/// 칸별 메뉴 위치 뷰. 화면을 다시 그릴 필요가 없어 관찰하지 않는 객체에 담는다
private final class MenuAnchors {
    var views: [NameToken.ID: NSView] = [:]
}

extension View {
    /// 비활성 입력칸을 회색 배경으로 덮어 활성 칸과 구분한다 (Rename 칸, Create Empty Files의 Min)
    func disabledBackground(_ isDisabled: Bool) -> some View {
        overlay {
            if isDisabled {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                    .allowsHitTesting(false)
            }
        }
    }
}
