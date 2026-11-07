//
//  WERTests.swift
//  WERTests
//

import Foundation
import Testing
@testable import WER

struct OrderMoverTests {
    private let items = Array(0..<10)

    @Test func moveUpKeepsGap() {
        let result = OrderMover.move(items, selected: [3, 5], by: -1)
        #expect(result.items == [0, 1, 3, 2, 5, 4, 6, 7, 8, 9])
        #expect(result.selected == [2, 4])
    }

    @Test func moveUpCompactsAtTop() {
        let result = OrderMover.move(items, selected: [1, 4], by: -10)
        #expect(result.items == [1, 4, 0, 2, 3, 5, 6, 7, 8, 9])
        #expect(result.selected == [0, 1])
    }

    @Test func moveUpPartiallyBlocked() {
        // 첫 항목이 맨 위에 막히면 다음 항목은 바로 아래에 붙는다
        let result = OrderMover.move(items, selected: [0, 2], by: -1)
        #expect(result.items == [0, 2, 1, 3, 4, 5, 6, 7, 8, 9])
    }

    @Test func moveDownKeepsGap() {
        let result = OrderMover.move(items, selected: [0, 2], by: 3)
        #expect(result.items == [1, 3, 4, 0, 5, 2, 6, 7, 8, 9])
        #expect(result.selected == [3, 5])
    }

    @Test func moveToBottom() {
        let result = OrderMover.move(items, selected: [2, 6], by: items.count)
        #expect(result.items == [0, 1, 3, 4, 5, 7, 8, 9, 2, 6])
        #expect(result.selected == [8, 9])
    }

    @Test func emptySelectionDoesNothing() {
        #expect(OrderMover.move(items, selected: [], by: -1).items == items)
    }
}

struct FolderLoaderTests {
    @Test func sortsLikeFinder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["file10.txt", "file2.txt", "File1.txt", ".hidden"] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        try FileManager.default.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: false)

        let items = try FolderLoader.load(folder, showHidden: false)
        #expect(items.map(\.name) == ["File1.txt", "file2.txt", "file10.txt", "sub"])
        #expect(items.last?.isDirectory == true)

        let withHidden = try FolderLoader.load(folder, showHidden: true)
        #expect(withHidden.map(\.name).contains(".hidden"))

        let foldersFirst = try FolderLoader.load(folder, showHidden: false, foldersFirst: true)
        #expect(foldersFirst.map(\.name) == ["sub", "File1.txt", "file2.txt", "file10.txt"])
        let textOrder = try FolderLoader.load(folder, showHidden: false, sort: .lexicographic, foldersFirst: true)
        #expect(textOrder.map(\.name) == ["sub", "File1.txt", "file10.txt", "file2.txt"])
    }
}

struct PathCompleterTests {
    @Test func suggestsMatchingEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appending(path: "Docs"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["doc10.txt", "doc2.txt", "other.txt", ".dotfile"] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        let base = folder.path

        let caseSensitive = try folder.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames ?? false
        let matches = caseSensitive
            ? [base + "/doc2.txt", base + "/doc10.txt"]
            : [base + "/doc2.txt", base + "/doc10.txt", base + "/Docs/"]
        #expect(PathCompleter.suggestions(for: base + "/do") == matches)
        #expect(PathCompleter.suggestions(for: base + "/").count == 4)
        #expect(PathCompleter.suggestions(for: base + "/.") == [base + "/.dotfile"])
        #expect(PathCompleter.suggestions(for: base + "/none").isEmpty)
    }

    @Test func keepsTildeForm() {
        #expect(PathCompleter.suggestions(for: "~").first == "~/")
    }

    @Test func commonPrefixForTab() {
        #expect(PathCompleter.commonPrefix(of: ["/a/doc2.txt", "/a/doc10.txt"]) == "/a/doc")
        #expect(PathCompleter.commonPrefix(of: []) == nil)
    }
}

struct OrderInsertTests {
    private let reference = ["a", "b", "c", "d", "e"]

    @Test func insertsBetweenNeighbors() {
        #expect(OrderMover.insert(["b", "d"], into: ["a", "c", "e"], reference: reference) == ["a", "b", "c", "d", "e"])
    }

    @Test func insertsAfterPredecessorInCustomOrder() {
        #expect(OrderMover.insert(["b"], into: ["e", "c", "a"], reference: reference) == ["e", "c", "a", "b"])
    }

    @Test func insertsAtFrontWhenNoPredecessor() {
        #expect(OrderMover.insert(["a"], into: ["c", "b"], reference: reference) == ["a", "c", "b"])
    }

    @Test func keepsAddedItemsTogetherAtFront() {
        #expect(OrderMover.insert(["b", "a"], into: ["d"], reference: reference) == ["a", "b", "d"])
    }

    @Test func skipsExisting() {
        #expect(OrderMover.insert(["a"], into: ["a"], reference: reference) == ["a"])
    }
}

struct RenameSettingsTests {
    private func settings(_ tokens: [NameToken]) -> RenameSettings {
        var settings = RenameSettings()
        settings.tokens = tokens
        return settings
    }

    @Test func noNameWhenAllTokensEmpty() {
        #expect(RenameSettings().newName(for: "IMG_1234.jpg", index: 0) == nil)
    }

    @Test func emptyValuesAreErrors() {
        let s = settings([NameToken(kind: .text), NameToken(kind: .number)])
        #expect(!s.isValid)
        #expect(s.validationErrors.map(\.slot) == [0, 1])
        #expect(s.newName(for: "IMG_1234.jpg", index: 0) == nil)
    }

    @Test func textOnlyIgnoresOriginalName() {
        let s = settings([NameToken(kind: .text, value: "trip")])
        #expect(s.newName(for: "IMG_1234.jpg", index: 0) == "trip.jpg")
    }

    @Test func joinsTokensWithSeparatorsExceptLast() {
        let s = settings([
            NameToken(kind: .text, value: "trip"),
            NameToken(kind: .none, value: "ignored", separator: "#"),
            NameToken(kind: .number, value: "001", separator: "_"),
            NameToken(kind: .regex, value: "\\d+"),
        ])
        #expect(s.newName(for: "IMG_1234.jpg", index: 4) == "trip-005_1234.jpg")
    }

