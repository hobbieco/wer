//
//  RenameExecutor.swift
//  WER
//

import Foundation

/// 실행할 이름 변경 목록
nonisolated struct RenamePlan: Sendable {
    enum Mode: Sendable, Equatable {
        /// 원본 이름 변경
        case rename
        /// destination 폴더에 새 이름으로 복사
        case copy(destination: URL)
    }

    struct Item: Sendable, Identifiable, Equatable {
        let id = UUID()
        let source: URL
        let destination: URL
    }

    let mode: Mode
    let items: [Item]

    var isCopy: Bool { if case .copy = mode { true } else { false } }
}

/// Preview에 보여줄 처리 로그 한 줄
nonisolated struct RenameLogEntry: Identifiable, Sendable {
    enum Kind: Sendable {
        case info
        case success
        case failure
        case revert
        case warning
    }

    let id = UUID()
    let kind: Kind
    let message: String
    var detail: String?

    static func item(_ kind: Kind, _ item: RenamePlan.Item, _ message: String) -> RenameLogEntry {
        RenameLogEntry(kind: kind, message: "\(item.source.lastPathComponent) → \(item.destination.lastPathComponent)", detail: message)
    }
}

/// 실행 결과
nonisolated struct RenameOutcome: Sendable {
    /// 모두 성공했는지. false면 끝난 작업은 모두 되돌린 상태다
    var succeeded: Bool
    /// 사전 검사에서 막혀 아무것도 하지 않았는지
    var notStarted = false
    /// 실패 원인 (파일별)
    var failures: [(item: RenamePlan.Item, reason: String)] = []
    /// 되돌리지 못한 파일 (지금 위치 → 원래 위치)
    var unreverted: [(current: URL, original: URL)] = []
}

