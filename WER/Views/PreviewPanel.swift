//
//  PreviewPanel.swift
//  WER
//

import AVKit
import Quartz
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// ⑤ 미리보기. Finder처럼 하나를 선택하면 Quick Look, 여러 개면 개수를 보여준다.
/// 동영상·오디오는 재생 컨트롤바가 늘 보이는 자체 플레이어로, 문서는 썸네일을 먼저 보여준다.
struct PreviewPanel: View {
    let selection: Set<URL>
    /// Space 재생/일시정지 요청 (BrowserModel.playbackToggleRequest)
    let playbackToggleRequest: UUID?
    /// 파일 정보 레이어 (⌘I). 고른 항목 (없으면 비어 있다)
    var isFileInfoShown = false
    var fileInfoEntries: [FileInfoEntry] = []
    var fileDates: (URL) -> FileDates = { _ in FileDates() }
    /// 하나만 고른 항목의 파일 안 정보 (BrowserModel이 백그라운드로 읽는다)
    var selectionMedia: SelectionMedia?
    /// 읽어 둔 결과. 재생할 수 있는지 다시 열어 보지 않는 데 쓴다
    var cachedMedia: (URL) -> MediaReadResult? = { _ in nil }
    var onToggleFileInfo: () -> Void = {}
    /// 플레이어가 보이거나 사라질 때 (Space 재생은 플레이어가 있을 때만)
    var onPlayerChange: (URL, Bool) -> Void = { _, _ in }
    /// 재생을 시작하거나 멈출 때 (재생 중에는 방향키로 이동·음량, Quick Look은 열지 않는다)
    var onPlayingChange: (Bool) -> Void = { _ in }
    /// 방향키 ←→로 앞뒤로 옮겨 달라는 요청 (BrowserModel.playbackSeekRequest)
    var playbackSeekRequest: BrowserModel.SeekRequest?
    @AppStorage(AppSettings.previewEnabledKey) private var isEnabled = true
    /// 선택이 잠시 멈춘 뒤에 보여줄 파일. 방향키로 훑을 때 지나가는 파일은 읽지 않는다
    @State private var shownURL: URL?
    /// 플레이어로 재생할 수 있는지 확인한 결과. 재생할 수 없는 오디오·영상(ogg 등)은 문서처럼 보여준다
    @State private var playable: (url: URL, isPlayable: Bool)?

    private var selectedURL: URL? { selection.count == 1 ? selection.first : nil }

    /// 고른 항목의 파일 안 정보. 아직 읽지 않았으면 nil
    private var media: MediaReadResult? {
        selectionMedia.flatMap { $0.url == selectedURL ? $0.result : nil }
    }