    @Test func numberStepAndWidth() {
        #expect(NameToken(kind: .number, value: "010", option: "5").resolve(stem: "", index: 2) == "020")
        #expect(NameToken(kind: .number, value: "001", option: "2").resolve(stem: "", index: 3) == "007")
        #expect(NameToken(kind: .number, value: "1").resolve(stem: "", index: 9) == "10")
        #expect(NameToken(kind: .number, value: "10", option: "-3").resolve(stem: "", index: 4) == "-02")
        #expect(NameToken(kind: .number, value: "a1").validationError != nil)
        // 음수 시작: 자릿수는 "-"를 뺀 길이
        #expect(NameToken(kind: .number, value: "-02").resolve(stem: "", index: 0) == "-02")
        #expect(NameToken(kind: .number, value: "-02").resolve(stem: "", index: 3) == "01")
        #expect(NameToken(kind: .number, value: "-").validationError != nil)
        #expect(NameToken(kind: .number, value: "1-").validationError != nil)
        #expect(NameToken(kind: .number, value: "1", option: "0").optionError != nil)
        #expect(NameToken(kind: .number, value: "1", option: "x").optionError != nil)
    }

    @Test func regexUsesFirstGroup() {
        #expect(NameToken(kind: .regex, value: "IMG_(\\d+)").resolve(stem: "IMG_1234", index: 0) == "1234")
        #expect(NameToken(kind: .regex, value: "xyz").resolve(stem: "IMG_1234", index: 0) == nil)
        #expect(NameToken(kind: .regex, value: "(").validationError != nil)
    }
}

struct SeparatorToggleTests {
    @Test func keepsLastSeparatorWhenNotOmitted() {
        var settings = RenameSettings()
        settings.tokens = [NameToken(kind: .text, value: "a"), NameToken(kind: .text, value: "b")]
        settings.omitsLastSeparator = false
        #expect(settings.newName(for: "x.txt", index: 0) == "a-b-.txt")
    }

    @Test func ignoresSeparatorsWhenOff() {
        var settings = RenameSettings()
        settings.tokens = [NameToken(kind: .text, value: "a"), NameToken(kind: .text, value: "b")]
        settings.usesSeparator = false
        #expect(settings.newName(for: "x.txt", index: 0) == "ab.txt")
    }
}

struct FileNameComparerTests {
    @Test func caseHandlingFollowsVolume() {
        #expect(FileNameComparer.key("Photo.JPG", caseSensitive: false) == FileNameComparer.key("photo.jpg", caseSensitive: false))
        #expect(FileNameComparer.key("Photo.JPG", caseSensitive: true) != FileNameComparer.key("photo.jpg", caseSensitive: true))
    }

    @Test func ignoresUnicodeNormalization() {
        let composed = "한글.txt".precomposedStringWithCanonicalMapping
        let decomposed = "한글.txt".decomposedStringWithCanonicalMapping
        #expect(FileNameComparer.key(composed, caseSensitive: true) == FileNameComparer.key(decomposed, caseSensitive: true))
    }
}

@MainActor
struct ApplyFlowTests {
    @Test func applyFillsNewNames() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.txt", "b.txt"] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        let model = BrowserModel(folder: folder)
        // 시작 프리셋과 상관없이 빈 칸에서 시작
        model.renameSettings.tokens = (0..<RenameSettings.tokenCount).map { _ in NameToken() }
        model.addToOrder()
        #expect(model.orderedFiles.count == 2)
        model.renameSettings.tokens[0].kind = .text
        model.renameSettings.tokens[0].value = "trip"
        model.renameSettings.tokens[1].kind = .number
        model.renameSettings.tokens[1].value = "01"
        model.applyRenameSettings()
        #expect(Set(model.newNames.values) == ["trip-01.txt", "trip-02.txt"])
        #expect(model.readyCount == 2)

        // b.txt에는 'a'가 없어 정규식이 일치하지 않는다
        model.renameSettings.tokens[2].kind = .regex
        model.renameSettings.tokens[2].value = "a"
        model.applyRenameSettings()
        #expect(model.regexMisses.count == 1)
        #expect(model.readyCount == 1)
        #expect(model.issueDescription(for: model.orderedFiles[1].url)?.contains("slot 3") == true)

        // Back하면 새 이름과 여섯 칸이 모두 이전에 적용한 규칙으로 돌아간다
        model.backRenameSettings()
        #expect(model.renameSettings.tokens[2].kind == .none)
        #expect(model.appliedSettings?.tokens[2].kind == NameToken.Kind.none)
        #expect(Set(model.newNames.values) == ["trip-01.txt", "trip-02.txt"])
    }
}

struct RegexHighlightTests {
    @Test func reportsRangePerRegexSlot() {
        var settings = RenameSettings()
        settings.tokens[1] = NameToken(kind: .regex, value: "IMG_(\\d+)")
        settings.tokens[3] = NameToken(kind: .regex, value: "[a-z]+$")
        #expect(settings.highlights(for: "IMG_1234_trip.jpg") == [
            NameHighlight(start: 4, length: 4, slot: 1),
            NameHighlight(start: 9, length: 4, slot: 3),
        ])
    }

    @Test func noHighlightWhenNoMatch() {
        var settings = RenameSettings()
        settings.tokens[0] = NameToken(kind: .regex, value: "\\d+")
        #expect(settings.highlights(for: "photo.jpg").isEmpty)
    }

    @Test func regexErrorMessage() {
        #expect(NameToken(kind: .regex, value: "(").validationError != nil)
        #expect(NameToken(kind: .regex, value: "\\d+").validationError == nil)
    }
}

struct FileSortTests {
    private let items = ["file10.txt", "file2.txt", "File1.txt"].map {
        FileItem(url: URL(fileURLWithPath: "/tmp/" + $0), isDirectory: false)
    }

    @Test func naturalSort() {
        #expect(FileSort.natural.sorted(items).map(\.name) == ["File1.txt", "file2.txt", "file10.txt"])
    }

    @Test func lexicographicSort() {
        #expect(FileSort.lexicographic.sorted(items).map(\.name) == ["File1.txt", "file10.txt", "file2.txt"])
    }
}

struct OrderReverseTests {
    private let items = Array(0..<6)

    @Test func reversesAllWhenNoSelection() {
        #expect(OrderMover.reverse(items, selected: []) == [5, 4, 3, 2, 1, 0])
    }

    @Test func reversesContiguousBlockOnly() {
        #expect(OrderMover.reverse(items, selected: [1, 2, 3]) == [0, 3, 2, 1, 4, 5])
    }

    @Test func reversesEachBlockInPlace() {
        let ten = Array(0..<10)
        #expect(OrderMover.reverse(ten, selected: [1, 2, 5, 6, 7]) == [0, 2, 1, 3, 4, 7, 6, 5, 8, 9])
    }

    @Test func reversesAllWhenOnlySingleItemsSelected() {
        #expect(OrderMover.reverse(items, selected: [3]) == [5, 4, 3, 2, 1, 0])
        #expect(OrderMover.reverse(items, selected: [0, 2, 5]) == [5, 4, 3, 2, 1, 0])
    }

