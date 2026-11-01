//
//  AppKitMenu.swift
//  WER
//

import AppKit
import SwiftUI

// SwiftUI 메뉴는 코드로 열거나 펼칠 방향을 정할 수 없어서, 단축키로 열거나 위치를 맞춰야 하는 메뉴는 AppKit 메뉴로 띄운다

/// SwiftUI 뷰 자리에 AppKit 메뉴를 띄우기 위한 빈 뷰
struct MenuAnchor: NSViewRepresentable {
    let register: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        register(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        register(nsView)
    }
}

/// 메뉴 항목을 누르면 클로저를 실행하는 대상
final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }

    /// target은 약하게 잡혀서 representedObject로 메뉴 항목이 붙들고 있게 한다
    static func item(title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }
}

/// 메뉴를 띄울 AppKit 뷰를 담아 둔다. 화면을 다시 그릴 필요가 없어 관찰하지 않는다
final class MenuAnchorBox {
    weak var view: NSView?
}

extension NSMenu {
    /// view 바로 아래에 연다. alignRight면 오른쪽 끝을 맞춰, 창 오른쪽 끝에 있는 버튼이어도 창 안쪽(왼쪽)으로 펼쳐진다
    func popUp(below view: NSView, alignRight: Bool = false) {
        let x = alignRight ? view.bounds.width - size.width : 0
        let y = view.isFlipped ? view.bounds.height + 4 : -4
        popUp(positioning: nil, at: NSPoint(x: x, y: y), in: view)
    }
}
