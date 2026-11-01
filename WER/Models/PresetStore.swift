//
//  PresetStore.swift
//  WER
//

import Foundation
import Observation
import SwiftUI

/// 이름 규칙. 다섯 칸과 구분자 옵션을 담는다 (복사 설정과 빈 칸 값은 제외. 빈 칸 값은 전역 설정)
nonisolated struct RenamePreset: Identifiable, Codable, Equatable {
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    var id = UUID()
    var name: String
    var tokens: [NameToken]
    var usesSeparator: Bool
    var omitsLastSeparator = true
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
        tokens = try container.decode([NameToken].self, forKey: .tokens)
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

    /// 예시를 겸한 기본 규칙: [Text] [Regex] [Number] → wer-rename-1234-0001.jpg
    static var builtInDefault: RenamePreset {
        let values = RenameDefaults.builtIn
        var tokens = [
            NameToken(kind: .text, value: values.text),
            NameToken(kind: .regex, value: values.regex, option: values.regexPad),
            NameToken(kind: .number, value: values.number, option: values.numberStep),
        ]
        tokens += (tokens.count..<RenameSettings.tokenCount).map { _ in NameToken() }
        return RenamePreset(id: defaultID, name: "Default", tokens: tokens, usesSeparator: true)
    }

    /// 목록에 보여줄 요약. 예: "Text trip · Number 001 · Regex (\d+)"
    var summary: String {
        let parts = tokens.filter { $0.kind != .none }.map { token in
            let kind = switch token.kind {
            case .none: ""
            case .text: "Text"
            case .number: "Number"
            case .regex: "Regex"
            }
            let option = switch token.kind {
            case .number where !token.option.isEmpty: " step \(token.option)"
            case .regex where !token.option.isEmpty: " pad \(token.option)"
            default: ""
            }
            return token.value.isEmpty ? kind : "\(kind) \(token.value)\(option)"
        }
        return parts.isEmpty ? "Empty" : parts.joined(separator: " · ")
    }

    /// 이 프리셋을 Rename 칸 설정에 넣는다. 복사 설정은 건드리지 않는다
    func apply(to settings: inout RenameSettings) {
        var filled = Array(tokens.prefix(RenameSettings.tokenCount))
        filled += (filled.count..<RenameSettings.tokenCount).map { _ in NameToken() }
        settings.tokens = filled
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

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([RenamePreset].self, from: data) {
            presets = saved
        }
        ensureDefault()
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

    /// 다섯 칸이 모두 None인 새 프리셋. 구분자와 구분자 옵션은 Default에서 가져온다
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
        AppSettings.Legacy.all.forEach(UserDefaults.standard.removeObject(forKey:))
        persist()
    }

    /// 예전 버전은 비워 둔 칸에 대체값을 썼다. 이제 빈 칸은 오류라서, 그 칸이 쓰던 값을 직접 채워 결과가 바뀌지 않게 한다.
    /// 프리셋별 대체값이 있으면 그 값, 없으면 전역 값을 쓴다. Default의 프리셋별 값은 전역 값으로도 옮긴다
    private func migrateLegacyFallbacks() {
        if let defaultLegacy = presets.first(where: \.isDefault)?.legacyFallbacks,
           UserDefaults.standard.string(forKey: AppSettings.fieldTextKey) == nil {
            AppSettings.setFieldDefaults(defaultLegacy)
        }
        let global = AppSettings.fieldDefaults
        for index in presets.indices {
            let values = presets[index].legacyFallbacks ?? global
            for slot in presets[index].tokens.indices
            where presets[index].tokens[slot].kind != .none && presets[index].tokens[slot].value.isEmpty {
                presets[index].tokens[slot].value = values.value(for: presets[index].tokens[slot].kind)
                if presets[index].tokens[slot].option.isEmpty {
                    presets[index].tokens[slot].option = values.option(for: presets[index].tokens[slot].kind)
                }
            }
            presets[index].legacyFallbacks = nil
        }
    }

    private static func migratedDefault() -> RenamePreset {
        var preset = RenamePreset.builtInDefault
        let defaults = UserDefaults.standard
        // 예전 설정의 Text·Number 기본값은 Default Field Values로 옮긴다
        var fallbacks = AppSettings.fieldDefaults
        if let text = defaults.string(forKey: AppSettings.Legacy.textDefault), !text.isEmpty {
            fallbacks.text = text
        }
        if let number = defaults.string(forKey: AppSettings.Legacy.numberDefault), let legacy = NameToken.parseNumber(number) {
            fallbacks.number = String(number.prefix { !$0.isWhitespace })
            fallbacks.numberStep = String(legacy.step)
        }
        if fallbacks != AppSettings.fieldDefaults {
            AppSettings.setFieldDefaults(fallbacks)
        }
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
