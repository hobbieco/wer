//
//  RenameSettings.swift
//  WER
//

import Foundation

/// 새 이름을 이루는 조각 하나
nonisolated struct NameToken: Equatable, Identifiable, Codable {
    enum Kind: String, Hashable, CaseIterable, Codable {
        /// 사용 안 함. 구분자도 무시한다.
        case none
        /// 고정 문자열
        case text
        /// 연번. value는 시작값(음수 가능, "-"를 뺀 숫자 길이가 자릿수), option은 증가 폭(비우면 1, 음수면 감소)
        case number
        /// 원본 이름(확장자 제외)에서 정규식으로 추출. 캡처 그룹이 있으면 첫 그룹, 없으면 전체 일치.
        /// option은 채우기 모양: "0000"이면 왼쪽을 0으로 채워 4자리 (비우면 채우지 않음)
        case regex
        /// 확장자 바꾸기(Change Ext). value는 대상 확장자(대소문자 구분), option은 바꿀 확장자. 둘 다 필수.
        /// 이름 조각이 아니라 순서·구분자를 쓰지 않는다
        case changeExtension = "extension"
        /// 확장자 지우기(Remove Ext). value는 대상 확장자(대소문자 구분). option·구분자는 쓰지 않는다
        case removeExtension

        /// 확장자 규칙인지 (Change Ext·Remove Ext)
        var isExtensionRule: Bool { self == .changeExtension || self == .removeExtension }

        /// 새 이름 본문을 이루는 조각인지 (None·확장자 규칙 제외)
        var isNamePart: Bool { self != .none && !isExtensionRule }
    }

    var id = UUID()
    var kind: Kind = .none
    var value = ""
    /// 두 번째 칸. Number는 증가 폭, Regex는 채우기 모양, Text는 첫 칸 뒤에 붙일 문자열(비우면 무시)
    var option = ""
    var separator = "-"

    /// index번째(Order 순서, 0부터) 파일의 조각 값. 값이 없거나 형식이 잘못되면 nil
    func resolve(stem: String, index: Int) -> String? {
        guard validationError == nil, optionError == nil else { return nil }
        switch kind {
        case .none, .changeExtension, .removeExtension:
            return nil
        case .text:
            return value + option
        case .number:
            guard let start = Int(value) else { return nil }
            let number = start + index * step
            let digits = String(abs(number))
            // 자릿수는 시작값에서 "-"를 뺀 숫자 길이
            let width = value.filter(\.isNumber).count
            let padded = String(repeating: "0", count: max(width - digits.count, 0)) + digits
            return number < 0 ? "-" + padded : padded
        case .regex:
            return regexRange(in: stem).map { Self.pad(String(stem[$0]), with: option) }
        }
    }

    /// Number 증가 폭. 비우면 1
    /// 빈 칸 오류 문구. 형식 오류(빨강)와 달리 "아직 채우지 않음"(주황)으로 표시하고, 프리셋 저장은 막지 않는다
    static let emptyValueMessage = "Needs input"

    /// 첫 칸·두 번째 칸이 비어서 생긴 오류인지
    var needsValue: Bool { validationError == Self.emptyValueMessage }
    var needsOption: Bool { optionError == Self.emptyValueMessage }
    var needsInput: Bool { needsValue || needsOption }

    /// 실행은 되지만 확인이 필요한 상태(주황). Apply·저장을 막지 않는다.
    /// Change Ext의 대상과 바꿀 확장자가 같으면(완전 일치) 아무것도 바뀌지 않는다
    var warning: String? {
        guard kind == .changeExtension, validationError == nil, optionError == nil,
              RenameSettings.extensionKey(value) == RenameSettings.extensionKey(option) else { return nil }
        return "Same as the target extension. Nothing changes"
    }

    /// Text의 두 칸이 모두 빈 상태. 오류 표시를 커서가 있는 칸에 두는 데 쓴다
    var isEmptyText: Bool { kind == .text && value.isEmpty && option.isEmpty }

    var step: Int { option.isEmpty ? 1 : Int(option) ?? 1 }

    /// 채우기 모양 길이만큼 왼쪽을 그 문자로 채운다. 이미 길면 그대로
    static func pad(_ text: String, with template: String) -> String {
        guard let character = template.first, text.count < template.count else { return text }
        return String(repeating: character, count: template.count - text.count) + text
    }

    /// 정규식이 추출하는 범위. 캡처 그룹이 있으면 첫 그룹, 없으면 전체 일치. 일치하지 않거나 빈 범위면 nil.
    /// stem은 NFC로 맞춰 넘긴다 (RenameSettings.stem). 패턴도 NFC로 맞춰, 자모가 분리된 한글도 [가-힣]이나 한글 글자로 찾는다
    func regexRange(in stem: String) -> Range<String.Index>? {
        guard kind == .regex, !value.isEmpty,
              let regex = try? NSRegularExpression(pattern: value.precomposedStringWithCanonicalMapping),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)) else { return nil }
        let group = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound ? 1 : 0
        guard let range = Range(match.range(at: group), in: stem), !range.isEmpty else { return nil }
        return range
    }

    /// 값 오류. 빈 값은 오류(Text는 두 칸이 모두 비었을 때만). None이면 검사하지 않는다
    var validationError: String? {
        switch kind {
        case .none:
            return nil
        case .text:
            if value.isEmpty { return option.isEmpty ? Self.emptyValueMessage : nil }
            return Self.containsInvalidFileNameCharacter(value) ? Self.invalidCharacterMessage : nil
        case .changeExtension, .removeExtension:
            return value.isEmpty ? Self.emptyValueMessage : Self.extensionError(value)
        case _ where value.isEmpty:
            return Self.emptyValueMessage
        case .number:
            // 앞에 "-" 하나는 허용 (음수 시작)
            let digits = value.hasPrefix("-") ? value.dropFirst() : Substring(value)
            return !digits.isEmpty && digits.allSatisfy({ $0.isASCII && $0.isNumber })
                ? nil : "Start must be a whole number, e.g. 0001 or -01"
        case .regex:
            do {
                _ = try NSRegularExpression(pattern: value)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    /// 두 번째 칸 오류. Number는 0이 아닌 정수, Regex 채우기는 같은 문자의 반복, Text는 파일 이름에 쓸 수 있는 문자.
    /// Change Ext만 필수이고 나머지는 비워도 된다
    var optionError: String? {
        if kind == .changeExtension, option.isEmpty { return Self.emptyValueMessage }
        guard !option.isEmpty else { return nil }
        switch kind {
        case .none, .removeExtension:
            return nil
        case .text:
            return Self.containsInvalidFileNameCharacter(option) ? Self.invalidCharacterMessage : nil
        case .changeExtension:
            return Self.extensionError(option)
        case .number:
            guard let step = Int(option) else { return "Step must be a whole number, e.g. 1 or -1" }
            return step == 0 ? "Step can't be 0" : nil
        case .regex:
            if Self.containsInvalidFileNameCharacter(option) { return Self.invalidCharacterMessage }
            return Set(option).count == 1 ? nil : "Pad must repeat one character, e.g. 0000"
        }
    }

    /// 확장자 칸 오류. "."이나 파일 이름에 쓸 수 없는 문자가 있으면 오류
    static func extensionError(_ text: String) -> String? {
        if containsInvalidFileNameCharacter(text) { return invalidCharacterMessage }
        return text.contains(".") ? "Enter without dots, e.g. doc" : nil
    }

    /// 구분자 오류. 빈 값은 "구분자 없음"이라 허용. None·Extension이면 검사하지 않는다
    var separatorError: String? {
        guard kind.isNamePart, Self.containsInvalidFileNameCharacter(separator) else { return nil }
        return Self.invalidCharacterMessage
    }

    static let invalidCharacterMessage = "Contains a character not allowed in file names (/ : or control characters)"

    /// macOS 파일 이름에 쓸 수 없는 문자. "/"는 경로 구분자, ":"는 Finder에서 "/"로 보여 혼동된다
    static func containsInvalidFileNameCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0 == "/" || $0 == ":" || $0.properties.generalCategory == .control }
    }

    /// 예전 Number 형식 "001", "001 step 2", "001 2"를 (시작, 증가 폭, 자릿수)로 읽는다. 저장된 값을 옮길 때만 쓴다
    static func parseNumber(_ spec: String) -> (start: Int, step: Int, width: Int)? {
        var parts = spec.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 3 {
            guard parts[1].lowercased() == "step" else { return nil }
            parts.remove(at: 1)
        }
        guard (1...2).contains(parts.count),
              let startText = parts.first, startText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let start = Int(startText) else { return nil }
        var step = 1
        if parts.count == 2 {
            guard let parsed = Int(parts[1]), parsed != 0 else { return nil }
            step = parsed
        }
        return (start, step, startText.count)
    }
}

