//
//  PaneLayout.swift
//  WER
//

import SwiftUI

/// Select | Order | Rename 칸 너비 계산. Select와 Rename 폭을 pt로 저장하고 Order가 나머지를 갖는다.
/// 비율로 저장하면 끄기를 마칠 때 비율로 바꾸는 계산 때문에 경계가 튀어서, 폭을 그대로 쓴다. 칸마다 최소 폭을 지킨다.
struct PaneLayout {
    static let defaultSelectWidth: Double = 320
    static let defaultRenameWidth: Double = 440

    // 최소 폭은 MacBook Pro 14인치의 가장 좁은 설정(1024×665)에서 세 칸이 모두 들어가도록 잡는다 (290 + 400 + 330 + 2 = 1022).
    // 더 좁은 화면이면 Select를 접은 채 연다
    // 상단 버튼 줄(Go to Folder, 아이콘 2개, Add)이 잘리지 않는 폭
    static let minSelect: CGFloat = 290
    // 버튼 줄(Remove, 이동 6개, Reverse)이 잘리지 않는 폭
    static let minOrder: CGFloat = 400
    // 조각 줄의 고정 폭(손잡이 18, 종류 90, 두 번째 칸 64, 구분자 26, 간격 6×4, 여백) 약 238을 빼고 값 입력칸이 약 92 남는 폭
    static let minRename: CGFloat = 330
    static let collapsedWidth: CGFloat = 28
    /// 창 최소 높이. MacBook Pro 14인치의 가장 큰 글자 설정(1024×665)에서 메뉴 막대·제목 막대를 빼고 들어가는 높이
    /// (Preview 위 Rename 설정·경로 줄 약 355pt + 아래 상태 바 약 35pt + Preview 약 210pt)
    static let minHeight: CGFloat = 600
    /// 칸 사이 경계선 2개의 폭
    static let handlesWidth: CGFloat = 2

    struct Widths {
        var select: CGFloat
        var order: CGFloat
        var rename: CGFloat
    }

    /// 창의 최소 너비
    static func minWidth(isSelectCollapsed: Bool) -> CGFloat {
        (isSelectCollapsed ? collapsedWidth : minSelect) + minOrder + minRename + handlesWidth
    }

    /// 칸 영역 전체에서 경계선을 뺀 폭
    static func available(total: CGFloat) -> CGFloat {
        max(total - handlesWidth, 0)
    }

    /// 저장한 Select·Rename 폭으로 세 칸 폭을 정한다. 창이 좁아 다 못 들어가면 Rename, Select 순으로 줄인다
    static func widths(total: CGFloat, selectWidth: CGFloat, renameWidth: CGFloat, isSelectCollapsed: Bool) -> Widths {
        let available = available(total: total)
        let select = isSelectCollapsed
            ? collapsedWidth
            : clamp(selectWidth, minSelect, available - minOrder - minRename)
        let rename = clamp(renameWidth, minRename, available - select - minOrder)
        return Widths(select: select, order: max(available - select - rename, 0), rename: rename)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(upper, lower))
    }
}

/// 칸 사이 경계선. 좌우로 끌어 너비를 조절한다.
struct SplitHandle: View {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        Divider()
            .overlay {
                // 1pt 선은 잡기 어려워 좌우로 넓은 영역에서 끌 수 있게 한다
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { onChanged($0.translation.width) }
                            .onEnded { _ in onEnded() }
                    )
            }
            // 오른쪽 칸이 넓힌 영역을 덮지 않게
            .zIndex(1)
    }
}
