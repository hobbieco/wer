//
//  PaneLayout.swift
//  WER
//

import SwiftUI

/// Select | Order | Rename 칸 너비 계산. 비율로 저장해 창 크기가 바뀌어도 비율을 유지하고, 칸마다 최소 폭을 지킨다.
struct PaneLayout {
    static let defaultSelectFraction = 0.25
    static let defaultOrderFraction = 0.5

    static let minSelect: CGFloat = 280
    static let minOrder: CGFloat = 480
    static let minRename: CGFloat = 360
    static let collapsedWidth: CGFloat = 28
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

    static func widths(total: CGFloat, selectFraction: Double, orderFraction: Double, isSelectCollapsed: Bool) -> Widths {
        let available = available(total: total)
        if isSelectCollapsed {
            // Select 몫은 Order와 Rename이 원래 비율대로 나눠 쓴다
            let rest = available - collapsedWidth
            let orderShare = orderFraction / max(1 - selectFraction, 0.01)
            let order = clamp(rest * orderShare, minOrder, rest - minRename)
            return Widths(select: collapsedWidth, order: order, rename: rest - order)
        }
        let select = clamp(available * selectFraction, minSelect, available - minOrder - minRename)
        let order = clamp(available * orderFraction, minOrder, available - select - minRename)
        return Widths(select: select, order: order, rename: available - select - order)
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
