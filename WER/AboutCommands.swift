//
//  AboutCommands.swift
//  WER
//

import SwiftUI

/// ① 메뉴 > WER > About WER·Settings…, 메뉴 > Help. 기본 About 창에 설명·저장소 링크·라이선스를 더한다
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    static let repositoryURL = URL(string: "https://github.com/hobbieco/wer")!
    static let usageURL = URL(string: "https://github.com/hobbieco/wer#usage")!

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About WER") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: SettingsView.windowID) }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .help) {
            Button("WER Help") { NSWorkspace.shared.open(Self.usageURL) }
        }
    }

    private static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 6
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let note: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(
            string: "Want to Edit file Rename — rename many files at once with your own order and rules.\n",
            attributes: body
        ))
        var link = body
        link[.link] = repositoryURL
        text.append(NSAttributedString(string: "github.com/hobbieco/wer\n", attributes: link))
        text.append(NSAttributedString(
            string: "Licensed under the Apache License, Version 2.0.",
            attributes: note
        ))
        return text
    }
}