    @Test func singleItemsBesideBlockStay() {
        #expect(OrderMover.reverse(items, selected: [0, 2, 3]) == [0, 1, 3, 2, 4, 5])
    }
}

@MainActor
struct PresetTests {
    @Test func loadPresetFillsTokensWithoutApplying() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BrowserModel(folder: folder)
        let preset = RenamePreset(name: "trip", tokens: [NameToken(kind: .text, value: "trip")], usesSeparator: false)
        model.loadPreset(preset)
        #expect(model.renameSettings.tokens.count == RenameSettings.tokenCount)
        #expect(model.renameSettings.tokens[0].value == "trip")
        #expect(model.renameSettings.usesSeparator == false)
        #expect(model.appliedSettings == nil)
    }

    @Test func summaryListsUsedTokens() {
        let preset = RenamePreset(
            name: "p",
            tokens: [NameToken(kind: .text, value: "trip"), NameToken(), NameToken(kind: .number)],
            usesSeparator: true
        )
        #expect(preset.summary == "Text trip · Number")
    }
}

struct AddExtensionTests {
    @Test func addsOnlyToFilesWithoutExtension() {
        var settings = RenameSettings()
        settings.tokens[0] = NameToken(kind: .addExtension, value: "pdf")
        settings.tokens[1] = NameToken(kind: .removeExtension, value: "bak")
        #expect(settings.newName(for: "invoice", index: 0) == "invoice.pdf")
        #expect(settings.newName(for: "a.txt", index: 0) == "a.txt")
        // 지운 결과에 다시 붙이지 않는다 (규칙은 한 번만)
        #expect(settings.newName(for: "b.bak", index: 0) == "b")
        #expect(settings.buildNewName(for: "invoice", index: 0)?.highlights == [NameHighlight(start: 8, length: 3, slot: 0)])
        #expect(settings.isValid)
        #expect(RenameSettings.extensionCounts(of: ["invoice", "a.txt", "b"])[""] == 2)
        // Add Ext끼리는 겹친다. Change Ext txt와는 겹치지 않는다
        settings.tokens[2] = NameToken(kind: .changeExtension, value: "pdf", option: "txt")
        #expect(settings.isValid)
        settings.tokens[3] = NameToken(kind: .addExtension, value: "txt")
        #expect(RenameSettings.extensionConflicts(in: settings.tokens) == [0: 3, 3: 0])
    }
}

struct MissingFolderTests {
    @MainActor @Test func goesToNearestExistingFolder() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "wer-missing-\(UUID().uuidString)")
        let deep = base.appending(path: "a/b")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let model = BrowserModel(folder: deep)
        try FileManager.default.removeItem(at: base.appending(path: "a"))
        #expect(model.isFolderMissing)
        model.goToNearestExistingFolder()
        #expect(model.folder.standardizedFileURL.path == base.standardizedFileURL.path)
        #expect(!model.isFolderMissing)
    }
}

struct FileDropTests {
    @MainActor @Test func droppedPathIsDetected() throws {
        let path = FileManager.default.temporaryDirectory.path
        #expect(BrowserModel.droppedPath(old: "wer-", new: "wer-" + path) == URL(fileURLWithPath: path))
        #expect(BrowserModel.droppedPath(old: "", new: "file://" + path)?.path == URL(fileURLWithPath: path).path)
        // 일반 입력이나 없는 경로는 그대로
        #expect(BrowserModel.droppedPath(old: "wer", new: "wer-") == nil)
        #expect(BrowserModel.droppedPath(old: "", new: "/no/such/path") == nil)
    }
}

struct DefaultPresetTests {
    @Test func oldFiveSlotPresetIsPaddedToSix() throws {
        let old = RenamePreset(name: "old", tokens: (0..<5).map { _ in NameToken(kind: .text, value: "a") }, usesSeparator: true)
        let decoded = try JSONDecoder().decode(RenamePreset.self, from: JSONEncoder().encode(old))
        #expect(decoded.tokens.count == RenameSettings.tokenCount)
        #expect(decoded.tokens.last?.kind == NameToken.Kind.none)
    }

    @Test func builtInDefaultExampleName() {
        var settings = RenameSettings()
        RenamePreset.builtInDefault.apply(to: &settings)
        #expect(settings.newName(for: "IMG_12.jpg", index: 0) == "wer-rename-0012-0001.jpg")
        // Default는 확장자를 바꾸지 않는다
        #expect(settings.newName(for: "IMG_12.jpeg", index: 0) == "wer-rename-0012-0001.jpeg")
        #expect(settings.isValid)
    }

    @Test func builtInFixExtensionsChangesOnlyExtensions() {
        var settings = RenameSettings()
        RenamePreset.builtInFixExtensions.apply(to: &settings)
        #expect(settings.newName(for: "IMG_12.jpeg", index: 0) == "IMG_12.jpg")
        // 바뀐 확장자는 Change Ext 칸(0번) 색으로 칠한다
        #expect(settings.buildNewName(for: "IMG_12.jpeg", index: 0)?.highlights == [NameHighlight(start: 7, length: 3, slot: 0)])
        #expect(settings.newName(for: "report.docx.bak", index: 0) == "report.docx")
        #expect(settings.newName(for: "IMG_sample", index: 0) == "IMG_sample.jpg")
        #expect(settings.newName(for: "a.png", index: 0) == "a.png")
        #expect(settings.isValid)
    }

    @Test func textSuffixAppendedOrIgnored() {
        #expect(NameToken(kind: .text, value: "wer-", option: "rename").resolve(stem: "a", index: 0) == "wer-rename")
        #expect(NameToken(kind: .text, value: "wer-", option: "").resolve(stem: "a", index: 0) == "wer-")
        #expect(NameToken(kind: .text, value: "a", option: "b/c").optionError != nil)
        #expect(NameToken(kind: .text, value: "", option: "rename").validationError == nil)
        #expect(NameToken(kind: .text, value: "", option: "rename").resolve(stem: "a", index: 0) == "rename")
        #expect(NameToken(kind: .text, value: "", option: "").validationError != nil)
    }

