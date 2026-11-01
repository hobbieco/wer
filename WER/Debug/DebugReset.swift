//
//  DebugReset.swift
//  WER
//

#if DEBUG
import Foundation

/// 개발용 초기화. 실행 인자 `-resetAll YES`를 주면 앱이 시작할 때 저장된 상태를 모두 지운다.
/// Xcode: Product > Scheme > Edit Scheme… > Run > Arguments > Arguments Passed On Launch
enum DebugReset {
    static let argumentKey = "resetAll"

    /// 앱 init에서 호출한다. 프리셋 저장소 등이 값을 읽기 전에 지워야 한다
    static func performIfRequested() {
        // 실행 인자는 UserDefaults의 argument 도메인으로 들어온다 (저장되지 않음)
        guard UserDefaults.standard.bool(forKey: argumentKey),
              let bundleID = Bundle.main.bundleIdentifier else { return }

        // 설정, 프리셋, 마지막 폴더, 정렬 방식
        UserDefaults.standard.removePersistentDomain(forName: bundleID)

        let library = URL.libraryDirectory
        // 창 상태 (Select 접힘, 칸 너비, 설정 창 탭)
        try? FileManager.default.removeItem(at: library.appending(path: "Saved Application State/\(bundleID).savedState"))
        // 강제 종료 대비 작업 기록
        try? FileManager.default.removeItem(at: RenameJournal.fileURL.deletingLastPathComponent())

        print("[DebugReset] Cleared saved settings, presets, window state and rename journal for \(bundleID)")
    }
}
#endif
