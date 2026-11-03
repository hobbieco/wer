//
//  EmptyFileSpec.swift
//  WER
//

import Foundation

/// Add Empty Files 설정. 설정 > Empty Files의 기본값이고, 창을 열 때마다 이 값으로 시작한다 (창에서 바꾼 값은 저장하지 않는다).
/// 입력칸은 글자 그대로 저장하고 빈 칸도 저장한다. 빈 칸은 만들 때 채운다: Name은 wer-create, Max는 Min(없으면 10), Count는 1.
/// 나중에 프리셋으로 넓힐 수 있게 한 덩어리로 저장한다
nonisolated struct EmptyFileSpec: Codable, Equatable, Sendable {
    /// 용량 단위. KB·MB·GB는 1000, KiB·MiB·GiB는 1024 기준
    enum Unit: String, Codable, CaseIterable, Sendable {
        case b = "B"
        case kb = "KB", mb = "MB", gb = "GB"
        case kib = "KiB", mib = "MiB", gib = "GiB"

        var multiplier: Int64 {
            switch self {
            case .b: 1
            case .kb: 1_000
            case .mb: 1_000_000
            case .gb: 1_000_000_000
            case .kib: 1 << 10
            case .mib: 1 << 20
            case .gib: 1 << 30
            }
        }

        static let decimal: [Unit] = [.kb, .mb, .gb]
        static let binary: [Unit] = [.kib, .mib, .gib]
    }

    /// 채우기. zeros는 sparse 파일(즉시, 실제로 쓰지 않음), random은 난수를 실제로 써서 압축·중복 제거가 안 된다
    enum Fill: String, Codable, CaseIterable, Sendable {
        case zeros
        case random

        var title: String {
            switch self {
            case .zeros: "Zeros (sparse)"
            case .random: "Random"
            }
        }
    }

    /// 입력칸. 창의 포커스에 쓴다
    enum Field: Hashable {
        case name, ext, min, max, count
    }

    var name = defaultName
    var ext = ""
    var min = ""
    var max = defaultMax
    var unit = Unit.mib
    var count = String(defaultCount)
    var fill = Fill.zeros
    var addsToOrder = false

    /// 빈 칸일 때 쓰는 값
    static let defaultName = "wer-create"
    static let defaultMax = "10"
    static let defaultCount = 1
    static let maxCount = 10_000
    /// 파일 하나의 최대 용량 (1 TiB)
    static let maxBytes: Int64 = 1 << 40

    init() {}

    /// 나중에 항목이 늘어도 예전에 저장한 값을 읽을 수 있게 없는 항목은 기본값으로 둔다
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = EmptyFileSpec()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? fallback.name
        ext = try container.decodeIfPresent(String.self, forKey: .ext) ?? fallback.ext
        min = try container.decodeIfPresent(String.self, forKey: .min) ?? fallback.min
        max = try container.decodeIfPresent(String.self, forKey: .max) ?? fallback.max
        unit = (try? container.decodeIfPresent(Unit.self, forKey: .unit)) ?? fallback.unit
        count = try container.decodeIfPresent(String.self, forKey: .count) ?? fallback.count
        fill = (try? container.decodeIfPresent(Fill.self, forKey: .fill)) ?? fallback.fill
        addsToOrder = try container.decodeIfPresent(Bool.self, forKey: .addsToOrder) ?? fallback.addsToOrder
    }

    // MARK: - 저장

    static let storageKey = "settings.emptyFileDefaults"

    /// 설정에 저장한 기본값. 비워 저장한 Name·Max·Count는 기본값을 실제 값으로 채워 보여준다
    static var saved: EmptyFileSpec {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var spec = try? JSONDecoder().decode(EmptyFileSpec.self, from: data) else { return EmptyFileSpec() }
        if trimmed(spec.name).isEmpty { spec.name = defaultName }
        // Min만 저장했으면 "모두 Min 용량"이라 Max를 채우지 않는다
        if trimmed(spec.max).isEmpty, trimmed(spec.min).isEmpty { spec.max = defaultMax }
        if trimmed(spec.count).isEmpty { spec.count = String(defaultCount) }
        return spec
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    // MARK: - 입력 해석

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    /// 용량 칸을 바이트로. 비었으면 nil, 잘못됐으면 오류
    private func bytes(_ text: String) -> Result<Int64, SpecError>? {
        let text = Self.trimmed(text)
        guard !text.isEmpty else { return nil }
        let isNumber = text.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") } && text.filter { $0 == "." }.count <= 1
            && text != "."
        guard isNumber, let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            return .failure(.init("Enter a number"))
        }
        if unit == .b, text.contains(".") { return .failure(.init("Bytes must be a whole number")) }
        // 소수는 내림한다
        var product = value * Decimal(unit.multiplier)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 0, .down)
        guard rounded <= Decimal(Self.maxBytes) else { return .failure(.init("Up to 1 TiB per file")) }
        return .success(NSDecimalNumber(decimal: rounded).int64Value)
    }

    struct SpecError: Error, Equatable {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// 파일 수. 비었으면 1, 잘못됐으면 nil
    var countValue: Int? {
        let text = Self.trimmed(count)
        guard !text.isEmpty else { return Self.defaultCount }
        guard text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), (1...Self.maxCount).contains(value)
        else { return nil }
        return value
    }

    /// Min을 쓰는지. 1개면 max만 쓴다 (Count가 잘못됐으면 켜 둔다)
    var usesMin: Bool { countValue != 1 }

    private var hasMin: Bool { usesMin && !Self.trimmed(min).isEmpty }

    /// Max 칸이 비어 기본값(10)을 쓰는지. Min이 있으면 Min을 쓴다
    var usesDefaultMax: Bool { Self.trimmed(max).isEmpty && !hasMin }

    var minBytes: Result<Int64, SpecError>? { usesMin ? bytes(min) : nil }
    var maxBytes: Result<Int64, SpecError>? {
        if usesDefaultMax { return bytes(Self.defaultMax) }
        return bytes(max)
    }

    /// 칸별 오류. 빈 칸은 오류로 표시하지 않는다 (Create만 막는다)
    func error(for field: Field) -> String? {
        switch field {
        case .name:
            let name = Self.trimmed(self.name)
            if NameToken.containsInvalidFileNameCharacter(name) { return NameToken.invalidCharacterMessage }
            return nil
        case .ext:
            let ext = Self.trimmed(self.ext)
            return ext.isEmpty ? nil : NameToken.extensionError(ext)
        case .min:
            if case .failure(let error) = minBytes { return error.message }
            return nil
        case .max:
            if case .failure(let error) = maxBytes { return error.message }
            if case .success(let low) = minBytes, case .success(let high) = maxBytes, low > high {
                return "Max is smaller than Min"
            }
            return nil
        case .count:
            guard countValue == nil else { return nil }
            return "Enter a whole number from 1 to \(Self.maxCount.formatted())"
        }
    }

    var errors: [(field: Field, message: String)] {
        [Field.name, .ext, .min, .max, .count].compactMap { field in error(for: field).map { (field, $0) } }
    }

    /// 파일별 용량. 양 끝(min, max)을 포함해 균등하게 나눈다. Min만 있으면 모두 Min 용량, 1개면 max
    var sizes: [Int64]? {
        guard errors.isEmpty, let count = countValue else { return nil }
        let low = try? minBytes?.get()
        let high = try? maxBytes?.get()
        switch (low, high) {
        case let (low?, high?):
            guard count > 1 else { return [high] }
            let span = high - low
            let steps = Int64(count - 1)
            // 반올림. span·steps 상한(1 TiB, 1만 개)이라 넘치지 않는다
            return (0..<Int64(count)).map { low + (span * $0 + steps / 2) / steps }
        case let (value?, nil), let (nil, value?):
            return Array(repeating: value, count: count)
        default:
            return nil
        }
    }

    /// 만들 파일 이름. <이름>-<용량 바이트(최대 용량 자릿수로 0 채움)>[-같은 용량 번호(가장 많이 겹친 수의 자릿수로 0 채움)].<확장자>
    var fileNames: [String]? {
        guard let sizes else { return nil }
        let base = Self.trimmed(name).isEmpty ? Self.defaultName : Self.trimmed(name)
        let ext = Self.trimmed(self.ext)
        let width = String(sizes.max() ?? 0).count
        var totals: [Int64: Int] = [:]
        for size in sizes { totals[size, default: 0] += 1 }
        let suffixWidth = String(totals.values.max() ?? 1).count
        var seen: [Int64: Int] = [:]
        return sizes.map { size in
            let digits = String(size)
            var name = base + "-" + String(repeating: "0", count: width - digits.count) + digits
            if totals[size, default: 0] > 1 {
                seen[size, default: 0] += 1
                let number = String(seen[size]!)
                name += "-" + String(repeating: "0", count: suffixWidth - number.count) + number
            }
            return ext.isEmpty ? name : name + "." + ext
        }
    }

    /// 파일 이름이 너무 긴지 (macOS는 255바이트까지)
    var nameTooLong: Bool {
        fileNames?.contains { $0.utf8.count > 255 } ?? false
    }

    /// 만들 수 있으면 계획
    func plan(in folder: URL) -> EmptyFilePlan? {
        guard !nameTooLong, let sizes, let names = fileNames else { return nil }
        let files = zip(names, sizes).map { EmptyFilePlan.File(url: folder.appending(path: $0), size: $1) }
        return EmptyFilePlan(folder: folder, files: files, fill: fill)
    }
}

/// 만들 파일 목록
nonisolated struct EmptyFilePlan: Sendable, Equatable {
    struct File: Sendable, Equatable {
        let url: URL
        let size: Int64
    }

    let folder: URL
    let files: [File]
    let fill: EmptyFileSpec.Fill

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
}
