//
//  NoticeTicker.swift
//  WER
//

import SwiftUI

/// 상태 바 2칸의 안내. 서서히 나타나고 사라진다.
/// 칸에 들어가지 않으면 1초 뒤 끝까지 한 번 흘리고 멈춘다. 동작 줄이기를 켰으면 흘리지 않고 줄임표와 마우스 설명으로 보여준다
struct NoticeTicker: View {
    let text: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    /// 흘리는 속도 (pt/초)
    private static let speed: CGFloat = 40

    var body: some View {
        ZStack(alignment: .leading) {
            // 안내가 없어도 칸이 비지 않게 둔다 (빈 칸은 폭을 차지하지 않아 상태 바 배치가 밀린다).
            // 크기를 0으로 두어 상태 바 높이를 늘리지 않는다
            Color.clear
                .frame(width: 0, height: 0)
            if let text {
                label(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: !reduceMotion, vertical: false)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                    .offset(x: offset)
                    .help(text)
                    .transition(.opacity)
                    .id(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
        .animation(.easeInOut(duration: 0.25), value: text)
        .task(id: text) { await scrollIfNeeded() }
    }

    private func label(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .foregroundStyle(.orange)
    }

    /// 넘치는 만큼 한 번 흘린다
    private func scrollIfNeeded() async {
        offset = 0
        guard text != nil, !reduceMotion else { return }
        try? await Task.sleep(for: .seconds(1))
        let overflow = textWidth - boxWidth
        guard overflow > 0, !Task.isCancelled else { return }
        withAnimation(.linear(duration: overflow / Self.speed)) {
            offset = -overflow
        }
    }
}