nonisolated extension NameToken {
    // 예전 Number 값("0001 step 2")은 시작값과 증가 폭으로 나눠 읽는다. option이 없던 예전 데이터도 읽는다
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        value = try container.decode(String.self, forKey: .value)
        option = try container.decodeIfPresent(String.self, forKey: .option) ?? ""
        separator = try container.decode(String.self, forKey: .separator)
        if kind == .number, value.contains(where: \.isWhitespace), let legacy = Self.parseNumber(value) {
            value = String(value.prefix { !$0.isWhitespace })
            option = String(legacy.step)
        }
    }
}

/// 원래 이름에서 정규식이 추출한 부분. 위치는 문자(Character) 단위, slot은 조각 번호
nonisolated struct NameHighlight: Hashable {
    let start: Int
    let length: Int
    let slot: Int
}

nonisolated struct RenameSettings: Equatable {
    static let tokenCount = 6

    var tokens: [NameToken] = (0..<tokenCount).map { _ in NameToken() }
    /// 끄면 모든 구분자를 무시한다. 입력값은 유지한다.
    var usesSeparator = true
    /// 마지막 조각 뒤의 구분자를 뺀다 (프리셋에서 정한다)
    var omitsLastSeparator = true

    /// 원본 대신 복사본에 새 이름을 붙인다
    var isCopy = false
    /// 복사 위치. nil이면 원본 폴더 안의 기본 복사 폴더(설정 > General, 기본 "wer-rename")
    var copyFolder: URL?

    /// 칸별 오류 (칸 번호, 내용). 하나라도 있으면 Apply할 수 없다
    var validationErrors: [(slot: Int, message: String)] {
        let conflicts = Self.extensionConflicts(in: tokens)
        return tokens.enumerated().flatMap { slot, token in
            [token.validationError, token.optionError, token.separatorError.map { "Separator: " + $0 },
             conflicts[slot].map(Self.conflictMessage)]
                .compactMap { $0 }
                .map { (slot, $0) }
        }
    }

    /// 확장자 비교 키. 대소문자까지 완전 일치로 비교하고, 자모가 분리된(NFD) 한글만 NFC로 맞춘다
    static func extensionKey(_ ext: String) -> String {
        ext.precomposedStringWithCanonicalMapping
    }

    /// 파일 이름들의 확장자별 개수 (extensionKey 기준). 확장자 규칙 줄의 일치 파일 수 표시에 쓴다
    static func extensionCounts(of names: [String]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for name in names {
            let ext = (name as NSString).pathExtension
            if !ext.isEmpty { counts[extensionKey(ext), default: 0] += 1 }
        }
        return counts
    }

    /// 대상 확장자가 다른 확장자 규칙과 겹치는 칸 → 겹치는 다른 칸(0부터, 첫 번째). 대소문자 구분, 종류 무관
    static func extensionConflicts(in tokens: [NameToken]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (slot, token) in tokens.enumerated() where token.kind.isExtensionRule && !token.value.isEmpty {
            if let other = tokens.indices.first(where: {
                $0 != slot && tokens[$0].kind.isExtensionRule
                    && extensionKey(tokens[$0].value) == extensionKey(token.value)
            }) {
                result[slot] = other
            }
        }
        return result
    }

    static func conflictMessage(_ otherSlot: Int) -> String {
        "Same extension as slot \(otherSlot + 1)"
    }

    var isValid: Bool { validationErrors.isEmpty }

    /// 빈 칸을 뺀 형식 오류. 이것이 없으면 빈 칸이 있어도 프리셋으로 저장할 수 있다
    var formatErrors: [(slot: Int, message: String)] {
        validationErrors.filter { $0.message != NameToken.emptyValueMessage }
    }

    /// 정규식 조각마다 원래 이름에서 추출한 위치
    func highlights(for name: String) -> [NameHighlight] {
        let stem = Self.stem(of: name)
        return tokens.enumerated().compactMap { slot, token in
            token.regexRange(in: stem).map { range in
                NameHighlight(
                    start: stem.distance(from: stem.startIndex, to: range.lowerBound),
                    length: stem.distance(from: range.lowerBound, to: range.upperBound),
                    slot: slot
                )
            }
        }
    }

    /// 값이 있는 조각을 구분자로 잇고 원래 확장자를 붙인다. 마지막 조각의 구분자는 omitsLastSeparator면 붙이지 않는다.
    /// 원래 이름은 쓰지 않는다. 값이 있는 조각이 하나도 없으면 nil
    /// 확장자를 뺀 이름. macOS에는 자모가 분리된(NFD) 한글 이름도 있어서 정규식에 넘기기 전에 NFC로 맞춘다.
    /// 글자(Character) 수는 그대로라 원래 이름 위의 강조 위치도 맞는다
    static func stem(of name: String) -> String {
        (name as NSString).deletingPathExtension.precomposedStringWithCanonicalMapping
    }

    /// 원래 확장자와 완전히 같은(대소문자 구분) 확장자 규칙을 적용한 확장자. Change Ext는 바꿀 확장자, Remove Ext는 빈 문자열.
    /// 맞는 규칙이 없으면 원래 확장자 (대상이 겹치면 Apply할 수 없어 규칙은 많아야 하나)
    func newExtension(for name: String) -> String {
        extensionChange(for: name).ext
    }

    /// 새 확장자와, 그것을 정한 확장자 규칙의 칸 번호(맞는 규칙이 없으면 nil)
    func extensionChange(for name: String) -> (ext: String, slot: Int?) {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, let slot = tokens.indices.first(where: {
            tokens[$0].kind.isExtensionRule && tokens[$0].validationError == nil && tokens[$0].optionError == nil
                && Self.extensionKey(tokens[$0].value) == Self.extensionKey(ext)
        }) else { return (ext, nil) }
        return (tokens[slot].kind == .removeExtension ? "" : tokens[slot].option, slot)
    }

    func newName(for name: String, index: Int) -> String? {
        buildNewName(for: name, index: index)?.name
    }

    /// 새 이름과, 새 이름 안에서 각 조각이 차지하는 위치(조각 색 강조용)
    func buildNewName(for name: String, index: Int) -> (name: String, highlights: [NameHighlight])? {
        let stem = Self.stem(of: name)
        let (ext, extensionSlot) = extensionChange(for: name)
        // Change Ext가 바꾼 확장자는 그 칸 색으로 칠한다 (Remove Ext는 지워져서 칠할 부분이 없다)
        func withExtension(_ base: String, _ highlights: [NameHighlight]) -> (name: String, highlights: [NameHighlight]) {
            guard !ext.isEmpty else { return (base, highlights) }
            var highlights = highlights
            if let extensionSlot {
                highlights.append(NameHighlight(start: base.count + 1, length: ext.count, slot: extensionSlot))
            }
            return (base + "." + ext, highlights)
        }
        let parts = tokens.enumerated().compactMap { slot, token in
            token.resolve(stem: stem, index: index).map { (value: $0, separator: token.separator, slot: slot) }
        }
        guard !parts.isEmpty else {
            // 확장자 조각만 있으면 원래 이름은 두고 확장자만 바꾼다
            guard tokens.contains(where: { $0.kind.isExtensionRule }) else { return nil }
            return withExtension((name as NSString).deletingPathExtension, [])
        }
        var base = ""
        var highlights: [NameHighlight] = []
        for (offset, part) in parts.enumerated() {
            highlights.append(NameHighlight(start: base.count, length: part.value.count, slot: part.slot))
            base += part.value
            if usesSeparator, offset < parts.count - 1 || !omitsLastSeparator { base += part.separator }
        }
        return withExtension(base, highlights)
    }
}
