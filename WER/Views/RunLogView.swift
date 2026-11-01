//
//  RunLogView.swift
//  WER
//

import SwiftUI

/// Preview 영역에 보여주는 실행 로그. 파일별 처리를 한 줄씩 쌓는다
struct RunLogView: View {
    let entries: [RenameLogEntry]
    let isRunning: Bool
    /// 성공한 실행의 로그일 때만 준다. 제목 줄에 Undo 버튼을 보여준다
    var onUndo: (() -> Void)?
    var undoTitle = "Undo Rename"
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Log")
                    .font(.headline)
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                // 결과를 확인하는 자리에서 바로 되돌릴 수 있게 둔다. Close와 헷갈리지 않게 간격을 둔다
                if let onUndo {
                    Button(undoTitle, systemImage: "arrow.uturn.backward", action: onUndo)
                        .help("Undo the last run (⌥⌘Z)")
                        .padding(.trailing, 8)
                }
                Button("Close", action: onClose)
                    .disabled(isRunning)
            }
            ScrollViewReader { proxy in
                List(entries) { entry in
                    row(entry)
                        .listRowSeparator(.hidden)
                        .id(entry.id)
                }
                .font(.system(.caption, design: .monospaced))
                // 진행 중에는 마지막 줄을 따라간다
                .onChange(of: entries.count) {
                    if let last = entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func row(_ entry: RenameLogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            icon(entry.kind)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message)
                    .textSelection(.enabled)
                    .lineLimit(2)
                if let detail = entry.detail {
                    Text(detail)
                        .foregroundStyle(entry.kind == .failure ? Color.red : Color.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func icon(_ kind: RenameLogEntry.Kind) -> some View {
        switch kind {
        case .info: Image(systemName: "info.circle").foregroundStyle(.secondary)
        case .success: Image(systemName: "checkmark").foregroundStyle(.green)
        case .failure: Image(systemName: "xmark").foregroundStyle(.red)
        case .revert: Image(systemName: "arrow.uturn.backward").foregroundStyle(.orange)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }
}
