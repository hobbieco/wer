//
//  TokenGridEditor.swift
//  WER
//

import SwiftUI

/// 이름 조각 다섯 칸 편집. Rename 칸과 설정의 프리셋 편집에서 함께 쓴다
struct TokenGridEditor: View {
    @Binding var tokens: [NameToken]
    let usesSeparator: Bool
    let omitsLastSeparator: Bool
    /// 입력칸 중 하나라도 포커스를 받거나 모두 잃을 때 부른다 (Rename 칸 제목 강조용)
    var onFocusChange: ((Bool) -> Void)?
    /// ⌘1~5 요청. 바뀌면 그 칸의 종류 드롭다운을 연다 (Rename 칸만)
    var kindMenuRequest: BrowserModel.KindMenuRequest?
    /// ⌘T로 Rename 칸에 온 요청. 바뀌면 마지막으로 쓰던 입력칸(없으면 첫 활성 값 칸)에 포커스를 준다
    var focusRequest: UUID?

    @State private var hoveredSlot: Int?
    // 손잡이를 끄는 중인 칸과 놓을 자리
    @State private var dragSource: Int?
    @State private var dropTargetSlot: Int?
    @State private var gridHeight: CGFloat = 0
    @FocusState private var focusedField: FieldID?
    @State private var lastFocusedField: FieldID?
    @State private var menuAnchors = MenuAnchors()

    /// 입력칸 구분: 칸 id와 열(0 값, 1 두 번째 칸, 2 구분자)
    private struct FieldID: Hashable {
        let token: NameToken.ID
        let column: Int
    }

    private static let rowSpacing: CGFloat = 6

