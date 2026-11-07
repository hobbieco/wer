//
//  EmptyFileCreator.swift
//  WER
//

import Foundation

/// Create Empty Files의 실제 파일 작업. 이미 있는 이름은 절대 덮어쓰지 않는다 (O_EXCL).
/// 취소하거나 실패하면 이번에 만든 파일만 지운다
nonisolated enum EmptyFileCreator {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 이미 있는 파일. 대소문자·한글 자모 비교는 파일 시스템에 맡긴다
    @concurrent
    static func existing(_ urls: [URL]) async -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 폴더가 있는 볼륨의 남은 용량(Finder와 같은 기준)과 sparse 파일 지원 여부
    struct VolumeSpace: Equatable, Sendable {
        /// 모르면 nil (일부 네트워크 볼륨)
        let available: Int64?
        let supportsSparse: Bool

        /// 이 계획에 공간이 모자라면 이유. Zeros는 sparse를 지원하는 볼륨이면 공간을 거의 쓰지 않는다
        func shortage(for plan: EmptyFilePlan) -> String? {
            let needsSpace = plan.fill == .random || !supportsSparse
            guard needsSpace, let available, plan.totalBytes > available else { return nil }
            let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            return "Not enough disk space (needs \(format(plan.totalBytes)), \(format(available)) available)"
        }
    }

    static func space(at folder: URL) -> VolumeSpace {
        let values = try? folder.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeSupportsSparseFilesKey,
        ])
        return VolumeSpace(
            available: values?.volumeAvailableCapacityForImportantUsage,
            supportsSparse: values?.volumeSupportsSparseFiles == true
        )
    }

    /// 네트워크 볼륨은 읽는 데 시간이 걸릴 수 있어 화면에서는 이것으로 읽는다
    @concurrent
    static func loadSpace(at folder: URL) async -> VolumeSpace {
        space(at: folder)
    }

    /// 실행 전 검사. 문제가 있으면 이유
    static func preflight(_ plan: EmptyFilePlan) -> String? {
        guard FileManager.default.isWritableFile(atPath: plan.folder.path) else {
            return "No permission to write in \(plan.folder.path)"
        }
        return space(at: plan.folder).shortage(for: plan)
    }

    /// 계획대로 만든다. progress는 0~1 (Random은 용량, Zeros는 개수 기준).
    /// 취소하면 CancellationError, 실패하면 Failure. 어느 쪽이든 이번에 만든 파일은 지운 뒤 던진다
    @concurrent
    static func create(
        _ plan: EmptyFilePlan, progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> [EmptyFilePlan.File] {
        var created: [EmptyFilePlan.File] = []
        let byBytes = plan.fill == .random && plan.totalBytes > 0
        let total = byBytes ? Double(plan.totalBytes) : Double(plan.files.count)
        var done = 0.0
        var reported = 0.0
        func report(_ value: Double) async {
            // 너무 자주 알리지 않는다 (0.5% 단위)
            guard value - reported >= 0.005 || value >= 1 else { return }
            reported = value
            await progress(Swift.min(value, 1))
        }

        do {
            for file in plan.files {
                try Task.checkCancellation()
                let handle = try open(file.url)
                // 만들기 시작한 파일은 중간에 실패해도 지운다
                created.append(file)
                defer { try? handle.close() }
                switch plan.fill {
                case .zeros:
                    try handle.truncate(atOffset: UInt64(file.size))
                case .random:
                    try await writeRandom(file.size, to: handle) { written in
                        await report((done + Double(written)) / total)
                    }
                }
                done += byBytes ? Double(file.size) : 1
                await report(done / total)
            }
            return created
        } catch {
            for file in created {
                try? FileManager.default.removeItem(at: file.url)
            }
            if error is CancellationError { throw error }
            if let failure = error as? Failure { throw failure }
            throw Failure(message: error.localizedDescription)
        }
    }

    /// 새 파일을 연다. 같은 이름이 있으면 실패한다 (덮어쓰지 않음)
    private static func open(_ url: URL) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard descriptor >= 0 else {
            let code = errno
            let reason = code == EEXIST ? "A file with the same name already exists" : String(cString: strerror(code))
            throw Failure(message: "\(url.lastPathComponent): \(reason)")
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static let chunkSize = 1 << 20

    /// 1 MiB씩 매번 새 난수로 채워 쓴다 (같은 덩어리를 반복하면 서버가 중복으로 줄일 수 있다)
    private static func writeRandom(_ size: Int64, to handle: FileHandle, progress: (Int64) async -> Void) async throws {
        var generator = SplitMix64(seed: UInt64.random(in: .min ... .max))
        var buffer = [UInt64](repeating: 0, count: chunkSize / 8)
        var written: Int64 = 0
        while written < size {
            try Task.checkCancellation()
            for index in buffer.indices { buffer[index] = generator.next() }
            let length = Int(Swift.min(Int64(chunkSize), size - written))
            try buffer.withUnsafeBytes { raw in
                try handle.write(contentsOf: UnsafeRawBufferPointer(rebasing: raw.prefix(length)))
            }
            written += Int64(length)
            await progress(written)
        }
    }

    /// 빠른 의사 난수. 암호용이 아니라 압축되지 않는 데이터를 만드는 용도
    private struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