/// 실행 중 강제 종료에 대비한 작업 기록. 실행 전에 저장하고 끝나면 지운다.
/// 다음 실행 때 남아 있으면 파일을 원래 이름으로 되돌릴지 묻는다
nonisolated struct RenameJournal: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let source: URL
        /// 이름 변경 1단계의 임시 이름. 복사면 nil
        let temp: URL?
        let destination: URL
    }

    let isCopy: Bool
    let entries: [Entry]

    static var fileURL: URL {
        let folder = URL.applicationSupportDirectory.appending(path: "WER", directoryHint: .isDirectory)
        return folder.appending(path: "rename-journal.json")
    }

    static func load() -> RenameJournal? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(RenameJournal.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// 실제 파일 작업. 원본 변경은 UUID 임시 이름을 거쳐 2단계로 바꾸고(맞바꾸기·대소문자만 바꾸기 대응),
/// 하나라도 실패하면 끝난 작업을 모두 되돌린다
struct RenameExecutor {
    private let fileManager = FileManager.default
    /// 복사본을 휴지통으로 옮길지 (설정). 휴지통을 쓸 수 없으면 영구 삭제한다
    var removesCopiesToTrash = AppSettings.removesCopiesToTrash

    /// 복사본을 지운다. 성공하면 로그에 남길 설명, 실패하면 nil.
    /// 네트워크 드라이브(NFS, SMB 등)처럼 휴지통이 없는 곳에서는 휴지통 이동이 실패하므로 영구 삭제로 넘어간다
    private func removeCopy(_ url: URL) -> String? {
        if removesCopiesToTrash {
            do {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
                return "Moved copy to Trash"
            } catch {
                // 휴지통을 쓸 수 없는 볼륨: 아래에서 영구 삭제
            }
        }
        do {
            try fileManager.removeItem(at: url)
            return removesCopiesToTrash ? "Deleted copy (Trash isn't available on this volume)" : "Deleted copy"
        } catch {
            return nil
        }
    }

    /// 실행 전 검사. 파일을 바꾸지 않는다. 문제가 있으면 (파일, 이유) 목록
    func preflight(_ plan: RenamePlan) -> [(item: RenamePlan.Item?, reason: String)] {
        var issues: [(item: RenamePlan.Item?, reason: String)] = []

        for item in plan.items where !fileManager.fileExists(atPath: item.source.path) {
            issues.append((item, "File not found (moved or deleted)"))
        }

        switch plan.mode {
        case .rename:
            let folders = Set(plan.items.map { $0.source.deletingLastPathComponent() })
            for folder in folders where !fileManager.isWritableFile(atPath: folder.path) {
                issues.append((nil, "No permission to write in \(folder.path)"))
            }
            // 다른 파일이 이미 그 이름을 쓰고 있는지. 이번에 이름을 바꾸는 파일끼리는 맞바꿀 수 있어 제외한다
            let caseSensitive = folders.first.map(FileNameComparer.isCaseSensitive(at:)) ?? true
            let key = { (url: URL) in FileNameComparer.key(url.path, caseSensitive: caseSensitive) }
            let sources = Set(plan.items.map { key($0.source) })
            for item in plan.items
            where fileManager.fileExists(atPath: item.destination.path) && !sources.contains(key(item.destination)) {
                issues.append((item, "A file with the new name already exists"))
            }
        case .copy(let destination):
            // 복사 위치가 없으면 만들 상위 폴더에 쓸 수 있어야 한다
            let writableFolder = fileManager.fileExists(atPath: destination.path)
                ? destination
                : destination.deletingLastPathComponent()
            if !fileManager.isWritableFile(atPath: writableFolder.path) {
                issues.append((nil, "No permission to write in \(writableFolder.path)"))
            }
            for item in plan.items where fileManager.fileExists(atPath: item.destination.path) {
                issues.append((item, "A file with the new name already exists in the copy folder"))
            }
            let needed = plan.items.reduce(Int64(0)) { total, item in
                total + Int64((try? item.source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            if let available = try? writableFolder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage,
               needed > available {
                let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                issues.append((nil, "Not enough disk space (needs \(format(needed)), \(format(available)) available)"))
            }
        }
        return issues
    }

    /// 계획대로 실행한다. 하나라도 실패하면 끝난 작업을 모두 되돌린다.
    /// 복사 실패 시에는 만든 복사본만 지우고 복사 폴더는 남긴다.
    /// progress는 진행률(0~1). 이름 바꾸기는 파일 개수, 복사는 용량 기준 (되돌리는 중에는 부르지 않는다)
    func execute(
        _ plan: RenamePlan, log: (RenameLogEntry) -> Void, progress: (Double) -> Void = { _ in }
    ) async -> RenameOutcome {
        switch plan.mode {
        case .rename: await rename(plan, log: log, progress: progress)
        case .copy(let destination): await copy(plan, into: destination, log: log, progress: progress)
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    // MARK: - Rename

    private func rename(_ plan: RenamePlan, log: (RenameLogEntry) -> Void, progress: (Double) -> Void) async -> RenameOutcome {
        let entries = plan.items.map { item in
            RenameJournal.Entry(
                source: item.source,
                temp: item.source.deletingLastPathComponent().appending(path: ".wer-tmp-\(UUID().uuidString)"),
                destination: item.destination
            )
        }
        do {
            try RenameJournal(isCopy: false, entries: entries).save()
        } catch {
            return RenameOutcome(succeeded: false, notStarted: true, failures: plan.items.prefix(1).map {
                ($0, "Could not write the recovery journal: \(error.localizedDescription)")
            })
        }
        defer { RenameJournal.clear() }

        // 두 단계를 합쳐 파일 수 × 2 걸음으로 센다
        let steps = Double(entries.count * 2)
        // 1단계: 원래 이름 → 임시 이름
        var movedToTemp: [Int] = []
        for (index, entry) in entries.enumerated() {
            do {
                try fileManager.moveItem(at: entry.source, to: entry.temp!)
                movedToTemp.append(index)
                progress(Double(index + 1) / steps)
                await Task.yield()
            } catch {
                var outcome = RenameOutcome(succeeded: false, failures: [(plan.items[index], error.localizedDescription)])
                outcome.unreverted = revertTemps(movedToTemp.map { entries[$0] }, log: log)
                return outcome
            }
        }
        // 2단계: 임시 이름 → 새 이름
        var renamed: [Int] = []
        for (index, entry) in entries.enumerated() {
            do {
                try fileManager.moveItem(at: entry.temp!, to: entry.destination)
                renamed.append(index)
                log(.item(.success, plan.items[index], "Renamed"))
                progress(Double(entries.count + index + 1) / steps)
                await Task.yield()
            } catch {
                var outcome = RenameOutcome(succeeded: false, failures: [(plan.items[index], error.localizedDescription)])
                // 새 이름 → 임시 이름으로 되돌린 뒤, 모든 임시 이름 → 원래 이름
                var unreverted: [(current: URL, original: URL)] = []
                for done in renamed.reversed() {
                    let entry = entries[done]
                    do {
                        try fileManager.moveItem(at: entry.destination, to: entry.temp!)
                    } catch {
                        unreverted.append((entry.destination, entry.source))
                    }
                }
                let stillInTemp = movedToTemp.map { entries[$0] }.filter { entry in
                    !unreverted.contains { $0.original == entry.source }
                }
                outcome.unreverted = unreverted + revertTemps(stillInTemp, log: log)
                return outcome
            }
        }
        return RenameOutcome(succeeded: true)
    }

    /// 임시 이름 → 원래 이름. 되돌리지 못한 파일 목록을 돌려준다
    private func revertTemps(_ entries: [RenameJournal.Entry], log: (RenameLogEntry) -> Void) -> [(current: URL, original: URL)] {
        var unreverted: [(current: URL, original: URL)] = []
        for entry in entries.reversed() {
            guard let temp = entry.temp else { continue }
            do {
                try fileManager.moveItem(at: temp, to: entry.source)
                log(RenameLogEntry(kind: .revert, message: entry.source.lastPathComponent, detail: "Reverted"))
            } catch {
                unreverted.append((temp, entry.source))
            }
        }
        return unreverted
    }

    // MARK: - Copy

    private func copy(
        _ plan: RenamePlan, into folder: URL, log: (RenameLogEntry) -> Void, progress: (Double) -> Void
    ) async -> RenameOutcome {
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return RenameOutcome(succeeded: false, notStarted: true, failures: plan.items.prefix(1).map {
                ($0, "Could not create the copy folder: \(error.localizedDescription)")
            })
        }
        let entries = plan.items.map { RenameJournal.Entry(source: $0.source, temp: nil, destination: $0.destination) }
        try? RenameJournal(isCopy: true, entries: entries).save()
        defer { RenameJournal.clear() }

        // 용량 기준 진행률. 모두 빈 파일이면 개수 기준
        let sizes = plan.items.map { fileSize($0.source) }
        let totalBytes = sizes.reduce(0, +)
        var copiedBytes: Int64 = 0
        var copied: [RenamePlan.Item] = []
        for (index, item) in plan.items.enumerated() {
            do {
                try fileManager.copyItem(at: item.source, to: item.destination)
                copied.append(item)
                log(.item(.success, item, "Copied"))
                copiedBytes += sizes[index]
                progress(totalBytes > 0
                    ? Double(copiedBytes) / Double(totalBytes)
                    : Double(index + 1) / Double(plan.items.count))
                await Task.yield()
            } catch {
                var outcome = RenameOutcome(succeeded: false, failures: [(item, error.localizedDescription)])
                // 이번에 만든 복사본만 지운다(설정에 따라 휴지통 또는 삭제). 복사 폴더는 남긴다
                for done in copied.reversed() {
                    if let detail = removeCopy(done.destination) {
                        log(RenameLogEntry(kind: .revert, message: done.destination.lastPathComponent, detail: detail))
                    } else {
                        outcome.unreverted.append((done.destination, done.source))
                    }
                }
                return outcome
            }
        }
        return RenameOutcome(succeeded: true)
    }

    // MARK: - Undo

    /// 마지막 실행을 되돌린다. 이름 변경은 원래 이름으로(임시 이름을 거쳐 맞바꾸기 대응),
    /// 복사는 복사본을 지운다(설정에 따라 휴지통 또는 삭제, 복사 폴더는 남긴다). 그사이 옮겨지거나 지워진 파일은 건너뛴다
    /// progress는 파일 개수 기준 진행률(0~1)
    func undo(
        _ plan: RenamePlan, log: (RenameLogEntry) -> Void, progress: (Double) -> Void = { _ in }
    ) async -> RenameOutcome {
        var outcome = RenameOutcome(succeeded: true)
        let count = Double(plan.items.count)
        if plan.isCopy {
            for (index, item) in plan.items.enumerated() {
                if let detail = removeCopy(item.destination) {
                    log(RenameLogEntry(kind: .revert, message: item.destination.lastPathComponent, detail: detail))
                } else {
                    outcome.unreverted.append((item.destination, item.source))
                }
                progress(Double(index + 1) / count)
                await Task.yield()
            }
            return outcome
        }

        // 새 이름 → 임시 이름 → 원래 이름
        var temps: [(item: RenamePlan.Item, temp: URL)] = []
        for (index, item) in plan.items.enumerated() {
            let temp = item.destination.deletingLastPathComponent().appending(path: ".wer-tmp-\(UUID().uuidString)")
            do {
                try fileManager.moveItem(at: item.destination, to: temp)
                temps.append((item, temp))
            } catch {
                outcome.unreverted.append((item.destination, item.source))
            }
            progress(Double(index + 1) / (count * 2))
            await Task.yield()
        }
        for (index, (item, temp)) in temps.enumerated() {
            do {
                try fileManager.moveItem(at: temp, to: item.source)
                log(RenameLogEntry(kind: .revert, message: "\(item.destination.lastPathComponent) → \(item.source.lastPathComponent)",
                                   detail: "Restored original name"))
            } catch {
                // 원래 이름을 다른 파일이 쓰고 있으면 새 이름으로 돌려놓는다
                try? fileManager.moveItem(at: temp, to: item.destination)
                outcome.unreverted.append((item.destination, item.source))
            }
            progress((count + Double(index + 1) * count / Double(temps.count)) / (count * 2))
            await Task.yield()
        }
        return outcome
    }

    // MARK: - Recovery

    /// 강제 종료로 남은 작업 기록대로 원래 상태로 되돌린다.
    /// 이름 변경은 임시 이름이나 새 이름으로 남은 파일을 원래 이름으로, 복사는 만든 복사본을 지운다
    func recover(_ journal: RenameJournal) -> [(current: URL, original: URL)] {
        var unrecovered: [(current: URL, original: URL)] = []
        for entry in journal.entries {
            if journal.isCopy {
                if fileManager.fileExists(atPath: entry.destination.path), removeCopy(entry.destination) == nil {
                    unrecovered.append((entry.destination, entry.source))
                }
                continue
            }
            guard !fileManager.fileExists(atPath: entry.source.path) else { continue }
            let current = [entry.temp, entry.destination].compactMap { $0 }.first { fileManager.fileExists(atPath: $0.path) }
            guard let current else { continue }
            do { try fileManager.moveItem(at: current, to: entry.source) } catch {
                unrecovered.append((current, entry.source))
            }
        }
        RenameJournal.clear()
        return unrecovered
    }
}
