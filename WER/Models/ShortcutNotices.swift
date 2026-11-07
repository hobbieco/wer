//
//  ShortcutNotices.swift
//  WER
//

import AppKit

/// 꺼져 있어 동작하지 않은 단축키의 이유를 상태 바에 보여준다.
/// 메뉴 항목이 꺼져 있으면 단축키가 아무 반응 없이 지나가서, KeyEquivalentRouter가 메뉴에서 처리되지 않은 키를 여기로 넘긴다
extension BrowserModel {
    /// 키를 누른 창의 모델. 창이 활성일 때 ContentView가 지정한다
    nonisolated(unsafe) static weak var active: BrowserModel?

    /// 메뉴에서 처리되지 않은 ⌘ 키. 이유가 있으면 상태 바에 안내하고 true (그 키는 더 처리하지 않는다)
    func explainUnavailableShortcut(_ event: NSEvent, characters: String?) -> Bool {
        guard let message = unavailableShortcutMessage(key: Self.keyName(event, characters: characters), modifiers: event.modifierFlags)
        else { return false }
        showNotice(message)
        return true
    }

    /// 목록 안에서만 쓰는 키(↩, ⌫)가 동작하지 않은 이유
    func explainUnavailableListKey(_ key: String) {
        switch key {
        case "↩" where selection.count > 1:
            showNotice("Select one item to rename")
        case "⌫" where orderSelection.isEmpty && !orderedFiles.isEmpty:
            showNotice("Select files in Order to remove (⌥⌘← removes all)")
        default:
            break
        }
    }

    private func unavailableShortcutMessage(key: String, modifiers: NSEvent.ModifierFlags) -> String? {
        let flags = modifiers.intersection([.command, .option, .shift, .control])
        let isListFocused = shortcutPane == .select || shortcutPane == .order
        switch (key, flags) {
        case ("o", [.command]):
            return previewSelection.count > 1 ? "Select one item to open" : "Select a file or folder to open"
        case ("↑", [.command]) where shortcutPane == .select:
            return "Already at the top level"
        case ("→", [.command]) where shortcutPane == .select:
            if selection.isEmpty { return "Select files to add (⌥⌘→ adds all)" }
            return hasSelectedFiles ? Self.mixedSelectionMessage : "Folders can't be added to Order"
        case ("→", [.command]) where shortcutPane == .order:
            return "⌘→ adds files selected in Select (⌥⌘→ adds all)"
        case ("→", [.command, .option]) where isListFocused:
            return files.isEmpty ? "No files in this folder" : "All files are already in Order"
        case ("←", [.command]) where shortcutPane == .order:
            return orderedFiles.isEmpty ? "Order is empty" : "Select files in Order to remove (⌥⌘← removes all)"
        case ("←", [.command]) where shortcutPane == .select:
            return selection.isEmpty ? "Select files to remove from Order (⌥⌘← removes all)" : "Selected files aren't in Order"
        case ("←", [.command, .option]) where isListFocused:
            return "Order is empty"
        case ("↑", [.command]), ("↓", [.command]), ("↑", [.command, .option]), ("↓", [.command, .option]):
            guard shortcutPane == .order else { return nil }
            return orderedFiles.isEmpty ? "Order is empty" : "Select files in Order to move"
        case ("r", [.command, .shift]):
            return "Reverse needs 2 or more files in Order"
        case ("↩", [.command]):
            if renamingURL != nil { return nil }
            if renameSettings.tokens.allSatisfy({ $0.kind == .none }) { return "Choose a type in at least one slot" }
            if !renameSettings.formatErrors.isEmpty { return "Fix the errors in Rename first" }
            if !renameSettings.isValid { return "Fill in the empty fields in Rename first" }
            return "Already applied"
        case ("[", [.command]):
            return "No earlier rule to go back to"
        case ("y", [.command]):
            if isPreviewPlaying { return "Pause playback to open Quick Look" }
            return previewSelection.count > 1 ? "Select one item for Quick Look" : "Select a file or folder to preview"
        case ("i", [.command]):
            return AppSettings.isPreviewEnabled ? "Select a file or folder to show info" : "Info is shown while Preview is off"
        case ("n", [.command, .option]):
            if isRunning { return "Wait until the current run finishes" }
            if renamingURL != nil { return nil }
            return "Can't create files in this folder"
        case ("z", [.command, .option]):
            return isRunning ? "Wait until the current run finishes" : "Nothing to undo"
        default:
            return nil
        }
    }

    /// 화살표·Return은 기호로, 글자는 소문자로 (한글 입력이면 영문 자판 기준 글자를 받는다)
    private static func keyName(_ event: NSEvent, characters: String?) -> String {
        switch event.keyCode {
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        case 36, 76: "↩"
        default: (characters ?? event.charactersIgnoringModifiers ?? "").lowercased()
        }
    }
}
