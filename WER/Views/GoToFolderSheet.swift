//
//  GoToFolderSheet.swift
//  WER
//

import SwiftUI

/// Finder의 폴더로 이동(⇧⌘G). 입력하면 아래에 후보 목록을 보여준다.
/// 복사 위치 선택에도 쓰며, 이때는 새 폴더 버튼을 보여준다.
struct GoToFolderSheet: View {
    let title: String
    let confirmTitle: String
    /// 시작 경로. 폴더면 그 폴더와 하위 폴더 목록을 보여준다
    let initialPath: String
    let showsNewFolder: Bool
    let onGo: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var suggestions: [String] = []
    @AppStorage(AppSettings.monospacedNamesKey) private var monospacedNames = true
    @State private var highlighted: String?
    // 폴더 목록 모드일 때 목록의 기준 폴더. 직접 입력 중이면 nil
    @State private var listingFolder: String?
    @State private var errorMessage: String?
    @State private var isNewFolderPresented = false
    @State private var newFolderName = ""
    @FocusState private var isFieldFocused: Bool

    init(
        title: String = "Go to Folder",
        confirmTitle: String = "Go",
        initialFolder: URL,
        showsNewFolder: Bool = false,
        onGo: @escaping (String) -> Bool
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.initialPath = (initialFolder.path as NSString).abbreviatingWithTildeInPath + "/"
        self.showsNewFolder = showsNewFolder
        self.onGo = onGo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            TextField("~/Documents", text: $path)
                .font(AppSettings.fieldFont(monospaced: monospacedNames))
                .onChange(of: path) {
                    errorMessage = nil
                    // 후보 선택으로 채운 경우에는 목록을 유지한다
                    guard path != highlighted else { return }
                    suggestions = PathCompleter.suggestions(for: path)
                    highlighted = nil
                    listingFolder = nil
                }
                .focused($isFieldFocused)
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.leftArrow) { enterParent() }
                .onKeyPress(.rightArrow) { enterHighlighted() }
                .onKeyPress(.tab) { complete() }

            if !suggestions.isEmpty {
                ScrollViewReader { proxy in
                List(suggestions, id: \.self, selection: highlightBinding) { suggestion in
                    Label {
                        Text(suggestion)
                            .font(AppSettings.fieldFont(monospaced: monospacedNames))
                            .lineLimit(1)
                            .truncationMode(.head)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: (suggestion as NSString).expandingTildeInPath))
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                }
                .contextMenu(forSelectionType: String.self) { _ in
                } primaryAction: { selected in
                    if let suggestion = selected.first { go(suggestion) }
                }
                // 목록을 클릭해 포커스가 옮겨가도 입력칸과 같은 키로 움직인다 (↑↓는 목록 기본 동작)
                .onKeyPress(.leftArrow) { enterParent() }
                .onKeyPress(.rightArrow) { enterHighlighted() }
                .onKeyPress(.tab) { complete() }
                .frame(height: 220)
                // 입력칸에서 ↑↓로 고르거나 폴더를 옮겨도 고른 항목이 보이게 한다
                .onChange(of: highlighted) {
                    if let highlighted { proxy.scrollTo(highlighted) }
                }
                .onChange(of: listingFolder) {
                    if let highlighted { proxy.scrollTo(highlighted) }
                }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                if showsNewFolder {
                    Button("New Folder") {
                        newFolderName = "untitled folder"
                        isNewFolderPresented = true
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { go(path) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(path.isEmpty)
            }
        }
        .frame(width: 480)
        .padding()
        .onAppear {
            if !showFolder(initialPath) { path = initialPath }
            isFieldFocused = true
        }
        .alert("New Folder", isPresented: $isNewFolderPresented) {
            TextField("Name", text: $newFolderName)
            Button("Create", action: createFolder)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a folder in \(baseFolder ?? path)")
        }
    }

    /// 새 폴더를 만들 위치. 목록 모드면 기준 폴더, 아니면 입력한 경로(폴더) 또는 그 상위 폴더
    private var baseFolder: String? {
        if let listingFolder { return listingFolder }
        if !PathCompleter.folderListing(for: path).isEmpty { return path }
        return PathCompleter.parent(of: path)
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let base = baseFolder else { return }
        let folder = (base.hasSuffix("/") ? base : base + "/") + name
        do {
            try FileManager.default.createDirectory(
                atPath: (folder as NSString).expandingTildeInPath,
                withIntermediateDirectories: false
            )
            showFolder(folder)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 목록을 클릭해 선택해도 입력칸을 채운다
    private var highlightBinding: Binding<String?> {
        Binding {
            highlighted
        } set: { newValue in
            highlighted = newValue
            if let newValue { path = newValue }
        }
    }

    private func moveHighlight(by step: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        let current = highlighted.flatMap { suggestions.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), suggestions.count - 1) } ?? (step > 0 ? 0 : suggestions.count - 1)
        highlighted = suggestions[next]
        path = suggestions[next]
        return .handled
    }

    private func complete() -> KeyPress.Result {
        // 이미 후보로 채워진 상태면 그 폴더와 하위 폴더 목록으로 바꾼다
        if highlighted != nil {
            showFolder(path)
            return .handled
        }
        guard let completion = PathCompleter.commonPrefix(of: suggestions),
              completion.count >= path.count else { return .ignored }
        if !showFolder(completion) {
            path = completion
        }
        return .handled
    }

    // 좌우 키는 목록에서 후보를 고른 상태일 때만 가로챈다. 아니면 입력칸 커서 이동.

    /// → 고른 폴더의 하위 폴더 목록으로 들어간다
    private func enterHighlighted() -> KeyPress.Result {
        guard let highlighted else { return .ignored }
        if highlighted != listingFolder, highlighted.hasSuffix("/") {
            showFolder(highlighted)
        }
        return .handled
    }

    /// ← 상위 폴더 목록으로 나오고, 방금 있던 폴더를 선택한다
    private func enterParent() -> KeyPress.Result {
        guard let highlighted else { return .ignored }
        guard let current = listingFolder ?? PathCompleter.parent(of: highlighted),
              let parent = PathCompleter.parent(of: current) else { return .handled }
        showFolder(parent, select: current)
        return .handled
    }

    /// 목록을 폴더 자신과 하위 폴더로 바꾸고, 선택한 항목으로 입력칸을 채운다.
    @discardableResult
    private func showFolder(_ folderPath: String, select item: String? = nil) -> Bool {
        let listing = PathCompleter.folderListing(for: folderPath)
        guard let folder = listing.first else { return false }
        // "~/"와 "/Users/name/"처럼 표기가 달라도 같은 폴더면 선택한다
        let expand = { (path: String) in (path as NSString).expandingTildeInPath }
        let selected = item.flatMap { item in listing.first { expand($0) == expand(item) } } ?? folder
        // highlighted를 먼저 맞춰 onChange(of: path)가 목록을 덮어쓰지 않게 한다
        highlighted = selected
        path = selected
        suggestions = listing
        listingFolder = folder
        return true
    }

    private func go(_ target: String) {
        if onGo(target) {
            dismiss()
        } else {
            errorMessage = "The folder can't be found."
        }
    }
}