    private struct ShownKey: Equatable {
        let url: URL?
        let isEnabled: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 미리보기를 끄면 파일 정보를 보여주는 칸이라 이름도 바꾼다
            PanelHeader(title: isEnabled ? "Preview" : "Info")
                // 제목 줄 너비의 절반 + 25를 볼륨 조절에 쓰고, 오른쪽 끝에 미리보기 끄기 버튼을 둔다
                .overlay {
                    GeometryReader { geometry in
                        HStack(spacing: 8) {
                            // 미리보기를 끄면 재생할 것이 없어 숨긴다 (자리는 비워 둔다)
                            VolumeControl()
                                .frame(width: geometry.size.width / 2 + 25)
                                .opacity(isEnabled ? 1 : 0)
                                .disabled(!isEnabled)
                            // 미리보기 위에 파일 정보를 겹쳐 띄운다 (⌘I)
                            Button(
                                isFileInfoShown ? "Hide Info" : "Show Info",
                                systemImage: isFileInfoShown ? "info.circle.fill" : "info.circle",
                                action: onToggleFileInfo
                            )
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(isFileInfoShown && isEnabled ? Color.accentColor : .secondary)
                            .frame(width: 20)
                            .disabled(!isEnabled || (selection.isEmpty && !isFileInfoShown))
                            .help(selection.isEmpty ? "Select a file or folder to show info"
                                : isFileInfoShown ? "Hide Info (⌘I)" : "Show Info (⌘I)")
                            // Info 상태에서는 칸이 파일 정보라 숨긴다. 눈 버튼이 움직이지 않게 자리는 남긴다
                            .opacity(isEnabled ? 1 : 0)
                            .accessibilityHidden(!isEnabled)
                            Button(
                                isEnabled ? "Turn Off Preview" : "Turn On Preview",
                                systemImage: isEnabled ? "eye" : "eye.slash"
                            ) {
                                isEnabled.toggle()
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                            .help(isEnabled ? "Turn Off Preview" : "Turn On Preview")
                        }
                        // Rename 칸 안이라 Rename 제목 줄처럼 여백을 두지 않는다
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                }
            Group {
                // 꺼져 있으면 Quick Look·플레이어를 만들지 않아 파일을 읽지 않는다 (SMB의 큰 파일)
                // 대신 파일을 열지 않고 아는 정보와 헤더만 읽은 파일 정보를 보여준다
                if !isEnabled {
                    if fileInfoEntries.isEmpty {
                        Text("No Selection")
                            .foregroundStyle(.secondary)
                    } else {
                        FileInfoView(entries: fileInfoEntries, dates: fileDates, media: media, style: .inline)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else if let url = selectedURL {
                    if shownURL != url {
                        Color.clear
                    } else if let kind = PreviewMediaKind(url), playable?.url == url, playable?.isPlayable == true {
                        // 파일이 바뀌면 플레이어를 새로 만든다
                        // Quick Look이 열려 있으면 멈추고 자동 재생하지 않는다 (소리가 겹치지 않게)
                        MediaPlayerView(
                            url: url, kind: kind,
                            playbackToggleRequest: playbackToggleRequest,
                            playbackSeekRequest: playbackSeekRequest,
                            isHeld: QuickLook.shared.isVisible,
                            onPlayingChange: onPlayingChange
                        )
                            .id(url)
                            .onAppear { onPlayerChange(url, true) }
                            .onDisappear { onPlayerChange(url, false) }
                    } else if DocumentPreviewView.isImage(url) {
                        QuickLookView(url: url)
                    } else {
                        DocumentPreviewView(url: url).id(url)
                    }
                } else if selection.count > 1, !fileInfoEntries.isEmpty {
                    // 파일 정보와 같은 문구 (예: 3 folders, 12 files / 12 files · 48.3 MB)
                    MultipleFileInfo(entries: fileInfoEntries)
                        .foregroundStyle(.secondary)
                } else {
                    Text(selection.isEmpty ? "No Selection" : "\(selection.count) items")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if isEnabled, isFileInfoShown, !fileInfoEntries.isEmpty {
                    FileInfoView(entries: fileInfoEntries, dates: fileDates, media: media)
                }
            }
            // 미리보기를 다시 켜면 재생 가능 여부를 그때 확인한다
            .task(id: ShownKey(url: selectedURL, isEnabled: isEnabled)) {
                guard let url = selectedURL else { return shownURL = nil }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                // 오디오·영상은 재생할 수 있는지 먼저 확인한다 (파일 정보의 재생 길이와 같은 기준)
                if PreviewMediaKind(url) != nil, isEnabled, playable?.url != url {
                    // 파일 정보가 이미 읽었으면 그 결과를 쓴다
                    let isPlayable = if let info = cachedMedia(url)?.info {
                        info.isPlayable
                    } else {
                        (try? await AVURLAsset(url: url).load(.isPlayable)) ?? false
                    }
                    guard !Task.isCancelled else { return }
                    playable = (url, isPlayable)
                }
                shownURL = url
            }
        }
    }
}

/// 문서. 전체 Quick Look은 파일을 모두 읽어 느리므로, Finder처럼 시스템이 캐시하는 썸네일을 먼저 보여주고
/// 클릭하면 전체 미리보기를 연다. 썸네일을 만들 수 없으면 바로 Quick Look
private struct DocumentPreviewView: View {
    let url: URL
    @State private var thumbnail: NSImage?
    @State private var showsFullPreview = false
    @Environment(\.displayScale) private var displayScale

    static func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .image) ?? false
    }

    var body: some View {
        if showsFullPreview {
            // Finder 미리보기 칸처럼 조작 막대 없는 간단한 미리보기 (엑셀은 첫 시트)
            QuickLookView(url: url, style: .compact)
        } else if let thumbnail {
            VStack(spacing: 8) {
                Button {
                    showsFullPreview = true
                } label: {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .help("Open full preview")
                Text("Click to open full preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else {
            ProgressView()
                .controlSize(.small)
                .task { await loadThumbnail() }
        }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 800, height: 800),
            scale: displayScale,
            representationTypes: .thumbnail
        )
        if let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage {
            thumbnail = image
        } else {
            showsFullPreview = true
        }
    }
}

/// 미리보기에서 자체 플레이어로 재생하는 파일 종류
nonisolated enum PreviewMediaKind {
    case video, audio

    init?(_ url: URL) {
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return nil }
        if type.conforms(to: .audio) {
            self = .audio
        } else if type.conforms(to: .audiovisualContent) {
            self = .video
        } else {
            return nil
        }
    }
}

/// Finder처럼 가운데에 재생 버튼(재생 중에는 마우스를 올리면 일시정지 버튼)을 두고, 아래에 컨트롤바를 늘 보여준다
private struct MediaPlayerView: View {
    let url: URL
    let kind: PreviewMediaKind
    let playbackToggleRequest: UUID?
    let playbackSeekRequest: BrowserModel.SeekRequest?
    /// Quick Look이 열려 있어 재생하지 않는다 (소리가 겹치지 않게)
    let isHeld: Bool
    let onPlayingChange: (Bool) -> Void

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isHovering = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var thumbnail: NSImage?
    @State private var videoSize: CGSize?
    @AppStorage(VolumeControl.volumeKey) private var volume: Double = 1
    @AppStorage(VolumeControl.mutedKey) private var isMuted = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                switch kind {
                case .video:
                    // 영상 비율에 맞춰 위아래(또는 좌우) 검은 여백이 생기지 않게 한다. 크기를 알기 전에는 숨긴다
                    PlayerLayerView(player: player)
                        .aspectRatio(videoSize.map { $0.width / $0.height }, contentMode: .fit)
                        .opacity(videoSize == nil ? 0 : 1)
                case .audio:
                    Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                if !isPlaying || isHovering {
                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 48))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "Pause" : "Play")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            controlBar
        }
        .task { await run() }
        .onDisappear {
            player?.pause()
            if isPlaying { onPlayingChange(false) }
        }
        .onChange(of: isPlaying) { _, playing in onPlayingChange(playing) }
        .onChange(of: playbackToggleRequest) { togglePlay() }
        .onChange(of: playbackSeekRequest) { _, request in
            guard let request, isPlaying else { return }
            let target = min(max(currentTime + request.seconds, 0), max(duration - 0.1, 0))
            currentTime = target
            seek(to: target)
        }
        .onChange(of: isHeld) { _, held in
            if held, isPlaying { togglePlay() }
        }
        .onChange(of: volume) { player?.volume = Float(volume) }
        .onChange(of: isMuted) { player?.isMuted = isMuted }
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            Button(action: togglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(isPlaying ? "Pause" : "Play")
            Text(Self.format(currentTime))
                .monospacedDigit()
            Slider(value: $currentTime, in: 0...max(duration, 0.1)) { editing in
                isScrubbing = editing
                if !editing { seek(to: currentTime) }
            }
            .controlSize(.small)
            .disabled(duration <= 0)
            Text(Self.format(duration))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private func togglePlay() {
        guard let player else { return }
        // Quick Look이 열려 있으면 재생을 시작하지 않는다
        if !isPlaying, isHeld { return }
        if isPlaying {
            player.pause()
        } else {
            // 끝까지 재생했으면 처음부터
            if duration > 0, currentTime >= duration - 0.1 { player.seek(to: .zero) }
            player.play()
        }
        isPlaying.toggle()
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 플레이어를 만들고, 뷰가 사라질 때까지 재생 위치와 상태를 따라간다
    private func run() async {
        let player = AVPlayer(url: url)
        player.volume = Float(volume)
        player.isMuted = isMuted
        self.player = player
        let asset = AVURLAsset(url: url)
        switch kind {
        case .audio: await loadThumbnail()
        case .video: videoSize = await MediaInfoReader.displaySize(of: asset)
        }
        if let time = try? await asset.load(.duration), time.isNumeric {
            duration = time.seconds
        }
        while !Task.isCancelled {
            if !isScrubbing {
                currentTime = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
                isPlaying = player.timeControlStatus != .paused
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    // 미리보기 이미지가 없으면(앨범 아트 없는 오디오 등) 파일 아이콘을 쓴다
    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 512, height: 512),
            scale: displayScale,
            representationTypes: .thumbnail
        )
        thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.isFinite ? seconds : 0)
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// 미리보기 볼륨. 앱 전체에서 하나라 Preview 제목 줄에 늘 보여준다
struct VolumeControl: View {
    static let volumeKey = "preview.volume"
    static let mutedKey = "preview.muted"

    @AppStorage(volumeKey) private var volume: Double = 1
    @AppStorage(mutedKey) private var isMuted = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isMuted.toggle()
            } label: {
                Image(systemName: symbol)
                    .frame(width: 18, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .help(isMuted ? "Unmute" : "Mute")
            Slider(value: $volume, in: 0...1) { _ in
                isMuted = false
            }
            .controlSize(.small)
            .help("Preview Volume")
        }
        .foregroundStyle(.secondary)
    }

    private var symbol: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

/// 컨트롤 없이 영상만 그린다 (컨트롤은 MediaPlayerView가 그린다)
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

private struct QuickLookView: NSViewRepresentable {
    let url: URL
    var style: QLPreviewViewStyle = .normal

    func makeNSView(context: Context) -> QLPreviewView {
        let view: QLPreviewView = QLPreviewView(frame: .zero, style: style)
        view.autostarts = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }

    // close()는 SwiftUI가 뷰를 해제하는 시점에 호출하면 SIGABRT가 나서 항목만 비운다
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.previewItem = nil
    }
}
