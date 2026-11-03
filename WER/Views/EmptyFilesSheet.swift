//
//  EmptyFilesSheet.swift
//  WER
//

import AppKit
import SwiftUI

/// Add Empty Files 창 (File > Add Empty Files…, ⌥⌘N, Select의 버튼).
/// 설정 > Empty Files의 기본값으로 시작하고, 바꾼 값은 저장하지 않는다. Select의 현재 폴더에 실제 파일을 바로 만든다
struct EmptyFilesSheet: View {
    let model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var spec = EmptyFileSpec.saved
    @FocusState private var focus: EmptyFileSpec.Field?

    /// 이미 있는 같은 이름. 있으면 만들지 않는다
    @State private var existing: [URL] = []
    /// Finder에서 정리하고 돌아오면 다시 검사한다
    @State private var recheck = 0
    @State private var isChecking = false
    /// 폴더 볼륨의 남은 용량. 창을 열 때와 앱으로 돌아올 때 읽는다
    @State private var space: EmptyFileCreator.VolumeSpace?

    @State private var creation: Task<Void, Never>?
    @State private var progress: Double = 0
    @State private var failure: String?

    private var isCreating: Bool { creation != nil }
    private var plan: EmptyFilePlan? { spec.plan(in: model.folder) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Empty Files")
                .font(.headline)

            EmptyFileSpecFields(spec: $spec, focus: $focus)
                .disabled(isCreating)

            Divider()

            HStack {
                Label {
                    Text((model.folder.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                } icon: {
                    Image(systemName: "folder")
                }
                .help(model.folder.path)
                Spacer()
                if let plan {
                    Text("\(plan.files.count) files · \(Self.format(plan.totalBytes))")
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                if let available = space?.available {
                    Text("/ \(Self.format(available)) free")
                        .foregroundStyle(shortage == nil ? Color.secondary : Color.red)
                        .fixedSize()
                        .help(shortage ?? "Free space on this volume")
                }
            }
            .font(.callout)

            fileList

            status
                .font(.callout)

            if isCreating {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    if let creation { creation.cancel() } else { dismiss() }
                }
                .keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        // 폭은 설정 창 기본 폭과 같게. 높이는 창 최소 높이에서도 아래 상태 바가 보이게
        .padding(20)
        .frame(width: Self.width, height: PaneLayout.minHeight - 70)
        .interactiveDismissDisabled(isCreating)
        // 주로 Max만 바꿔 가며 쓴다
        .onAppear { focus = .max }
        // 입력이 잠시 멈추면 같은 이름이 있는지 확인한다
        .task(id: CheckKey(plan: plan, recheck: recheck)) {
            guard let plan else {
                existing = []
                isChecking = false
                return
            }
            isChecking = true
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let found = await EmptyFileCreator.existing(plan.files.map(\.url))
            guard !Task.isCancelled else { return }
            existing = found
            isChecking = false
        }
        .task(id: recheck) {
            space = await EmptyFileCreator.loadSpace(at: model.folder)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recheck += 1
        }
        .onChange(of: spec) { failure = nil }
    }

    static let width: CGFloat = 520

    /// 만들 파일 목록. 이미 있는 이름은 주황색으로 표시한다
    @ViewBuilder
    private var fileList: some View {
        let existingPaths = Set(existing.map(\.path))
        List(plan?.files ?? [], id: \.url) { file in
            HStack {
                Text(file.url.lastPathComponent)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(file.size.formatted(.number.grouping(.automatic)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                // Finder와 같은 표기 (1000 기준, 단위 자동)
                Text(Self.format(file.size))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
            .foregroundStyle(existingPaths.contains(file.url.path) ? Color.orange : Color.primary)
            .help(existingPaths.contains(file.url.path) ? "Already exists" : "")
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
        .frame(maxHeight: .infinity)
    }

    private struct CheckKey: Equatable {
        let plan: EmptyFilePlan?
        let recheck: Int
    }

    private var canCreate: Bool {
        plan != nil && existing.isEmpty && !isChecking && !isCreating && shortage == nil
    }

    /// 공간이 모자라면 이유
    private var shortage: String? {
        guard let plan, let space else { return nil }
        return space.shortage(for: plan)
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 만들 수 없는 이유, 같은 이름, 실패
    @ViewBuilder
    private var status: some View {
        if let failure {
            Label(failure, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if !existing.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text("\(existing.count) of \(plan?.files.count ?? 0) files already exist. Remove or rename them first.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                .help(existing.prefix(50).map(\.lastPathComponent).joined(separator: "\n") + (existing.count > 50 ? "\n…" : ""))
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(existing)
                }
            }
        } else if let shortage {
            Label(shortage, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if spec.nameTooLong {
            Label("File name is too long", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func create() {
        guard canCreate, let plan else { return }
        if let problem = EmptyFileCreator.preflight(plan) {
            failure = problem
            return
        }
        let addsToOrder = spec.addsToOrder
        progress = 0
        creation = Task {
            do {
                let start = ContinuousClock.now
                let created = try await EmptyFileCreator.create(plan) { progress = $0 }
                model.finishEmptyFiles(created, fill: plan.fill, elapsed: ContinuousClock.now - start, addsToOrder: addsToOrder)
                creation = nil
                dismiss()
            } catch is CancellationError {
                creation = nil
                recheck += 1
            } catch {
                failure = error.localizedDescription
                creation = nil
                recheck += 1
            }
        }
    }
}

/// 빈 파일 입력칸 묶음. Add Empty Files 창과 설정 > Empty Files가 함께 쓴다
struct EmptyFileSpecFields: View {
    @Binding var spec: EmptyFileSpec
    var focus: FocusState<EmptyFileSpec.Field?>.Binding

    var body: some View {
        // 줄마다 라벨 폭을 고정한 세로 배치. 입력칸 줄이 창 폭을 다 쓴다
        VStack(alignment: .leading, spacing: 10) {
            row("Name") {
                field(.name, text: $spec.name)
                    .frame(maxWidth: .infinity)
                Text("Ext")
                    .padding(.leading, 8)
                field(.ext, text: $spec.ext)
                    .frame(width: 100)
            }
            // 단위를 먼저 고르고 값을 입력하는 순서. 바이트로 바꾼 값은 칸 오른쪽에 둔다
            row("Unit") {
                Picker("Unit", selection: $spec.unit) {
                    Text(EmptyFileSpec.Unit.b.rawValue).tag(EmptyFileSpec.Unit.b)
                    Divider()
                    ForEach(EmptyFileSpec.Unit.decimal, id: \.self) { Text($0.rawValue).tag($0) }
                    Divider()
                    ForEach(EmptyFileSpec.Unit.binary, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Applies to Min and Max. Decimals are rounded down to whole bytes.")
                note("KB/MB/GB ×1000 · KiB/MiB/GiB ×1024")
            }
            row("Min") {
                // 1개면 Max만 쓴다. Rename 칸과 같은 회색 배경으로 비활성을 표시한다
                field(.min, text: $spec.min)
                    .frame(width: Self.sizeFieldWidth)
                    .disabled(!spec.usesMin)
                    .disabledBackground(!spec.usesMin)
                note(spec.usesMin ? minBytesText : "Not used for 1 file")
            }
            row("Max") {
                field(.max, text: $spec.max)
                    .frame(width: Self.sizeFieldWidth)
                note(maxBytesText)
            }
            // 오른쪽이 비지 않게 Count 옆에 Fill을 둔다
            row("Count") {
                field(.count, text: $spec.count)
                    .frame(width: Self.sizeFieldWidth)
                Text("Fill")
                    .padding(.leading, 16)
                Picker("Fill", selection: $spec.fill) {
                    ForEach(EmptyFileSpec.Fill.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
                .fixedSize()
                .help("Zeros: created instantly, but servers may compress it. Random: written in full, can't be compressed.")
            }
            row("") {
                Toggle("Add to Order", isOn: $spec.addsToOrder)
                    .toggleStyle(.checkbox)
            }
            if !spec.errors.isEmpty {
                row("") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(spec.errors, id: \.field) { error in
                            Text("\(Self.title(error.field)): \(error.message)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private static let labelWidth: CGFloat = 48

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: Self.labelWidth, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    /// 회색 안내 문구(placeholder)는 쓰지 않는다. 기본값은 실제 값으로 채워 보여준다
    private func field(_ field: EmptyFileSpec.Field, text: Binding<String>) -> some View {
        TextField(Self.title(field), text: text, prompt: Text(""))
            .labelsHidden()
            .focused(focus, equals: field)
            // 오류일 때만 글자색을 정한다. 항상 정하면 비활성 칸의 흐린 글자가 덮인다
            .modifier(ErrorTint(isError: spec.error(for: field) != nil))
            .help(spec.error(for: field) ?? "")
    }

    private static func title(_ field: EmptyFileSpec.Field) -> String {
        switch field {
        case .name: "Name"
        case .ext: "Ext"
        case .min: "Min"
        case .max: "Max"
        case .count: "Count"
        }
    }

    private static let sizeFieldWidth: CGFloat = 120

    private static func bytes(_ value: Int64) -> String {
        value.formatted(.number.grouping(.automatic)) + " bytes"
    }

    /// Min 칸 아래. 쓰지 않거나 비었거나 잘못됐으면 비운다
    private var minBytesText: String {
        guard let value = try? spec.minBytes?.get() else { return " " }
        return Self.bytes(value)
    }

    /// Max 칸 아래. 비었으면 기본값(10) 또는 Min을 쓴다고 알린다
    private var maxBytesText: String {
        if spec.usesDefaultMax, let value = try? spec.maxBytes?.get() {
            return Self.bytes(value) + " (default)"
        }
        if spec.max.trimmingCharacters(in: .whitespaces).isEmpty { return "Same as Min" }
        guard let value = try? spec.maxBytes?.get() else { return " " }
        return Self.bytes(value)
    }
}

private struct ErrorTint: ViewModifier {
    let isError: Bool

    func body(content: Content) -> some View {
        if isError {
            content.foregroundStyle(.red)
        } else {
            content
        }
    }
}