    /// 한 줄이 차지하는 높이 (줄 높이 + 간격). 끈 거리를 줄 수로 바꾸는 데 쓴다
    private var rowPitch: CGFloat {
        guard !tokens.isEmpty, gridHeight > 0 else { return 28 }
        return (gridHeight + Self.rowSpacing) / CGFloat(tokens.count)
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: Self.rowSpacing) {
            ForEach(Array($tokens.enumerated()), id: \.element.id) { slot, $token in
                GridRow {
                    handle(slot: slot, token: token)
                    // Default 프리셋과 같은 순서 (None은 구분선으로 분리)
                    Picker("Type", selection: kindBinding($token)) {
                        Text("None").tag(NameToken.Kind.none)
                        Divider()
                        Text("Text").tag(NameToken.Kind.text)
                        Text("Regex").tag(NameToken.Kind.regex)
                        Text("Number").tag(NameToken.Kind.number)
                    }
                    .frame(width: 90)
                    // ⌘1~5 메뉴를 띄울 자리
                    .background(MenuAnchor { menuAnchors.views[token.id] = $0 })
                    // 비활성 칸은 회색 배경으로 구분한다 (None 줄 전체, Text의 두 번째 칸, 쓰지 않는 구분자)
                    let isNone = token.kind == .none
                    let isOptionDisabled = isNone || token.kind == .text
                    let isSeparatorDisabled = isNone || !usesSeparator || isOmittedSeparator(slot)
                    TextField(RenameDefaults.builtIn.value(for: token.kind), text: $token.value)
                        .focused($focusedField, equals: FieldID(token: token.id, column: 0))
                        .multilineTextAlignment(.center)
                        .invalidBorder(token.validationError != nil)
                        .help(token.validationError ?? Self.help(for: token.kind))
                        .disabled(isNone)
                        .disabledBackground(isNone)
                    // 두 번째 칸: Number 증가 폭, Regex 채우기 모양. Text는 쓰지 않는다
                    TextField(RenameDefaults.builtIn.option(for: token.kind), text: $token.option)
                        .focused($focusedField, equals: FieldID(token: token.id, column: 1))
                        .multilineTextAlignment(.center)
                        .frame(width: 66)
                        .invalidBorder(token.optionError != nil)
                        .help(token.optionError ?? Self.optionHelp(for: token.kind))
                        .disabled(isOptionDisabled)
                        .disabledBackground(isOptionDisabled)
                    TextField("Sep", text: $token.separator)
                        .focused($focusedField, equals: FieldID(token: token.id, column: 2))
                        .multilineTextAlignment(.center)
                        .frame(width: 30)
                        .invalidBorder(token.separatorError != nil)
                        .help(token.separatorError ?? (isOmittedSeparator(slot) ? "Omitted after the last slot" : "Separator"))
                        .disabled(isSeparatorDisabled)
                        .disabledBackground(isSeparatorDisabled)
                }
                // 끄는 중인 칸은 흐리게
                .opacity(dragSource == slot ? 0.5 : 1)
                // 오류가 있는 칸은 줄 전체를 옅은 빨간색으로, 끌어다 놓을 자리는 강조색으로
                .background {
                    if dropTargetSlot == slot, dragSource != slot {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.2))
                            .padding(-2)
                    } else if token.validationError != nil || token.optionError != nil || token.separatorError != nil {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(0.12))
                            .padding(-2)
                    }
                }
            }
        }
        .labelsHidden()
        .onChange(of: focusedField) { _, field in
            if let field { lastFocusedField = field }
            onFocusChange?(field != nil)
        }
        // 커서가 있던 칸이 비활성이 되면(None으로 바꿈 등) 포커스를 비운다
        .onChange(of: tokens) { clearDisabledFocus() }
        .onChange(of: usesSeparator) { clearDisabledFocus() }
        .onChange(of: omitsLastSeparator) { clearDisabledFocus() }
        .onChange(of: focusRequest) { _, request in
            guard request != nil else { return }
            if let last = lastFocusedField, isEnabled(last) {
                focusedField = last
            } else if let first = tokens.first(where: { $0.kind != .none }) {
                focusedField = FieldID(token: first.id, column: 0)
            }
        }
        .onChange(of: kindMenuRequest) { _, request in
            if let request { openKindMenu(slot: request.slot) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { gridHeight = $0 }
    }

    /// 줄 앞 손잡이. 칸 색을 보여주고, 끌어서 순서를 바꾸며, 우클릭하면 이동 메뉴를 연다
    private func handle(slot: Int, token: NameToken) -> some View {
        ZStack {
            // Order 표에서 이 조각을 칠하는 색 (None이어도 항상 표시)
            RoundedRectangle(cornerRadius: 4)
                .fill(RegexPalette.color(slot))
                .frame(width: 14, height: 18)
            // 평소에는 칸 번호(⌘1~5), 마우스를 올리면 끌기 표시
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
        .frame(width: 18, height: 22)
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
        for kind in [NameToken.Kind.none, .text, .regex, .number] {
            let item = MenuAction.item(title: Self.title(for: kind)) {
                guard let index = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
                Self.select(kind, for: &tokens[index])
            }
            if kind == tokens[slot].kind {
                item.state = .on
                current = item
            }
            menu.addItem(item)
            if kind == .none { menu.addItem(.separator()) }
        }
        // 메뉴 명령 처리 중에는 다른 메뉴를 열 수 없어서 다음 차례에 연다. popUp은 메뉴를 닫을 때까지 기다린다
        DispatchQueue.main.async {
            menu.popUp(positioning: current, at: NSPoint(x: 0, y: anchor.isFlipped ? 0 : anchor.bounds.height), in: anchor)
            // None이면 커서를 둘 칸이 없어서, 다른 칸에 커서가 남아 엉뚱한 칸에 입력되지 않도록 포커스를 비운다
            let field = FieldID(token: tokenID, column: 0)
            focusedField = isEnabled(field) ? field : nil
        }
    }

    private static func title(for kind: NameToken.Kind) -> String {
        switch kind {
        case .none: "None"
        case .text: "Text"
        case .regex: "Regex"
        case .number: "Number"
        }
    }

    /// 사용자가 종류를 고르면 설정 > General의 Default Field Values로 값을 채운다
    private static func select(_ kind: NameToken.Kind, for token: inout NameToken) {
        guard kind != token.kind else { return }
        token.kind = kind
        token.value = AppSettings.fieldDefaults.value(for: kind)
        token.option = AppSettings.fieldDefaults.option(for: kind)
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
        case 0: return kind != .none
        case 1: return kind != .none && kind != .text
        default: return kind != .none && usesSeparator && !isOmittedSeparator(slot)
        }
    }

    /// 마지막 칸 뒤 구분자를 빼는 옵션이면, None이 아닌 마지막 칸의 구분자는 쓰이지 않는다
    private func isOmittedSeparator(_ slot: Int) -> Bool {
        omitsLastSeparator && slot == tokens.lastIndex { $0.kind != .none }
    }

    private static func help(for kind: NameToken.Kind) -> String {
        switch kind {
        case .none: "Not used"
        case .text: "Fixed text"
        case .number: "Start number. Digits follow its length, e.g. 0001. Negative is allowed, e.g. -01"
        case .regex: "Extract from original name. First capture group, or whole match"
        }
    }

    private static func optionHelp(for kind: NameToken.Kind) -> String {
        switch kind {
        case .none, .text: "Not used"
        case .number: "Step. Empty means 1, negative counts down. 0 isn't allowed"
        case .regex: "Pad on the left to this length with its character, e.g. 0000 → 0012. Empty: no padding"
        }
    }
}

private extension View {
    /// 비활성 입력칸을 회색 배경으로 덮어 활성 칸과 구분한다
    func disabledBackground(_ isDisabled: Bool) -> some View {
        overlay {
            if isDisabled {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                    .allowsHitTesting(false)
            }
        }
    }

    /// 값 오류가 있는 입력칸에 빨간 테두리 (빈 값은 글자가 없어 테두리로 표시)
    func invalidBorder(_ isInvalid: Bool) -> some View {
        overlay {
            if isInvalid {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red, lineWidth: 1.5)
            }
        }
    }
}

/// 칸별 메뉴 위치 뷰. 화면을 다시 그릴 필요가 없어 관찰하지 않는 객체에 담는다
private final class MenuAnchors {
    var views: [NameToken.ID: NSView] = [:]
}
