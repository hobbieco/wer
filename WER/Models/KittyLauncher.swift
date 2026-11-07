//
//  KittyLauncher.swift
//  WER
//

import AppKit

/// Select 우클릭 메뉴의 Open in kitty. 폴더에서 kitty 탭(기본) 또는 새 창을 연다.
/// 탭·창은 kitty 원격 제어(`kitty @ launch`)로만 확실히 지정할 수 있어 kitty.conf에 아래 두 줄이 필요하다:
///   allow_remote_control socket-only
///   listen_on unix:/tmp/kitty
/// 원격 제어에 닿지 못하면 새 창으로 대신 연다
nonisolated enum KittyLauncher {
    static let bundleID = "net.kovidgoyal.kitty"
    static let defaultSocket = "unix:/tmp/kitty"

    enum OpenMode: String, CaseIterable {
        case tab, window

        var title: String {
            switch self {
            case .tab: "Tab"
            case .window: "Window"
            }
        }
    }

    enum Outcome: Equatable {
        case openedTab
        case openedWindow
        /// kitty가 꺼져 있어 새로 실행했다
        case started
        /// 원격 제어에 닿지 못해 새 kitty 창으로 대신 열었다
        case fellBack(socket: String)
        case failed(String)

        var message: String {
            switch self {
            case .openedTab: "Opened a tab in kitty"
            case .openedWindow: "Opened a window in kitty"
            case .started: "kitty wasn't running. Started it in a new window"
            case .fellBack(let socket): "Couldn't reach kitty at \(socket). Opened a new window instead. Check kitty.conf"
            case .failed(let reason): reason
            }
        }

        var isProblem: Bool {
            switch self {
            case .fellBack, .failed: true
            default: false
            }
        }
    }

    // MARK: 설정

    /// 설정에서 고른 kitty (kitty.app 또는 실행 파일). 비우면 설치된 kitty를 찾는다
    static var customPath: String {
        UserDefaults.standard.string(forKey: AppSettings.kittyPathKey) ?? ""
    }

    static var openMode: OpenMode {
        UserDefaults.standard.string(forKey: AppSettings.kittyOpenModeKey).flatMap(OpenMode.init) ?? .tab
    }

    static var socket: String {
        let value = UserDefaults.standard.string(forKey: AppSettings.kittySocketKey)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? defaultSocket : value
    }

    /// 쓸 kitty (앱 또는 실행 파일). 없으면 nil이고, 우클릭 메뉴에서 항목을 뺀다
    static var location: URL? {
        if !customPath.isEmpty {
            let url = URL(filePath: (customPath as NSString).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// 실행 파일. kitty.app이면 그 안의 Contents/MacOS/kitty
    static func executable(at location: URL) -> URL {
        location.pathExtension == "app" ? location.appending(path: "Contents/MacOS/kitty") : location
    }

    // MARK: 열기

    /// directory에서 설정대로 연다. 원격 제어 → (꺼져 있으면) 새로 실행 → (닿지 못하면) 새 창 순서
    static func open(directory: URL) async -> Outcome {
        guard let location else { return .failed("kitty not found. Choose it in Settings > kitty") }
        let kitty = executable(at: location)
        let mode = openMode
        if isRunning(location) {
            if let address = await resolvedSocket(),
               await run(kitty, ["@", "--to", address, "launch", "--type=\(mode == .tab ? "tab" : "os-window")",
                                 "--cwd=\(directory.path)"]) {
                return mode == .tab ? .openedTab : .openedWindow
            }
            return await launch(location, directory: directory, newInstance: true)
                ? .fellBack(socket: socket) : .failed("Couldn't open kitty")
        }
        return await launch(location, directory: directory, newInstance: false)
            ? .started : .failed("Couldn't start kitty")
    }

    private static func isRunning(_ location: URL) -> Bool {
        let executablePath = executable(at: location).resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == bundleID || app.executableURL?.resolvingSymlinksInPath().path == executablePath
        }
    }

    /// 원격 제어 주소. kitty는 listen_on 경로 뒤에 프로세스 번호를 붙이기도 해서 (/tmp/kitty-12345)
    /// 그대로 없으면 같은 이름으로 시작하는 소켓 중 가장 최근 것을 쓴다. unix 소켓이 아니면(tcp 등) 그대로 쓴다
    private static func resolvedSocket() async -> String? {
        let address = socket
        guard address.hasPrefix("unix:") else { return address }
        let path = String(address.dropFirst("unix:".count))
        // 앞에 @가 붙은 추상 소켓은 파일이 없다
        if path.hasPrefix("@") || FileManager.default.fileExists(atPath: path) { return address }
        let folder = (path as NSString).deletingLastPathComponent
        let prefix = (path as NSString).lastPathComponent + "-"
        let candidates = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .filter { $0.hasPrefix(prefix) }
            .map { (folder as NSString).appendingPathComponent($0) }
        let newest = candidates.max {
            let a = (try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date) ?? .distantPast
            let b = (try? FileManager.default.attributesOfItem(atPath: $1)[.modificationDate] as? Date) ?? .distantPast
            return a < b
        }
        return newest.map { "unix:" + $0 }
    }

    /// 명령을 실행하고 성공했는지. 원격 제어 명령은 금방 끝나서 3초가 지나면 실패로 본다
    private static func run(_ executable: URL, _ arguments: [String]) async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return false }
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning, Date() < deadline { usleep(50_000) }
            if process.isRunning {
                process.terminate()
                return false
            }
            return process.terminationStatus == 0
        }.value
    }

    /// kitty를 directory에서 새로 실행한다. WER을 닫아도 kitty가 같이 꺼지지 않게 앱으로 띄운다.
    /// 실행 파일만 지정했으면 그 파일을 바로 실행한다
    private static func launch(_ location: URL, directory: URL, newInstance: Bool) async -> Bool {
        let arguments = ["--directory", directory.path]
        guard location.pathExtension == "app" else {
            let process = Process()
            process.executableURL = location
            process.arguments = arguments
            return (try? process.run()) != nil
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = newInstance
        return (try? await NSWorkspace.shared.openApplication(at: location, configuration: configuration)) != nil
    }
}
