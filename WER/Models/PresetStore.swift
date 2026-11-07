//
//  PresetStore.swift
//  WER
//

import Foundation
import Observation
import SwiftUI

/// 이름 규칙. 여섯 칸과 구분자 옵션을 담는다 (복사 설정은 제외)
nonisolated struct RenamePreset: Identifiable, Codable, Equatable {
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id = UUID()
    var name: String
    var tokens: [NameToken]
    var usesSeparator: Bool
    var omitsLastSeparator = true
    /// 채워야 하는 빈 칸 번호(0부터). 메뉴·목록에 ⚠로 표시한다
    var slotsNeedingInput: [Int] { tokens.indices.filter { tokens[$0].needsInput } }

    /// 빈 칸 안내 문구. 빈 칸이 없으면 nil
    var needsInputNote: String? {
        slotsNeedingInput.isEmpty ? nil : "Needs input in slot " + slotsNeedingInput.map { String($0 + 1) }.joined(separator: ", ")
    }

    /// 예전 버전에서 프리셋마다 가졌던 빈 칸 대체값. 읽기만 하고, 처음 실행할 때 빈 칸을 채운 뒤 버린다
    var legacyFallbacks: RenameDefaults?

    var isDefault: Bool { id == Self.defaultID }

    init(
        id: UUID = UUID(),
        name: String,
        tokens: [NameToken],
        usesSeparator: Bool,
        omitsLastSeparator: Bool = true
    ) {
        self.id = id
        self.name = name
        self.tokens = tokens
        self.usesSeparator = usesSeparator
        self.omitsLastSeparator = omitsLastSeparator
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tokens, usesSeparator, omitsLastSeparator
        case legacyFallbacks = "fallbacks"
    }

    // 나중에 생긴 항목은 예전에 저장한 프리셋에 없을 수 있어 기본값으로 읽는다
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // 칸 수가 다르게 저장된 프리셋(예전 5칸)은 지금 칸 수에 맞춘다
        tokens = Self.fitted(try container.decode([NameToken].self, forKey: .tokens))
        usesSeparator = try container.decode(Bool.self, forKey: .usesSeparator)
        omitsLastSeparator = try container.decodeIfPresent(Bool.self, forKey: .omitsLastSeparator) ?? true
        legacyFallbacks = try container.decodeIfPresent(RenameDefaults.self, forKey: .legacyFallbacks)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(usesSeparator, forKey: .usesSeparator)
        try container.encode(omitsLastSeparator, forKey: .omitsLastSeparator)
    }

    /// 예시를 겸한 기본 규칙(시작 프리셋): [Text] [Regex] [Number] → wer-rename-1234-0001.jpg.
    /// 확장자 규칙은 이름만 바꾸려는 파일의 확장자까지 바꾸지 않도록 Fix Extensions에 따로 둔다
    static var builtInDefault: RenamePreset {
        let values = RenameDefaults.builtIn
        let tokens = [
            NameToken(kind: .text, value: values.text, option: values.textSuffix),
            NameToken(kind: .regex, value: values.regex, option: values.regexPad),
            NameToken(kind: .number, value: values.number, option: values.numberStep),
        ]
        return RenamePreset(id: defaultID, name: "Default", tokens: fitted(tokens), usesSeparator: true)
    }

    static let fixExtensionsName = "Fix Extensions"

    /// 확장자 규칙 예시 프리셋: [Change Ext] jpeg → jpg, [Remove Ext] bak, [Add Ext] jpg. 이름은 그대로 두고 확장자만 바꾼다.
    /// 일반 프리셋이라 이름을 바꾸거나 지울 수 있다
    static var builtInFixExtensions: RenamePreset {
        let tokens = [
            NameToken(kind: .changeExtension, value: "jpeg", option: "jpg"),
            NameToken(kind: .removeExtension, value: "bak"),
            NameToken(kind: .addExtension, value: "jpg"),
        ]
        return RenamePreset(name: fixExtensionsName, tokens: fitted(tokens), usesSeparator: true)
    }

    /// 목록에 보여줄 요약. 예: "Text trip · Number 001 · Regex (\d+)"
    var summary: String {
        let parts = tokens.filter { $0.kind != .none }.map { token in
            let kind = switch token.kind {
            case .none: ""
            case .text: "Text"
            case .number: "Number"
            case .regex: "Regex"
            case .replace: "Replace"
            case .changeExtension: "Change Ext"
            case .removeExtension: "Remove Ext"
            case .addExtension: "Add Ext"
            case .createdDate: "Created"
            case .modifiedDate: "Modified"
            case .takenDate: "Taken"
            }
            let option = switch token.kind {
            case .number where !token.option.isEmpty: " step \(token.option)"
            case .regex where token.option.hasPrefix("$"): " \(token.option)"
            case .regex where !token.option.isEmpty: " pad \(token.option)"
            case .replace: " → " + token.option
            case .text: token.option
            case .changeExtension: " → " + token.option
            // where는 마지막 패턴에만 걸려서 날짜 종류는 조건으로 묶는다
            case _ where token.kind.isDate && !token.option.isEmpty: " or \(token.option)"
            default: ""
            }
            return token.value.isEmpty ? kind : "\(kind) \(token.value)\(option)"
        }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " · ")
    }

    /// 칸 수를 RenameSettings.tokenCount에 맞춘다. 모자라면 None 칸을 붙이고 넘치면 자른다
    static func fitted(_ tokens: [NameToken]) -> [NameToken] {
        var filled = Array(tokens.prefix(RenameSettings.tokenCount))
        filled += (filled.count..<RenameSettings.tokenCount).map { _ in NameToken() }
        return filled
    }

    /// 이 프리셋을 Rename 칸 설정에 넣는다. 복사 설정은 건드리지 않는다
    func apply(to settings: inout RenameSettings) {
        settings.tokens = Self.fitted(tokens)
        settings.usesSeparator = usesSeparator
        settings.omitsLastSeparator = omitsLastSeparator
    }

    /// Rename 칸 설정이 이 프리셋과 같은 규칙인지 (고친 상태 표시용)
    func matches(_ settings: RenameSettings) -> Bool {
        var copy = settings
        apply(to: &copy)
        return copy == settings
    }

    /// Rename 칸 설정의 규칙으로 내용을 바꾼다
    mutating func update(from settings: RenameSettings) {
        tokens = settings.tokens
        usesSeparator = settings.usesSeparator
        omitsLastSeparator = settings.omitsLastSeparator
    }
}