    @Test func extensionTokens() {
        var settings = RenameSettings()
        settings.tokens[2] = NameToken(kind: .removeExtension, value: "doc")
        settings.tokens[4] = NameToken(kind: .changeExtension, value: "jpeg", option: "jpg")
        // 확장자 조각만 있으면 이름은 그대로
        #expect(settings.newName(for: "a.doc.doc", index: 0) == "a.doc")
        #expect(settings.newName(for: "b.jpeg", index: 0) == "b.jpg")
        #expect(settings.newName(for: "c.png", index: 0) == "c.png")
        // 대소문자까지 완전 일치
        #expect(settings.newName(for: "d.JPEG", index: 0) == "d.JPEG")
        #expect(RenameSettings.extensionCounts(of: ["a.jpeg", "b.JPEG", "c.jpeg", "d"]) == ["jpeg": 2, "JPEG": 1, "": 1])
        // 이름 조각과 함께 쓰면 순서·구분자와 상관없이 확장자만 바꾼다
        settings.tokens[3] = NameToken(kind: .text, value: "x")
        #expect(settings.newName(for: "b.jpeg", index: 0) == "x.jpg")
        #expect(NameToken(kind: .changeExtension, value: "").validationError != nil)
        #expect(NameToken(kind: .changeExtension, value: ".doc").validationError != nil)
        #expect(NameToken(kind: .changeExtension, value: "doc", option: "a.b").optionError != nil)
        #expect(NameToken(kind: .changeExtension, value: "doc", option: "").optionError != nil)
        #expect(NameToken(kind: .removeExtension, value: "doc").optionError == nil)
        // 대상과 바꿀 확장자가 같으면 경고만 (대소문자 구분)
        #expect(NameToken(kind: .changeExtension, value: "md", option: "md").warning != nil)
        #expect(NameToken(kind: .changeExtension, value: "MD", option: "md").warning == nil)
        #expect(settings.isValid)
        // 빈 칸은 Apply는 막지만 프리셋 저장(형식 오류 없음)은 막지 않는다
        settings.tokens[1] = NameToken(kind: .removeExtension)
        #expect(settings.tokens[1].needsInput)
        #expect(!settings.isValid)
        #expect(settings.formatErrors.isEmpty)
        settings.tokens[1] = NameToken(kind: .regex, value: "(")
        #expect(!settings.formatErrors.isEmpty)
        settings.tokens[1] = NameToken()
        // 대소문자가 다르면 겹치지 않는다
        settings.tokens[0] = NameToken(kind: .changeExtension, value: "DOC", option: "md")
        #expect(settings.isValid)
        // 대상 확장자가 같으면 (종류 무관) 두 칸 모두 오류
        settings.tokens[0] = NameToken(kind: .changeExtension, value: "doc", option: "md")
        #expect(RenameSettings.extensionConflicts(in: settings.tokens) == [0: 2, 2: 0])
        #expect(!settings.isValid)
    }

    @Test func textAndSeparatorRejectFileNameCharacters() {
        #expect(NameToken(kind: .text, value: "a/b").validationError != nil)
        #expect(NameToken(kind: .text, value: "a:b").validationError != nil)
        #expect(NameToken(kind: .text, value: "a\u{0007}b").validationError != nil)
        #expect(NameToken(kind: .text, value: "trip").validationError == nil)
        #expect(NameToken(kind: .text, value: "a", separator: "/").separatorError != nil)
        #expect(NameToken(kind: .text, value: "a", separator: "").separatorError == nil)
        // None은 검사하지 않는다
        #expect(NameToken(kind: .none, value: "", separator: "/").separatorError == nil)
    }

    @Test func matchesDetectsModification() {
        let preset = RenamePreset.builtInDefault
        var settings = RenameSettings()
        preset.apply(to: &settings)
        #expect(preset.matches(settings))
        settings.tokens[0].value = "trip"
        #expect(!preset.matches(settings))
        // 복사 설정은 규칙이 아니라 비교하지 않는다
        preset.apply(to: &settings)
        settings.isCopy = true
        #expect(preset.matches(settings))
    }
}

