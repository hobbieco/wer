//
//  QuickLook.swift
//  WER
//

import AppKit
@preconcurrency import Quartz
import SwiftUI

/// ⌘Y Quick Look. Finder처럼 Select·Order에서 고른 파일을 시스템 Quick Look 창으로 보여준다.
/// - ↑↓: 목록 선택을 옮기고 Quick Look이 따라간다
/// - ←→: 무시한다 (폴더 이동 안 함. 여러 파일을 골랐으면 Quick Look이 파일 사이를 넘긴다)
/// - Space: 무시한다 (뒤의 미리보기 칸이 함께 재생되지 않게)
/// Quick Look 창은 키 창의 responder chain에서 제어할 객체를 찾아서, 창 delegate(WindowCloseGuard.Coordinator)가 맡는다
@MainActor
@Observable
final class QuickLook: NSObject {
    static let shared = QuickLook()

    /// Quick Look 창이 열려 있는지 (메뉴 활성화, 키 처리 판단용)
    private(set) var isVisible = false
    /// 지금 보여주는 창의 모델과 그 창
    @ObservationIgnored private weak var model: BrowserModel?
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var urls: [URL] = []

    /// ⌘Y. 열려 있으면 닫고, 아니면 model의 선택으로 연다
    func toggle(for model: BrowserModel?) {
        if isVisible {
            close()
        } else if let model, model.previewSelection.count > 1 {
            // 여러 개는 열지 않는다 (우클릭 메뉴와 같은 규칙)
            model.showNotice("Select one item for Quick Look")
        } else if let model, model.isPreviewPlaying {
            // 재생 중에는 열지 않는다 (소리가 겹치지 않게, 방향키는 재생 조절에 쓴다)
            model.showNotice("Pause playback to open Quick Look")
        } else if let model, !model.previewSelection.isEmpty {
            self.model = model
            QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else {
            isVisible = false
            return
        }
        panel.orderOut(nil)
    }

    /// 목록 선택이 바뀌면 따라간다
    func selectionChanged(in model: BrowserModel) {
        guard isVisible, model === self.model else { return }
        // 비었거나 여러 개가 되면 닫는다
        if model.previewSelection.count != 1 {
            close()
            return
        }
        urls = model.previewURLs
        QLPreviewPanel.shared()?.reloadData()
    }

    // MARK: 창 delegate가 넘기는 제어

    func begin(_ panel: QLPreviewPanel, model: BrowserModel, window: NSWindow?) {
        self.model = model
        self.window = window
        urls = model.previewURLs
        panel.dataSource = self
        panel.delegate = self
        isVisible = true
    }

    func end(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
        isVisible = false
        urls = []
    }
}

extension QuickLook: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let url: URL? = MainActor.assumeIsolated { urls.indices.contains(index) ? urls[index] : nil }
        return url.map { $0 as NSURL }
    }

    /// Quick Look 창이 처리하지 않은 키. ↑↓는 원래 목록으로 넘기고 ←→·Space는 버린다
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let received = event, received.type == .keyDown else { return false }
        // Quick Look은 메인 스레드에서 부른다
        nonisolated(unsafe) let event = received
        return MainActor.assumeIsolated {
            switch Int(event.keyCode) {
            case 125, 126: // ↓ ↑
                // 목록에 포커스가 있을 때만 넘긴다 (입력칸이면 커서만 움직이므로)
                guard let table = window?.firstResponder as? NSTableView else { return true }
                table.keyDown(with: event)
                return true
            case 123, 124, 49: // ← → Space
                return true
            default:
                return false
            }
        }
    }
}

extension WindowCloseGuard.Coordinator {
    // Quick Look은 메인 스레드에서만 부른다
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QuickLook.shared.begin(panel, model: model, window: window) }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QuickLook.shared.end(panel) }
    }
}

extension BrowserModel {
    /// Quick Look에 보여줄 파일. 선택한 목록의 순서대로
    var previewURLs: [URL] {
        let list = orderSelection.isEmpty ? items : orderedFiles
        return list.map(\.url).filter { previewSelection.contains($0) }
    }
}
