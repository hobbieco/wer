//
//  AppSettings.swift
//  WER
//

import Foundation

/// 설정 화면(⌘,)의 값. UserDefaults에 저장한다. 이름 규칙은 모두 프리셋이 가진다
nonisolated enum AppSettings {
    /// 폴더 시작 위치. last는 마지막으로 고른 폴더(시작 폴더는 마지막 작업 폴더), current는 Select의 현재 폴더, custom은 지정 폴더
    enum FolderMode: String, CaseIterable {
        case last
        case current
        case custom
    }

    static let startupModeKey = "settings.startupFolderMode"
    static let startupPathKey = "settings.startupFolderPath"
    static let goToModeKey = "settings.goToFolderMode"
    static let goToPathKey = "settings.goToFolderPath"
    /// Go to Folder로 마지막에 이동한 폴더 (설정 값이 아니라 기록)
    static let lastGoToPathKey = "lastGoToFolderPath"
    /// Copy To에서 마지막으로 고른 폴더 (기록)
    static let lastCopyToPathKey = "lastCopyToFolderPath"
    static let defaultGoToMode = FolderMode.last
    static let defaultCopyToMode = FolderMode.current
    private static let folderModeMigratedKey = "settings.folderModeMigrated"

    /// 예전 Copy To의 last는 현재 작업 폴더였다. 지금은 current라서 한 번 바꿔 둔다
    static func migrateFolderModes() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: folderModeMigratedKey) else { return }
        if defaults.string(forKey: copyToModeKey) == FolderMode.last.rawValue {
            defaults.set(FolderMode.current.rawValue, forKey: copyToModeKey)
        }
        defaults.set(true, forKey: folderModeMigratedKey)
    }

    /// 설정에 따른 시작 폴더. 고른 폴더가 없거나 사라졌으면 current
    static func startFolder(modeKey: String, defaultMode: FolderMode, pathKey: String, lastKey: String, current: URL) -> URL {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: modeKey).flatMap(FolderMode.init(rawValue:)) ?? defaultMode
        let path: String? = switch mode {
        case .last: defaults.string(forKey: lastKey)
        case .current: nil
        case .custom: defaults.string(forKey: pathKey)
        }
        guard let path, isDirectory(path) else { return current }
        return URL(fileURLWithPath: path)
    }
    static let copyToModeKey = "settings.copyToFolderMode"
    static let copyToPathKey = "settings.copyToFolderPath"
    /// 창을 열 때 불러올 프리셋 id. 없거나 지워졌으면 Default
    static let startupPresetKey = "settings.startupPreset"
    static let copyFolderNameKey = "settings.copyFolderName"
    /// 복사본을 지우는 방식 (실패 시 되돌리기, Undo, 강제 종료 복구)
    static let removeCopiesToTrashKey = "settings.removeCopiesToTrash"

    /// 기본은 영구 삭제. 휴지통을 골라도 휴지통을 쓸 수 없는 볼륨에서는 영구 삭제한다
    static var removesCopiesToTrash: Bool {
        UserDefaults.standard.object(forKey: removeCopiesToTrashKey) as? Bool ?? false
    }
    /// Select·Order 목록의 글자 크기. Small이 예전 크기
    enum ListTextSize: String, CaseIterable {
        case small, medium, large

        var title: String { rawValue.capitalized }
        var pointSize: CGFloat {
            switch self {
            case .small: 13
            case .medium: 15
            case .large: 17
            }
        }
        /// 파일 아이콘 크기
        var iconSize: CGFloat { pointSize + 3 }
    }

    static let listTextSizeKey = "settings.listTextSize"
    /// Select·Order의 파일 이름(원래 이름, 새 이름)을 고정폭 글꼴로 보여줄지 (숫자 자리가 줄마다 맞는다). 기본은 켬.
    /// 키 이름은 처음(New Name만 적용하던 때)과 같게 유지한다
    static let monospacedNamesKey = "settings.monospacedNewNames"

    /// Select 목록에서 폴더를 파일보다 먼저 보여줄지. 기본은 폴더 먼저
    static let sortFoldersFirstKey = "settings.sortFoldersFirst"

    static var sortsFoldersFirst: Bool {
        UserDefaults.standard.object(forKey: sortFoldersFirstKey) as? Bool ?? true
    }

    /// 미리보기 켜기/끄기 (Preview 제목 줄의 버튼). 기본은 켬
    static let previewEnabledKey = "preview.enabled"

    static var isPreviewEnabled: Bool {
        UserDefaults.standard.object(forKey: previewEnabledKey) as? Bool ?? true
    }

    /// Rename 입력칸에 커서가 있을 때 Order 칸 위에 입력 안내를 띄울지. 끄면 입력칸 설명 툴팁도 숨긴다. 기본은 켬
    static let showsInputGuideKey = "settings.showsInputGuide"

    /// 앱을 시작할 때 Preview 칸을 미리보기로 열지, 파일 정보(Info)로 열지
    enum PreviewStartMode: String, CaseIterable {
        /// 마지막에 쓰던 상태 (눈 버튼)
        case last
        case preview
        case info

        var title: String {
            switch self {
            case .last: "Last Used"
            case .preview: "Preview"
            case .info: "Info"
            }
        }
    }

    static let previewStartModeKey = "settings.previewStartMode"

    /// Select 우클릭 > Open in kitty. 쓸 kitty(앱 또는 실행 파일, 비우면 설치된 kitty), 여는 방식, 원격 제어 소켓
    static let kittyPathKey = "settings.kittyPath"
    static let kittyOpenModeKey = "settings.kittyOpenMode"
    static let kittySocketKey = "settings.kittySocket"

    /// 앱을 시작할 때 한 번 미리보기 켜기/끄기를 정한다. 그 뒤 눈 버튼으로 바꾸는 것은 자유
    static func applyPreviewStartMode() {
        let mode = UserDefaults.standard.string(forKey: previewStartModeKey).flatMap(PreviewStartMode.init) ?? .last
        switch mode {
        case .last: break
        case .preview: UserDefaults.standard.set(true, forKey: previewEnabledKey)
        case .info: UserDefaults.standard.set(false, forKey: previewEnabledKey)
        }
    }
    static let builtInCopyFolderName = "wer-rename"
    /// 예전 설정 > General > Default Field Values (종류를 고를 때 채우던 값). 지금은 빈 칸으로 시작해서 쓰지 않고,
    /// 예전 프리셋의 빈 칸을 한 번 채울 때만 읽는다
    enum LegacyField {
        static let text = "settings.emptyText"
        static let number = "settings.emptyNumber"
        static let regex = "settings.emptyRegex"
        static let numberStep = "settings.fieldNumberStep"
        static let regexPad = "settings.fieldRegexPad"
        static let all = [text, number, regex, numberStep, regexPad]
    }

    /// 예전 Default Field Values. 비었거나 형식이 잘못된 항목은 예전 앱 기본값을 쓴다
    static var legacyFieldDefaults: RenameDefaults {
        let defaults = UserDefaults.standard
        var result = RenameDefaults(text: "wer-rename", number: "0001", numberStep: "1", regex: "\\d+", regexPad: "0000")
        if let text = defaults.string(forKey: LegacyField.text) ?? defaults.string(forKey: Legacy.textDefault),
           NameToken(kind: .text, value: text).validationError == nil {
            result.text = text
        }
        if var number = defaults.string(forKey: LegacyField.number) ?? defaults.string(forKey: Legacy.numberDefault) {
            // 예전 형식 "0001 step 1"이면 시작값과 증가 폭으로 나눈다
            if let legacy = NameToken.parseNumber(number), number.contains(where: \.isWhitespace) {
                result.numberStep = String(legacy.step)
                number = String(number.prefix { !$0.isWhitespace })
            }
            if NameToken(kind: .number, value: number).validationError == nil { result.number = number }
        }
        if let step = defaults.string(forKey: LegacyField.numberStep),
           NameToken(kind: .number, value: "1", option: step).optionError == nil {
            result.numberStep = step
        }
        if let regex = defaults.string(forKey: LegacyField.regex), NameToken(kind: .regex, value: regex).validationError == nil {
            result.regex = regex
        }
        if let pad = defaults.string(forKey: LegacyField.regexPad),
           NameToken(kind: .regex, value: ".", option: pad).optionError == nil {
            result.regexPad = pad
        }
        return result
    }

    /// 예전 설정 > Rename 탭의 값. 처음 실행할 때 옮기고 지운다 (구분자는 Default 프리셋, Text·Number 값은 예전 프리셋의 빈 칸)
    enum Legacy {
        static let textDefault = "settings.textDefault"
        static let numberDefault = "settings.numberDefault"
        static let regexPlaceholder = "settings.regexPlaceholder"
        static let separatorDefaults = "settings.separatorDefaults"
        static let separatorSameForAll = "settings.separatorSameForAll"
        static let separatorCommon = "settings.separatorCommon"
        static let omitLastSeparator = "settings.omitLastSeparator"
        static let all = [textDefault, numberDefault, regexPlaceholder, separatorDefaults,
                          separatorSameForAll, separatorCommon, omitLastSeparator]
    }

    /// 지정 폴더 모드이고 그 폴더가 있으면 그 폴더. 아니면 nil(호출한 쪽의 기본 위치를 쓴다)
    static func customFolder(modeKey: String, pathKey: String) -> URL? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: modeKey) == FolderMode.custom.rawValue,
              let path = defaults.string(forKey: pathKey), isDirectory(path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func isValidFolderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.contains("/")
    }

    /// Copy To를 지정하지 않았을 때 원본 폴더 안에 만들 폴더 이름. 비었거나 "/"가 있으면 기본값
    static var copyFolderName: String {
        let name = UserDefaults.standard.string(forKey: copyFolderNameKey) ?? ""
        return isValidFolderName(name) ? name.trimmingCharacters(in: .whitespaces) : builtInCopyFolderName
    }
}