/// 프리셋 목록. 모든 창과 설정 창이 함께 쓰고 UserDefaults에 저장한다.
/// Default 프리셋은 항상 맨 앞에 있고 지우거나 이름을 바꿀 수 없다
@Observable
final class PresetStore {
    static let shared = PresetStore()

    private static let key = "settings.renamePresets"

    private(set) var presets: [RenamePreset] = []

    /// 설정 > Presets의 예시 파일 이름 (프리셋 id별 sampleCount개). 이름 규칙이 아니라 프리셋과 따로 저장한다
    private(set) var samples: [RenamePreset.ID: [String]] = [:]
    private static let samplesKey = "settings.presetSamples"
    static let sampleCount = 3

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([RenamePreset].self, from: data) {
            presets = saved
        }
        if let data = UserDefaults.standard.data(forKey: Self.samplesKey),
           let saved = try? JSONDecoder().decode([RenamePreset.ID: [String]].self, from: data) {
            samples = saved
        }
        ensureDefault()
        updateBuiltInSamples()
    }

    /// 프리셋의 예시 이름 sampleCount개. 저장한 적이 없으면 기본 예시
    func samples(for id: RenamePreset.ID) -> [String] {
        let saved = samples[id] ?? defaultSamples(for: id)
        return Array((saved + Array(repeating: "", count: Self.sampleCount)).prefix(Self.sampleCount))
    }

    func setSample(_ name: String, at row: Int, for id: RenamePreset.ID) {
        var current = samples(for: id)
        guard current.indices.contains(row) else { return }
        current[row] = name
        samples[id] = current
        persistSamples()
    }

    /// 기본 예시. 저장한 예시가 없을 때 쓴다.
    /// Fix Extensions: 바꾸기·지우기·해당 없음. 나머지(Default와 새 프리셋): 연번과 정규식 불일치
    private func defaultSamples(for id: RenamePreset.ID) -> [String] {
        if id != RenamePreset.defaultID, preset(id)?.name == RenamePreset.fixExtensionsName {
            return ["IMG_1234.jpeg", "IMG_0007.jpeg.bak", "IMG_sample"]
        }
        return ["IMG_1234.jpg", "IMG_0007.jpg", "IMG_sample.jpg"]
    }

    /// 한 줄이라도 고치면 그때의 기본 예시가 함께 저장된다. 예전 기본 예시 그대로면 지금 기본 예시로 바꾼다
    private func updateBuiltInSamples() {
        let outdated: [[String]] = [
            ["IMG_1234.jpeg", "IMG_0007.jpeg", ""],
            ["IMG_1234.jpeg", "", ""],
            ["IMG_1234.jpg", "", ""],
            ["IMG_1234.jpeg", "report.docx.bak", "notes.txt"],
            ["IMG_1234.jpeg", "IMG_0007.jpeg.bak", "IMG_sample.jpg"],
        ]
        var changed = false
        for (id, saved) in samples where outdated.contains(saved) {
            samples[id] = nil
            changed = true
        }
        if changed { persistSamples() }
    }

    private func persistSamples() {
        // 지워진 프리셋의 예시는 버린다
        let ids = Set(presets.map(\.id))
        samples = samples.filter { ids.contains($0.key) }
        if let data = try? JSONEncoder().encode(samples) {
            UserDefaults.standard.set(data, forKey: Self.samplesKey)
        }
    }

    var defaultPreset: RenamePreset {
        presets.first(where: \.isDefault) ?? .builtInDefault
    }

    func preset(_ id: RenamePreset.ID?) -> RenamePreset? {
        presets.first { $0.id == id }
    }

    /// 창을 열 때 불러올 프리셋 (설정 > General). 지워졌으면 Default
    var startupPreset: RenamePreset {
        let id = UserDefaults.standard.string(forKey: AppSettings.startupPresetKey).flatMap(UUID.init(uuidString:))
        return preset(id) ?? defaultPreset
    }

    /// Rename 칸 설정을 새 프리셋으로 저장한다. 같은 이름이 있으면 그 프리셋을 덮어쓴다
    @discardableResult
    func save(name: String, from settings: RenameSettings) -> RenamePreset.ID? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let index = presets.firstIndex(where: { $0.name == trimmed }) {
            presets[index].update(from: settings)
            persist()
            return presets[index].id
        }
        var preset = RenamePreset(name: trimmed, tokens: [], usesSeparator: true)
        preset.update(from: settings)
        presets.append(preset)
        persist()
        return preset.id
    }

    /// 여섯 칸이 모두 None인 새 프리셋. 구분자와 구분자 옵션은 Default에서 가져온다
    @discardableResult
    func add() -> RenamePreset.ID {
        let base = defaultPreset
        let preset = RenamePreset(
            name: uniqueName("New Preset"),
            tokens: base.tokens.map { NameToken(separator: $0.separator) },
            usesSeparator: true,
            omitsLastSeparator: base.omitsLastSeparator
        )
        presets.append(preset)
        persist()
        return preset.id
    }

    /// 바로 아래에 복사본을 만든다
    @discardableResult
    func duplicate(_ id: RenamePreset.ID) -> RenamePreset.ID? {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = presets[index]
        copy.id = UUID()
        copy.name = uniqueName(copy.name + " Copy")
        presets.insert(copy, at: index + 1)
        persist()
        samples[copy.id] = samples(for: id)
        persistSamples()
        return copy.id
    }

    /// 프리셋 내용 갱신. 편집하는 즉시 저장한다. Default의 이름은 바꾸지 않는다
    func update(_ preset: RenamePreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var updated = preset
        if updated.isDefault { updated.name = presets[index].name }
        presets[index] = updated
        persist()
    }

    func rename(_ id: RenamePreset.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, id != RenamePreset.defaultID,
              let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = trimmed
        persist()
    }

    /// Default는 지우지 않는다
    func delete(_ ids: Set<RenamePreset.ID>) {
        presets.removeAll { ids.contains($0.id) && !$0.isDefault }
        persist()
        persistSamples()
    }

    /// Default는 맨 앞에 고정한다
    func move(from source: IndexSet, to destination: Int) {
        guard !source.contains(0) else { return }
        presets.move(fromOffsets: source, toOffset: max(destination, 1))
        persist()
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(presets.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Default가 없으면 만들고 맨 앞에 둔다. 예전 버전의 값을 옮긴다
    private func ensureDefault() {
        if let index = presets.firstIndex(where: \.isDefault) {
            if index != 0 { presets.insert(presets.remove(at: index), at: 0) }
        } else {
            presets.insert(Self.migratedDefault(), at: 0)
        }
        migrateLegacyFallbacks()
        updateBuiltInDefault()
        addFixExtensionsOnce()
        updateBuiltInFixExtensions()
        AppSettings.Legacy.all.forEach(UserDefaults.standard.removeObject(forKey:))
        persist()
    }

    /// 예전 내장 Default 프리셋을 지금 내장값에 맞춘다. 결과 이름은 같다.
    /// Text "wer-rename"(두 번째 칸 없음)은 "wer-" + "rename"으로 나눈다
    private func updateBuiltInDefault() {
        guard let index = presets.firstIndex(where: \.isDefault) else { return }
        let builtIn = RenameDefaults.builtIn
        for slot in presets[index].tokens.indices {
            let token = presets[index].tokens[slot]
            if token.kind == .text, token.value == builtIn.text + builtIn.textSuffix, token.option.isEmpty {
                presets[index].tokens[slot].value = builtIn.text
                presets[index].tokens[slot].option = builtIn.textSuffix
            }
        }
        // 잠시 Default에 넣었던 확장자 예시는 Fix Extensions로 옮겼으므로 None으로 되돌린다
        for slot in presets[index].tokens.indices {
            let token = presets[index].tokens[slot]
            let isExample = (token.kind == .changeExtension && [("jpeg", "jpg"), ("html", "md")].contains { $0 == (token.value, token.option) })
                || (token.kind == .removeExtension && ["bak", "swp"].contains(token.value))
            if isExample {
                presets[index].tokens[slot] = NameToken(separator: token.separator)
            }
        }
    }

    /// 이미 만든 Fix Extensions가 고치지 않은 예전 내용(Change Ext·Remove Ext뿐)이면 Add Ext 예시를 넣는다
    private func updateBuiltInFixExtensions() {
        guard let index = presets.firstIndex(where: { $0.name == RenamePreset.fixExtensionsName && !$0.isDefault }) else { return }
        let tokens = presets[index].tokens
        let old = [NameToken.Kind.changeExtension, .removeExtension] + Array(repeating: .none, count: max(tokens.count - 2, 0))
        guard tokens.map(\.kind) == old, tokens[0].value == "jpeg", tokens[0].option == "jpg", tokens[1].value == "bak",
              tokens.count > 2 else { return }
        presets[index].tokens[2] = NameToken(kind: .addExtension, value: "jpg", separator: tokens[2].separator)
    }

    /// Fix Extensions 예시 프리셋을 만들었는지. 사용자가 지우면 다시 만들지 않는다
    private static let fixExtensionsAddedKey = "presets.fixExtensionsAdded"

    /// Fix Extensions를 처음 한 번만 Default 바로 뒤에 넣는다. 같은 이름의 프리셋이 있으면 넣지 않는다
    private func addFixExtensionsOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.fixExtensionsAddedKey) else { return }
        if !presets.contains(where: { $0.name == RenamePreset.fixExtensionsName }) {
            presets.insert(RenamePreset.builtInFixExtensions, at: min(1, presets.count))
        }
        defaults.set(true, forKey: Self.fixExtensionsAddedKey)
    }

    /// 예전 버전 프리셋의 빈 칸 채우기를 마쳤는지. 지금은 빈 칸을 "나중에 채울 칸"으로 저장할 수 있어서 한 번만 한다
    private static let legacyFallbacksMigratedKey = "presets.legacyFallbacksMigrated"

    /// 예전 버전은 비워 둔 칸에 대체값을 썼다. 결과가 바뀌지 않도록 그 칸이 쓰던 값을 한 번 직접 채운다.
    /// 프리셋별 대체값이 있으면 그 값, 없으면 Default의 대체값, 그것도 없으면 예전 Default Field Values를 쓴다
    private func migrateLegacyFallbacks() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.legacyFallbacksMigratedKey) {
            let global = presets.first(where: \.isDefault)?.legacyFallbacks ?? AppSettings.legacyFieldDefaults
            for index in presets.indices {
                let values = presets[index].legacyFallbacks ?? global
                for slot in presets[index].tokens.indices
                where presets[index].tokens[slot].kind.isNamePart && presets[index].tokens[slot].value.isEmpty {
                    presets[index].tokens[slot].value = values.value(for: presets[index].tokens[slot].kind)
                    if presets[index].tokens[slot].option.isEmpty {
                        presets[index].tokens[slot].option = values.option(for: presets[index].tokens[slot].kind)
                    }
                }
            }
            defaults.set(true, forKey: Self.legacyFallbacksMigratedKey)
            AppSettings.LegacyField.all.forEach(defaults.removeObject(forKey:))
        }
        for index in presets.indices { presets[index].legacyFallbacks = nil }
    }

    private static func migratedDefault() -> RenamePreset {
        var preset = RenamePreset.builtInDefault
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: AppSettings.Legacy.separatorSameForAll),
           let common = defaults.string(forKey: AppSettings.Legacy.separatorCommon) {
            for index in preset.tokens.indices { preset.tokens[index].separator = common }
        } else if let separators = defaults.stringArray(forKey: AppSettings.Legacy.separatorDefaults) {
            for (index, separator) in separators.prefix(preset.tokens.count).enumerated() {
                preset.tokens[index].separator = separator
            }
        }
        if let omits = defaults.object(forKey: AppSettings.Legacy.omitLastSeparator) as? Bool {
            preset.omitsLastSeparator = omits
        }
        return preset
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
