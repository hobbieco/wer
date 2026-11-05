//
//  WindowFillKeeper.swift
//  WER
//

import AppKit

/// 화면을 채운(Fill) 창을 해상도가 다른 모니터로 옮기면 그 모니터의 화면에 맞게 다시 채운다.
/// macOS는 창 > 이동 등으로 다른 모니터에 보낼 때 크기를 그대로 두어서, 작은 화면에서는 넘치고 큰 화면에서는 남는다.
/// 창 크기·위치가 바뀔 때마다 채운 상태인지 기억해 두고, 모니터가 바뀌면 그 값으로 판단한다
/// (모니터가 바뀐 뒤에는 이미 새 위치라 판단할 수 없다)
@MainActor
enum WindowFillKeeper {
    /// 채운 상태로 볼 화면 가장자리 여백 한도. "타일 창 사이 여백" 설정이 켜져 있으면 몇 pt 떨어진다
    private static let maxInset: CGFloat = 24
    private static let tolerance: CGFloat = 2

    private struct State {
        let screen: NSScreen
        /// 채운 상태면 화면 가장자리 여백 (위·왼쪽·아래·오른쪽 같은 값), 아니면 nil
        let fillInset: CGFloat?
    }

    private static var states: [ObjectIdentifier: State] = [:]

    static func install() {
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { record(window) }
            }
        }
        center.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { screenChanged(window) }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { states[ObjectIdentifier(window)] = nil }
        }
    }

    private static func isTarget(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.resizable) && !window.styleMask.contains(.fullScreen)
            && !(window is NSPanel) && window.sheetParent == nil
    }

    /// 지금 모니터에서 채운 상태인지 기억한다. 모니터가 바뀌는 중(이동 알림이 먼저 오는 경우)이면 덮어쓰지 않는다
    private static func record(_ window: NSWindow) {
        guard isTarget(window), let screen = window.screen else { return }
        let id = ObjectIdentifier(window)
        if let state = states[id], state.screen != screen { return }
        states[id] = State(screen: screen, fillInset: fillInset(of: window.frame, in: screen.visibleFrame))
    }

    private static func screenChanged(_ window: NSWindow) {
        guard isTarget(window), let screen = window.screen else { return }
        let id = ObjectIdentifier(window)
        let previous = states[id]
        states[id] = State(screen: screen, fillInset: fillInset(of: window.frame, in: screen.visibleFrame))
        // 끌어서 옮기는 중에는 손대지 않는다 (macOS가 끌기 시작할 때 채운 상태를 풀기도 한다)
        guard let inset = previous?.fillInset, previous?.screen != screen, NSEvent.pressedMouseButtons == 0 else { return }
        // macOS가 옮기기를 마친 뒤 맞춘다
        DispatchQueue.main.async {
            guard window.screen == screen else { return }
            let target = screen.visibleFrame.insetBy(dx: inset, dy: inset)
            if !window.frame.equalTo(target) { window.setFrame(target, display: true, animate: false) }
            states[id] = State(screen: screen, fillInset: inset)
        }
    }

    /// 창이 화면을 고르게 채웠으면 가장자리 여백
    private static func fillInset(of frame: NSRect, in visible: NSRect) -> CGFloat? {
        let insets = [
            frame.minX - visible.minX, visible.maxX - frame.maxX,
            frame.minY - visible.minY, visible.maxY - frame.maxY,
        ]
        guard let low = insets.min(), let high = insets.max(),
              low >= -tolerance, high <= maxInset, high - low <= tolerance else { return nil }
        return max(0, (insets.reduce(0, +) / 4).rounded())
    }
}
