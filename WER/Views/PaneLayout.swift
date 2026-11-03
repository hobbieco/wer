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

    // 상단 버튼 줄(Go to Folder, 아이콘 3개, Add)이 잘리지 않는 폭
    static let minSelect: CGFloat = 320
    static let minOrder: CGFloat = 480
    // 입력칸이 고정폭 글꼴이라 조금 넓게
    static let minRename: CGFloat = 420
    static let collapsedWidth: CGFloat = 28
    /// 창 최소 높이. 최소 폭의 Rename 칸에서 Preview가 거의 정사각형이 되는 높이
    /// (Preview 위 Rename 설정·경로 줄 약 355pt + 아래 상태 바 약 35pt + Preview 약 350pt (실제로 보면 이 정도가 정사각형에 가깝다))
    static let minHeight: CGFloat = 740
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
