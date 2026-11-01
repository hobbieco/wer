//
//  KeyEquivalentRouter.swift
//  WER
//

import AppKit
import Carbon.HIToolbox

/// ⌘ 단축키를 화면보다 메뉴에 먼저 보낸다. 다음 두 경우에 메뉴 단축키가 동작하지 않아서 둔다.
/// - 목록(List, Table)이 ⌥⌘← 같은 키를 메뉴보다 먼저 가져간다
/// - 한글 입력 상태에서는 ⇧⌘R이 "ㄲ"으로 들어와 메뉴의 R과 맞지 않는다. 영문 자판 기준 글자로 바꿔 다시 맞춰 본다
/// 화살표 단축키는 입력칸에 포커스가 있으면 메뉴 항목이 꺼져 있어서, 입력칸의 ⌘←/⌘→ 등은 그대로 동작한다.
/// 메뉴에서 처리되지 않은 키는 꺼진 단축키일 수 있어 상태 바 안내를 맡긴다. 안내했으면 목록 등이 그 키로 다른 동작을 하지 않도록 끝내고,
/// 아니면 원래대로 흘려보낸다
enum KeyEquivalentRouter {
    static func install() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command), let menu = NSApp.mainMenu else { return event }
            if menu.performKeyEquivalent(with: event) { return nil }
            let ascii = asciiEvent(for: event)
            if let ascii, menu.performKeyEquivalent(with: ascii) { return nil }
            if BrowserModel.active?.explainUnavailableShortcut(event, characters: ascii?.charactersIgnoringModifiers) == true {
                return nil
            }
            return event
        }
    }

    /// 영문이 아닌 글자로 들어온 키를 영문 자판 기준 글자로 바꾼 이벤트
    private static func asciiEvent(for event: NSEvent) -> NSEvent? {
        guard let characters = event.charactersIgnoringModifiers, !characters.allSatisfy(\.isASCII),
              let translated = asciiCharacters(keyCode: event.keyCode, shift: event.modifierFlags.contains(.shift))
        else { return nil }
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: event.modifierFlags,
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: translated,
            charactersIgnoringModifiers: translated,
            isARepeat: event.isARepeat,
            keyCode: event.keyCode
        )
    }

    /// 현재 영문 자판에서 이 키가 내는 글자
    private static func asciiCharacters(keyCode: UInt16, shift: Bool) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let modifiers = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