@MainActor
struct RenameFlowTests {
    private func makeModel(files: [String]) throws -> (BrowserModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in files {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        let model = BrowserModel(folder: folder)
        model.renameSettings.tokens = (0..<RenameSettings.tokenCount).map { _ in NameToken() }
        model.addToOrder()
        return (model, folder)
    }

    @Test func flagsLongAndHiddenNames() throws {
        let (model, folder) = try makeModel(files: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }
        model.renameSettings.tokens[0] = NameToken(kind: .text, value: String(repeating: "가", count: 90))
        model.renameSettings.tokens[1] = NameToken(kind: .number, value: "1")
        model.applyRenameSettings()
        #expect(model.nameIssues.errors.count == 2)

        model.renameSettings.tokens[0] = NameToken(kind: .text, value: ".hidden")
        model.applyRenameSettings()
        #expect(model.nameIssues.errors.isEmpty)
        #expect(model.nameIssues.warnings.count == 2)
    }

    @Test func applyIsBlockedByInvalidSlot() throws {
        let (model, folder) = try makeModel(files: ["a.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }
        model.renameSettings.tokens[0] = NameToken(kind: .text, value: "")
        model.applyRenameSettings()
        #expect(model.appliedSettings == nil)
    }

    @Test func backRestoresPresetLoad() throws {
        let (model, folder) = try makeModel(files: ["a.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }
        model.renameSettings.tokens[0] = NameToken(kind: .text, value: "mine")
        model.applyRenameSettings()
        let beforeLoad = model.renameSettings.tokens

        model.loadPreset(RenamePreset(name: "other", tokens: [NameToken(kind: .text, value: "other")], usesSeparator: true))
        #expect(model.renameSettings.tokens[0].value == "other")
        #expect(model.appliedSettings?.tokens[0].value == "mine")

        model.backRenameSettings()
        #expect(model.renameSettings.tokens == beforeLoad)
        #expect(model.appliedSettings?.tokens[0].value == "mine")

        model.backRenameSettings()
        #expect(model.appliedSettings == nil)
    }
}


@MainActor
struct RunRenameTests {
    private func makeModel(files: [String]) throws -> (BrowserModel, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in files {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        let model = BrowserModel(folder: folder)
        model.renameSettings.tokens = (0..<RenameSettings.tokenCount).map { _ in NameToken() }
        model.renameSettings.isCopy = false
        model.addToOrder()
        return (model, folder)
    }

    @Test func planSkipsUnchangedNames() throws {
        let (model, folder) = try makeModel(files: ["trip.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }
        model.renameSettings.tokens[0] = NameToken(kind: .regex, value: "trip|b")
        model.renameSettings.tokens[1] = NameToken(kind: .text, value: "x")
        model.applyRenameSettings()
        #expect(model.makePlan().items.map(\.destination.lastPathComponent).sorted() == ["b-x.txt", "trip-x.txt"])

        model.renameSettings.tokens[1] = NameToken()
        model.applyRenameSettings()
        // 새 이름이 지금 이름과 같으면 뺀다
        #expect(model.makePlan().items.isEmpty)
    }

    @Test func preflightFindsExistingAndMissingFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.txt", "taken.txt"] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        let plan = RenamePlan(mode: .rename, items: [
            RenamePlan.Item(source: folder.appending(path: "a.txt"), destination: folder.appending(path: "taken.txt")),
            RenamePlan.Item(source: folder.appending(path: "gone.txt"), destination: folder.appending(path: "new.txt")),
        ])
        let issues = RenameExecutor().preflight(plan)
        #expect(issues.count == 2)
    }

    @Test func preflightAllowsSwapWithinPlan() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.txt", "b.txt"] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        let a = folder.appending(path: "a.txt"), b = folder.appending(path: "b.txt")
        let plan = RenamePlan(mode: .rename, items: [
            RenamePlan.Item(source: a, destination: b),
            RenamePlan.Item(source: b, destination: a),
        ])
        #expect(RenameExecutor().preflight(plan).isEmpty)
    }

    @Test func runRenamesFilesAndUndoRestores() async throws {
        let (model, folder) = try makeModel(files: ["a.txt", "b.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }
        model.renameSettings.tokens[0] = NameToken(kind: .text, value: "trip")
        model.renameSettings.tokens[1] = NameToken(kind: .number, value: "1")
        model.applyRenameSettings()
        #expect(model.canRun)

        await model.performRun(model.makePlan())
        #expect(Self.names(in: folder) == ["trip-1.txt", "trip-2.txt"])
        #expect(model.orderedFiles.isEmpty)
        #expect(model.appliedSettings == nil)
        #expect(model.selection.count == 2)
        #expect(model.canUndoRun)

        await model.undoRun()
        #expect(Self.names(in: folder) == ["a.txt", "b.txt"])
        #expect(model.orderedFiles.count == 2)
        #expect(model.appliedSettings != nil)
        #expect(!model.canUndoRun)
    }

    static func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

}

@MainActor
struct RenameExecutorTests {
    private func makeFolder(_ files: [String: String]) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
        }
        return folder
    }

    private func content(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test func swapsNamesThroughTemporaryNames() async throws {
        let folder = try makeFolder(["a.txt": "A", "b.txt": "B"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let a = folder.appending(path: "a.txt"), b = folder.appending(path: "b.txt")
        let plan = RenamePlan(mode: .rename, items: [RenamePlan.Item(source: a, destination: b), RenamePlan.Item(source: b, destination: a)])
        let outcome = await RenameExecutor().execute(plan) { _ in }
        #expect(outcome.succeeded)
        #expect(content(a) == "B")
        #expect(content(b) == "A")
        #expect(RenameJournal.load() == nil)
    }

    @Test func revertsEverythingWhenOneFails() async throws {
        let folder = try makeFolder(["a.txt": "A", "b.txt": "B", "taken.txt": "T"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let plan = RenamePlan(mode: .rename, items: [
            RenamePlan.Item(source: folder.appending(path: "a.txt"), destination: folder.appending(path: "new-a.txt")),
            // 사전 검사를 건너뛰어, 이미 있는 이름으로 바꾸다 실패하게 만든다
            RenamePlan.Item(source: folder.appending(path: "b.txt"), destination: folder.appending(path: "taken.txt")),
        ])
        let outcome = await RenameExecutor().execute(plan) { _ in }
        #expect(!outcome.succeeded)
        #expect(outcome.unreverted.isEmpty)
        #expect(RunRenameTests.names(in: folder) == ["a.txt", "b.txt", "taken.txt"])
        #expect(content(folder.appending(path: "taken.txt")) == "T")
    }

    @Test func copyFailureRemovesCopiesButKeepsFolder() async throws {
        let folder = try makeFolder(["a.txt": "A", "b.txt": "B"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appending(path: "rename")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "X".write(to: destination.appending(path: "copy-b.txt"), atomically: true, encoding: .utf8)
        let plan = RenamePlan(mode: .copy(destination: destination), items: [
            RenamePlan.Item(source: folder.appending(path: "a.txt"), destination: destination.appending(path: "copy-a.txt")),
            RenamePlan.Item(source: folder.appending(path: "b.txt"), destination: destination.appending(path: "copy-b.txt")),
        ])
        // 테스트 파일이 실제 휴지통으로 가지 않도록 영구 삭제로
        var executor = RenameExecutor()
        executor.removesCopiesToTrash = false
        var log: [RenameLogEntry] = []
        let outcome = await executor.execute(plan) { log.append($0) }
        #expect(log.contains { $0.detail == "Deleted copy" })
        #expect(!outcome.succeeded)
        #expect(RunRenameTests.names(in: destination) == ["copy-b.txt"])
        #expect(content(destination.appending(path: "copy-b.txt")) == "X")
        #expect(RunRenameTests.names(in: folder) == ["a.txt", "b.txt", "rename"])
    }

    @Test func copyCreatesFolderAndKeepsOriginals() async throws {
        let folder = try makeFolder(["a.txt": "A"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appending(path: "rename")
        let plan = RenamePlan(mode: .copy(destination: destination), items: [
            RenamePlan.Item(source: folder.appending(path: "a.txt"), destination: destination.appending(path: "new.txt")),
        ])
        let outcome = await RenameExecutor().execute(plan) { _ in }
        #expect(outcome.succeeded)
        #expect(content(destination.appending(path: "new.txt")) == "A")
        #expect(content(folder.appending(path: "a.txt")) == "A")
    }

    @Test func recoverRestoresTemporaryNames() throws {
        let folder = try makeFolder([".wer-tmp-test": "A"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = RenameJournal(isCopy: false, entries: [
            RenameJournal.Entry(source: folder.appending(path: "a.txt"), temp: folder.appending(path: ".wer-tmp-test"),
                                destination: folder.appending(path: "new.txt")),
        ])
        #expect(RenameExecutor().recover(journal).isEmpty)
        #expect(content(folder.appending(path: "a.txt")) == "A")
    }
}

struct RegexPadTests {
    @Test func padsExtractedValueOnTheLeft() {
        let token = NameToken(kind: .regex, value: "\\((\\d+)\\)", option: "0000")
        #expect(token.resolve(stem: "img-2020(1)", index: 0) == "0001")
        #expect(token.resolve(stem: "img-2020(10)", index: 0) == "0010")
        #expect(token.resolve(stem: "img-2020(12345)", index: 0) == "12345")
        #expect(NameToken(kind: .regex, value: "\\d+", option: "").resolve(stem: "a7", index: 0) == "7")
    }

    @Test func padMustRepeatOneValidCharacter() {
        #expect(NameToken(kind: .regex, value: "a", option: "0_0").optionError != nil)
        #expect(NameToken(kind: .regex, value: "a", option: "//").optionError != nil)
        #expect(NameToken(kind: .regex, value: "a", option: "___").optionError == nil)
    }

    @Test func legacyNumberValueIsSplitWhenDecoded() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000009","kind":"number","value":"0001 step 2","separator":"-"}"#
        let token = try JSONDecoder().decode(NameToken.self, from: Data(json.utf8))
        #expect(token.value == "0001")
        #expect(token.option == "2")
    }
}


/// 한글 이름. macOS에서는 자모가 분리된(NFD) 이름의 파일도 흔하다
@MainActor
struct KoreanNameTests {
    private let nfdPhoto = "사진_001".decomposedStringWithCanonicalMapping + ".jpg"

    @Test func textTokenMakesKoreanName() {
        var settings = RenameSettings()
        settings.tokens[0] = NameToken(kind: .text, value: "여행")
        settings.tokens[1] = NameToken(kind: .number, value: "01")
        #expect(settings.newName(for: "IMG_1.jpg", index: 0) == "여행-01.jpg")
    }

    @Test func regexMatchesDecomposedName() {
        var settings = RenameSettings()
        settings.tokens[0] = NameToken(kind: .regex, value: "[가-힣]+")
        #expect(settings.newName(for: nfdPhoto, index: 0) == "사진.jpg")
        settings.tokens[0] = NameToken(kind: .regex, value: "사진")
        #expect(settings.newName(for: nfdPhoto, index: 0) == "사진.jpg")
        #expect(settings.highlights(for: nfdPhoto) == [NameHighlight(start: 0, length: 2, slot: 0)])
    }

    @Test func decomposedNameIsNotReportedAsRegexMiss() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        FileManager.default.createFile(atPath: folder.appending(path: nfdPhoto).path, contents: nil)
        let model = BrowserModel(folder: folder)
        model.renameSettings.tokens = (0..<RenameSettings.tokenCount).map { _ in NameToken() }
        model.addToOrder()
        model.renameSettings.tokens[0] = NameToken(kind: .regex, value: "[가-힣]+")
        model.applyRenameSettings()
        #expect(model.regexMisses.isEmpty)
    }

    @Test func newNameConflictsWithDecomposedExistingName() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.jpg", "사진".decomposedStringWithCanonicalMapping + ".jpg"] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        let model = BrowserModel(folder: folder)
        model.renameSettings.tokens = (0..<RenameSettings.tokenCount).map { _ in NameToken() }
        model.renameSettings.isCopy = false
        model.selection = Set(model.items.filter { $0.name == "a.jpg" }.map(\.url))
        model.addToOrder()
        model.renameSettings.tokens[0] = NameToken(kind: .text, value: "사진")
        model.applyRenameSettings()
        #expect(model.renameConflicts.order.count == 1)
        #expect(!model.canRun)
    }

    @Test func runRenamesToKoreanAndUndoRestores() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["a.txt", nfdPhoto] {
            FileManager.default.createFile(atPath: folder.appending(path: name).path, contents: nil)
        }
        let model = BrowserModel(folder: folder)
        model.renameSettings.tokens = (0..<RenameSettings.tokenCount).map { _ in NameToken() }
        model.renameSettings.isCopy = false
        model.addToOrder()
        model.renameSettings.tokens[0] = NameToken(kind: .text, value: "여행")
        model.renameSettings.tokens[1] = NameToken(kind: .number, value: "1")
        model.applyRenameSettings()
        #expect(model.canRun)

        await model.performRun(model.makePlan())
        let renamed = RunRenameTests.names(in: folder).map(\.precomposedStringWithCanonicalMapping)
        #expect(Set(renamed) == ["여행-1.txt", "여행-2.jpg"])

        await model.undoRun()
        let restored = RunRenameTests.names(in: folder).map(\.precomposedStringWithCanonicalMapping)
        #expect(Set(restored) == ["a.txt", "사진_001.jpg"])
    }
}


struct EmptyFileSpecTests {
    private func spec(min: String = "", max: String = "", unit: EmptyFileSpec.Unit = .b, count: String, name: String = "", ext: String = "") -> EmptyFileSpec {
        var spec = EmptyFileSpec()
        spec.min = min
        spec.max = max
        spec.unit = unit
        spec.count = count
        spec.name = name
        spec.ext = ext
        return spec
    }

    @Test func evenSplitIncludesBothEnds() {
        #expect(spec(min: "0", max: "100", count: "5").sizes == [0, 25, 50, 75, 100])
        #expect(spec(min: "1", max: "10", unit: .mib, count: "2").sizes == [1_048_576, 10_485_760])
    }

    @Test func minOnlyMakesSameSizes() {
        #expect(spec(min: "1.5", unit: .kb, count: "3").sizes == [1500, 1500, 1500])
    }

    @Test func emptyFieldsUseDefaults() {
        // Max가 비고 Min도 없으면 10, Count가 비면 1
        #expect(spec(count: "").sizes == [10])
        #expect(spec(unit: .mib, count: "2").sizes == [10_485_760, 10_485_760])
        #expect(spec(max: "5", count: "").sizes == [5])
        #expect(EmptyFileSpec().fileNames == ["wer-create-10485760"])
        #expect(spec(max: "3", count: "1", name: "  ").fileNames == ["wer-create-3"])
    }

    @Test func oneFileIgnoresMin() {
        #expect(spec(min: "1", max: "9", count: "1").sizes == [9])
        // Min이 꺼져 있으면 Min 오류도, Min > Max 오류도 보지 않는다
        #expect(spec(min: "x", max: "9", count: "1").errors.isEmpty)
        #expect(spec(min: "20", max: "9", count: "1").errors.isEmpty)
        // 1개에 Max가 비면 Min이 아니라 기본값 10
        #expect(spec(min: "2", count: "1").sizes == [10])
    }

    @Test func decimalsRoundDown() {
        #expect(spec(max: "0.0001", unit: .kib, count: "1").sizes == [0])
        #expect(spec(max: "1.9999", unit: .kb, count: "1").sizes == [1999])
    }

    @Test func invalidInputs() {
        #expect(spec(max: "1.5", unit: .b, count: "1").error(for: .max) != nil)
        #expect(spec(min: "10", max: "5", count: "2").error(for: .max) != nil)
        #expect(spec(max: "1e3", count: "1").error(for: .max) != nil)
        #expect(spec(max: "2", unit: .gib, count: "0").error(for: .count) != nil)
        #expect(spec(max: "1025", unit: .gib, count: "1").error(for: .max) != nil)
        #expect(spec(max: "1", count: "1", ext: "a.b").error(for: .ext) != nil)
        #expect(spec(max: "1", count: "1", name: "a/b").error(for: .name) != nil)
        #expect(spec(max: "3", count: "abc").sizes == nil)
    }

    @Test func namesArePaddedBySize() {
        #expect(spec(min: "5", max: "1000", count: "2", name: "up", ext: "bin").fileNames == ["up-0005.bin", "up-1000.bin"])
        #expect(spec(max: "7", count: "1").fileNames == ["wer-create-7"])
    }

    @Test func sameSizesGetSuffix() {
        #expect(spec(max: "7", count: "2", ext: "dat").fileNames == ["wer-create-7-1.dat", "wer-create-7-2.dat"])
        #expect(spec(min: "1", max: "2", count: "3").fileNames == ["wer-create-1", "wer-create-2-1", "wer-create-2-2"])
        // 같은 용량 번호도 자릿수를 맞춘다
        let names = spec(max: "5", count: "12").fileNames
        #expect(names?.first == "wer-create-5-01")
        #expect(names?.last == "wer-create-5-12")
    }

    @Test func savedSpecDecodesMissingKeys() throws {
        let decoded = try JSONDecoder().decode(EmptyFileSpec.self, from: Data(#"{"max":"5"}"#.utf8))
        #expect(decoded.max == "5")
        #expect(decoded.unit == .mib)
    }

    @Test func createsSizedFilesAndNeverOverwrites() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "wer-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for fill in EmptyFileSpec.Fill.allCases {
            var s = spec(min: "0", max: "3", unit: .mib, count: "3", name: fill.rawValue)
            s.fill = fill
            let plan = try #require(s.plan(in: folder))
            let created = try await EmptyFileCreator.create(plan) { _ in }
            #expect(created.count == 3)
            for file in plan.files {
                let size = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                #expect(Int64(size ?? -1) == file.size)
            }
            // 같은 이름이 있으면 실패하고, 그 전에 만든 파일은 남기지 않는다
            await #expect(throws: EmptyFileCreator.Failure.self) {
                _ = try await EmptyFileCreator.create(plan) { _ in }
            }
            #expect(await EmptyFileCreator.existing(plan.files.map(\.url)).count == 3)
        }
    }
}

struct DateTokenTests {
    /// 2024-05-01 13:22:10 (로컬 시간)
    private let date = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2024, month: 5, day: 1, hour: 13, minute: 22, second: 10)
    )!

    private func settings(_ tokens: [NameToken]) -> RenameSettings {
        var settings = RenameSettings()
        settings.tokens = tokens + (tokens.count..<RenameSettings.tokenCount).map { _ in NameToken() }
        return settings
    }

    @Test func formatsCreatedAndModifiedDates() {
        let settings = settings([
            NameToken(kind: .createdDate, value: "yyyy-MM-dd"),
            NameToken(kind: .modifiedDate, value: "yyyyMMdd_HHmmss"),
        ])
        let dates = FileDates(created: date, modified: date.addingTimeInterval(86_400))
        #expect(settings.newName(for: "IMG_1.jpg", index: 0, dates: dates) == "2024-05-01-20240502_132210.jpg")
        #expect(settings.usesDates)
    }

    @Test func quotedTextIsKept() {
        let token = NameToken(kind: .createdDate, value: "yyyy'y'MM")
        #expect(token.validationError == nil)
        #expect(token.resolve(stem: "a", index: 0, dates: FileDates(created: date)) == "2024y05")
    }

    @Test func missingDateUsesFallback() {
        let settings = settings([
            NameToken(kind: .text, value: "a"),
            NameToken(kind: .createdDate, value: "yyyy"),
            NameToken(kind: .text, value: "b"),
        ])
        // 빈 값이면 구분자만 남는다
        #expect(settings.newName(for: "x.jpg", index: 0) == "a--b.jpg")
        var withFallback = settings
        withFallback.tokens[1].option = "nodate"
        let built = withFallback.buildNewName(for: "x.jpg", index: 0)
        #expect(built?.name == "a-nodate-b.jpg")
        #expect(built?.highlights[1] == NameHighlight(start: 2, length: 6, slot: 1, isFallback: true))
        // 날짜를 찾으면 밑줄이 없다
        let found = withFallback.buildNewName(for: "x.jpg", index: 0, dates: FileDates(created: date))
        #expect(found?.highlights[1].isFallback == false)
    }

    @Test func trailingSeparatorStaysWhenLastIsEmpty() {
        let settings = settings([
            NameToken(kind: .text, value: "a"),
            NameToken(kind: .modifiedDate, value: "yyyy"),
        ])
        #expect(settings.newName(for: "x.jpg", index: 0) == "a-.jpg")
    }

    @Test func formatErrors() {
        #expect(NameToken(kind: .createdDate, value: "").needsValue)
        #expect(NameToken(kind: .createdDate, value: "HH:mm").validationError == NameToken.invalidCharacterMessage)
        #expect(NameToken(kind: .createdDate, value: "yyyy-Q").validationError != nil)
        #expect(NameToken(kind: .createdDate, value: "yyyy'at").validationError != nil)
        #expect(NameToken(kind: .createdDate, value: "'abc'").validationError != nil)
        #expect(NameToken(kind: .createdDate, value: "---").validationError != nil)
        #expect(NameToken(kind: .createdDate, value: "yyyy", option: "a/b").optionError != nil)
        #expect(NameToken(kind: .createdDate, value: "yyyy", option: "").optionError == nil)
        #expect(!settings([NameToken(kind: .createdDate, value: "")]).isValid)
        #expect(settings([NameToken(kind: .createdDate, value: "yyyyMMdd")]).isValid)
    }

    @Test func formatWarnings() {
        #expect(NameToken(kind: .createdDate, value: "yyyy-mm-dd").valueWarning != nil)
        #expect(NameToken(kind: .createdDate, value: "YYYY-MM-dd").valueWarning != nil)
        #expect(NameToken(kind: .createdDate, value: "yyyy-MM-DD").valueWarning != nil)
        #expect(NameToken(kind: .createdDate, value: "hh-mm").valueWarning != nil)
        #expect(NameToken(kind: .createdDate, value: "yyyy-MM-dd_HHmm").valueWarning == nil)
        #expect(NameToken(kind: .createdDate, value: "hhmm a").valueWarning == nil)
        // 경고는 Apply를 막지 않는다
        #expect(settings([NameToken(kind: .createdDate, value: "yyyy-mm-dd")]).isValid)
    }

    @Test func usesEnglishNames() {
        // 요일·AM/PM은 시스템 언어와 관계없이 영어
        let token = NameToken(kind: .createdDate, value: "EEE a")
        #expect(token.resolve(stem: "a", index: 0, dates: FileDates(created: date)) == "Wed PM")
    }

    @Test func onlyMissingDateGivesEmptyName() {
        let settings = settings([NameToken(kind: .createdDate, value: "yyyy")])
        #expect(settings.newName(for: "x", index: 0) == "")
    }
}

struct MediaInfoTests {
    @Test func parsesExifDateAsLocalTime() {
        let date = MediaInfoReader.exifDate("2024:05:01 13:22:10")
        let expected = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2024, month: 5, day: 1, hour: 13, minute: 22, second: 10)
        )
        #expect(date == expected)
        #expect(MediaInfoReader.exifDate("0000:00:00 00:00:00") == nil)
    }

    @Test func kindFromExtension() {
        #expect(MediaInfoReader.kind(of: URL(filePath: "/a/IMG_1.HEIC")) == .image)
        #expect(MediaInfoReader.kind(of: URL(filePath: "/a/clip.mov")) == .audiovisual)
        #expect(MediaInfoReader.kind(of: URL(filePath: "/a/song.mp3")) == .audiovisual)
        #expect(MediaInfoReader.kind(of: URL(filePath: "/a/doc.txt")) == nil)
    }

    @MainActor @Test func countText() {
        #expect(FileInfoView.count(1, "file") == "1 file")
        #expect(FileInfoView.count(3, "folder") == "3 folders")
    }
}

struct KindTitleTests {
    @MainActor @Test func shortensFirstWordOnly() {
        let titles = TokenGridEditor.shortTitles(for: "Created Date")
        #expect(titles.first == "Created Date")
        #expect(titles.contains("Cre… Date"))
        #expect(titles.suffix(2) == ["C… Date", "Date"])
        #expect(TokenGridEditor.shortTitles(for: "Number") == ["Number"])
    }
}

struct TakenDateTests {
    private let date = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2023, month: 12, day: 31, hour: 23, minute: 59, second: 0)
    )!

    @Test func usesTakenDateOrFallback() {
        var settings = RenameSettings()
        settings.tokens[0] = NameToken(kind: .takenDate, value: "yyyyMMdd", option: "nodate")
        settings.tokens[1] = NameToken(kind: .number, value: "01")
        #expect(settings.usesMediaMetadata)
        #expect(settings.newName(for: "IMG_1.HEIC", index: 0, dates: FileDates(taken: date)) == "20231231-01.HEIC")
        // 등록일·수정일이 있어도 촬영일이 없으면 기본값
        let other = FileDates(created: date, modified: date)
        #expect(settings.newName(for: "IMG_1.HEIC", index: 0, dates: other) == "nodate-01.HEIC")
        #expect(!RenameSettings().usesMediaMetadata)
    }

    @Test func readResultInfo() {
        #expect(MediaReadResult.loaded(MediaInfo(taken: date)).info?.taken == date)
        #expect(MediaReadResult.timedOut.info == nil)
        #expect(MediaReadResult.notDownloaded.info == nil)
    }

    @Test func readsImageWithoutExif() async throws {
        // EXIF가 없는 PNG는 크기만 있고 촬영일은 없다
        let url = FileManager.default.temporaryDirectory.appending(path: "wer-test-\(UUID().uuidString).png")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVR4nGP4z8DwHwQZGAAZ+wP9c3XDqgAAAABJRU5ErkJggg==")!
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = await MediaInfoReader.readInBackground(url)
        #expect(result.info?.taken == nil)
        #expect(result.info?.pixelSize == CGSize(width: 2, height: 1))
    }
}

struct ReplaceTokenTests {
    private func name(_ token: NameToken, _ original: String) -> String? {
        var settings = RenameSettings()
        settings.tokens[0] = token
        return settings.newName(for: original, index: 0)
    }

    @Test func replacesEveryMatch() {
        #expect(name(NameToken(kind: .replace, value: #"\s+"#, option: "-"), "IMG 2024  05.jpg") == "IMG-2024-05.jpg")
        // 비우면 지운다
        #expect(name(NameToken(kind: .replace, value: "^IMG_"), "IMG_12.jpg") == "12.jpg")
        // 그룹으로 순서 바꾸기
        #expect(name(NameToken(kind: .replace, value: "^(.+)_(.+)$", option: "$2_$1"), "a_b.txt") == "b_a.txt")
        // 일치하지 않으면 그대로
        #expect(name(NameToken(kind: .replace, value: "zzz", option: "x"), "photo.jpg") == "photo.jpg")
        // 자모가 분리된 한글 이름도 찾는다
        let nfd = "사진 1.jpg".decomposedStringWithCanonicalMapping
        #expect(name(NameToken(kind: .replace, value: "사진", option: "photo"), nfd) == "photo 1.jpg")
    }

    @Test func validation() {
        #expect(NameToken(kind: .replace, value: "").needsValue)
        #expect(NameToken(kind: .replace, value: "(").validationError != nil)
        #expect(NameToken(kind: .replace, value: "a", option: "b/c").optionError != nil)
        #expect(NameToken(kind: .replace, value: "(a)", option: "$2").warning != nil)
        #expect(NameToken(kind: .replace, value: "(a)", option: "$1").warning == nil)
        #expect(NameToken(kind: .replace, value: "(a)", option: #"\$5"#).warning == nil)
    }

    @Test func highlightsAllMatches() {
        var settings = RenameSettings()
        settings.tokens[0] = NameToken(kind: .replace, value: "a", option: "b")
        #expect(settings.highlights(for: "aXa.txt").count == 2)
    }
}

struct RegexGroupTests {
    private func value(_ option: String, _ stem: String = "IMG_5_7") -> String? {
        NameToken(kind: .regex, value: #"IMG_(\d+)_(\d+)"#, option: option).resolve(stem: stem, index: 0)
    }

    @Test func picksGroup() {
        #expect(value("") == "5")
        #expect(value("000") == "005")
        #expect(value("$2") == "7")
        #expect(value("$2:") == "7")
        #expect(value("$2:000") == "007")
        #expect(value("$0") == "IMG_5_7")
    }

    @Test func parsesOption() {
        #expect(NameToken.regexOption("$$$$")?.group == nil)
        #expect(NameToken.regexOption("$$$$")?.pad == "$$$$")
        #expect(NameToken.regexOption("$12:00")?.group == 12)
        #expect(NameToken.regexOption("$2x") == nil)
        #expect(NameToken(kind: .regex, value: #"(\d+)"#, option: "$2x").optionError != nil)
        #expect(NameToken(kind: .regex, value: #"(\d+)"#, option: "$2").optionError != nil)
        #expect(NameToken(kind: .regex, value: #"(\d+)"#, option: #"\1"#).optionError != nil)
        #expect(NameToken(kind: .regex, value: #"(\d+)"#, option: "$1:00").optionError == nil)
        #expect(NameToken(kind: .regex, value: #"(\d+)"#, option: "$1:0a").optionError != nil)
    }

    @Test func highlightsChosenGroup() {
        var settings = RenameSettings()
        settings.tokens[0] = NameToken(kind: .regex, value: #"IMG_(\d+)_(\d+)"#, option: "$2")
        #expect(settings.highlights(for: "IMG_5_7.jpg") == [NameHighlight(start: 6, length: 1, slot: 0)])
    }
}