/// Text·Number·Regex 값 묶음. 내장 Default 프리셋의 값과, 예전 버전 프리셋의 빈 칸을 채울 때 쓴다
nonisolated struct RenameDefaults: Equatable, Codable {
    var text: String
    /// Text 두 번째 칸 (첫 칸 뒤에 붙는다)
    var textSuffix = ""
    var number: String
    var numberStep = "1"
    var regex: String
    var regexPad = ""

    static let builtIn = RenameDefaults(
        text: "wer-", textSuffix: "rename", number: "0001", numberStep: "1", regex: "\\d+", regexPad: "0000")

    /// 첫 번째 칸 값
    func value(for kind: NameToken.Kind) -> String {
        switch kind {
        case .none, .changeExtension, .removeExtension, .addExtension, .createdDate, .modifiedDate, .takenDate, .replace: ""
        case .text: text
        case .number: number
        case .regex: regex
        }
    }

    /// 두 번째 칸 값 (Text 뒤 문자열, Number 증가 폭, Regex 채우기, 바꿀 확장자)
    func option(for kind: NameToken.Kind) -> String {
        switch kind {
        case .none, .changeExtension, .removeExtension, .addExtension, .createdDate, .modifiedDate, .takenDate, .replace: ""
        case .text: textSuffix
        case .number: numberStep
        case .regex: regexPad
        }
    }

    // 예전에 저장한 값에는 두 번째 칸이 없을 수 있다
    init(
        text: String, textSuffix: String = "", number: String, numberStep: String = "1", regex: String, regexPad: String = "") {
        self.text = text
        self.textSuffix = textSuffix
        self.number = number
        self.numberStep = numberStep
        self.regex = regex
        self.regexPad = regexPad
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        textSuffix = try container.decodeIfPresent(String.self, forKey: .textSuffix) ?? ""
        number = try container.decode(String.self, forKey: .number)
        numberStep = try container.decodeIfPresent(String.self, forKey: .numberStep) ?? "1"
        regex = try container.decode(String.self, forKey: .regex)
        regexPad = try container.decodeIfPresent(String.self, forKey: .regexPad) ?? ""
        // 예전 형식 "0001 step 2"
        if let legacy = NameToken.parseNumber(number), number.contains(where: \.isWhitespace) {
            number = String(number.prefix { !$0.isWhitespace })
            numberStep = String(legacy.step)
        }
    }
}
