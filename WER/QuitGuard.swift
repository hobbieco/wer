//
//  QuitGuard.swift
//  WER
//

import AppKit
import SwiftUI

/// Order는 저장하지 않아서, Order에 파일이 있는 채로 종료하거나 창을 닫으면 확인한다.
/// 이름 바꾸기 실행 중에는 종료·닫기를 막는다
extension BrowserModel {
    /// 열려 있는 창의 모델. 창이 사라지면 ContentView가 뺀다
    nonisolated(unsafe) static let open = NSHashTable<BrowserModel>.weakObjects()

    var hasOrderWork: Bool { !orderedFiles.isEmpty }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSServicesMenuRequestor {
    /// Services가 파일을 받을 수 있으면 지금 창의 선택(또는 우클릭 대상)을 넘긴다. 응답자 체인 끝에서 NSApp이 묻는다.
    /// 우클릭 메뉴에는 Services가 나오지 않는다 (SelectContextMenu 참고, 보류 중)
    @objc func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        guard returnType == nil, sendType == .fileURL, let model = BrowserModel.active, !model.serviceURLs.isEmpty
        else { return nil }
        return self
    }

    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let urls = BrowserModel.active?.serviceURLs, !urls.isEmpty else { return false }
        pboard.clearContents()
        return pboard.writeObjects(urls as [NSURL])
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let models = BrowserModel.open.allObjects
        if models.contains(where: \.isRunning) {
            let alert = NSAlert()
            alert.messageText = "A rename is in progress"
            alert.informativeText = "Wait until it finishes, then quit."
            alert.runModal()
            return .terminateCancel
        }
        let withOrder = models.filter(\.hasOrderWork).count
        guard withOrder > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit WER?"
        alert.informativeText = (models.count > 1 ? "Order has files in \(withOrder) of \(models.count) windows." : "Order has files.")
            + " The order you set will be lost."
        // 첫 버튼이 기본(Return). 실수로 Return을 눌러도 종료하지 않게 Cancel을 먼저 둔다
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

/// 창 닫기(⌘W, 닫기 버튼) 확인. SwiftUI에는 창 닫기를 막는 기능이 없어서,
/// AppKit 창의 delegate를 감싸 windowShouldClose만 가로채고 나머지는 원래 delegate로 넘긴다
struct WindowCloseGuard: NSViewRepresentable {
    let model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.install(on: view.window) }
        return view
    }

    // SwiftUI가 delegate를 다시 지정했으면 다시 감싼다
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.install(on: view.window) }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        let model: BrowserModel
        // responds·forwardingTarget는 nonisolated라 거기서도 읽는다 (AppKit은 메인 스레드에서만 부른다)
        nonisolated(unsafe) weak var original: NSWindowDelegate?
        /// 감싼 창 (Quick Look이 ↑↓를 이 창의 목록으로 넘긴다)
        private(set) weak var window: NSWindow?
        /// 확인 창에서 Close를 누른 뒤 다시 닫을 때는 묻지 않는다
        private var isConfirmed = false

        init(model: BrowserModel) {
            self.model = model
        }

        func install(on window: NSWindow?) {
            guard let window, window.delegate !== self else { return }
            self.window = window
            original = window.delegate
            window.delegate = self
            restoreFrame(of: window)
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { note in
                    guard let window = note.object as? NSWindow else { return }
                    MainActor.assumeIsolated {
                        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "mainWindowFrame")
                    }
                }
            }
        }

        private static let frameKey = "mainWindowFrame"
        /// 앱을 켠 뒤 첫 창만 복원한다 (⌘N 창은 macOS가 겹쳐 놓는다)
        private static var didRestore = false

        /// SwiftUI가 창 위치를 안정적으로 복원하지 못해(다중 모니터에서 모니터·크기가 매번 달라짐) 직접 저장·복원한다.
        /// 저장한 위치가 지금 연결된 모니터 안이 아니면 그대로 둔다
        private func restoreFrame(of window: NSWindow) {
            guard !Self.didRestore else { return }
            Self.didRestore = true
            guard let saved = UserDefaults.standard.string(forKey: "mainWindowFrame") else { return }
            let frame = NSRectFromString(saved)
            guard !frame.isEmpty else { return }
            // 가장 많이 겹치는 모니터를 고르고, 그 화면 안에 들어오게 크기·위치를 맞춘다 (모니터·해상도가 바뀐 경우 대비)
            func overlap(_ screen: NSScreen) -> CGFloat {
                let r = screen.visibleFrame.intersection(frame)
                return r.isNull ? 0 : r.width * r.height
            }
            guard let screen = NSScreen.screens.max(by: { overlap($0) < overlap($1) }), overlap(screen) > 0 else { return }
            let visible = screen.visibleFrame
            var fitted = frame
            fitted.size.width = min(fitted.width, visible.width)
            fitted.size.height = min(fitted.height, visible.height)
            fitted.origin.x = min(max(fitted.minX, visible.minX), visible.maxX - fitted.width)
            fitted.origin.y = min(max(fitted.minY, visible.minY), visible.maxY - fitted.height)
            window.setFrame(fitted, display: true)
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : nil
        }

        func windowShouldClose(_ window: NSWindow) -> Bool {
            if isConfirmed || !model.isRunning && !model.hasOrderWork {
                return original?.windowShouldClose?(window) ?? true
            }
            let alert = NSAlert()
            if model.isRunning {
                alert.messageText = "A rename is in progress"
                alert.informativeText = "Wait until it finishes, then close the window."
                alert.beginSheetModal(for: window)
                return false
            }
            alert.messageText = "Close this window?"
            alert.informativeText = "Order has files. The order you set will be lost."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Close")
            alert.beginSheetModal(for: window) { [weak self, weak window] response in
                guard response == .alertSecondButtonReturn, let self, let window else { return }
                self.isConfirmed = true
                window.performClose(nil)
            }
            return false
        }
    }
}
