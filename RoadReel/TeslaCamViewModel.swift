import Foundation
import AVFoundation
import AppKit
import Combine
import UniformTypeIdentifiers

enum TeslaClipCategory: String, CaseIterable, Identifiable, Sendable {
    case recent = "RecentClips"
    case saved = "SavedClips"
    case sentry = "SentryClips"

    var id: String { rawValue }

    var title: String {
        title(for: .simplifiedChinese)
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .recent: return language.text("最近录像", "Recent")
        case .saved: return language.text("已保存事件", "Saved Events")
        case .sentry: return language.text("哨兵事件", "Sentry Events")
        }
    }

    var systemImage: String {
        switch self {
        case .recent: return "clock.arrow.circlepath"
        case .saved: return "bookmark.fill"
        case .sentry: return "shield.fill"
        }
    }
}

enum TeslaCamera: String, CaseIterable, Hashable, Sendable {
    case front = "front"
    case rear = "back"
    case leftRepeater = "left_repeater"
    case rightRepeater = "right_repeater"
    case leftPillar = "left_pillar"
    case rightPillar = "right_pillar"

    var title: String {
        title(for: .simplifiedChinese)
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .front: return language.text("前视", "Front")
        case .rear: return language.text("后视", "Rear")
        case .leftRepeater: return language.text("左侧", "Left Repeater")
        case .rightRepeater: return language.text("右侧", "Right Repeater")
        case .leftPillar: return language.text("左 B 柱", "Left B-Pillar")
        case .rightPillar: return language.text("右 B 柱", "Right B-Pillar")
        }
    }

    var systemImage: String {
        switch self {
        case .front: return "arrow.up"
        case .rear: return "arrow.down"
        case .leftRepeater: return "arrow.up.left"
        case .rightRepeater: return "arrow.up.right"
        case .leftPillar: return "arrow.left"
        case .rightPillar: return "arrow.right"
        }
    }

    static var displayOrder: [TeslaCamera] {
        [.front, .leftPillar, .leftRepeater, .rear, .rightRepeater, .rightPillar]
    }

    static func match(filename: String) -> (camera: TeslaCamera, baseName: String)? {
        let lowercased = filename.lowercased()
        let suffixes: [(String, TeslaCamera)] = [
            ("-left_repeater.mp4", .leftRepeater),
            ("-right_repeater.mp4", .rightRepeater),
            ("-left_pillar.mp4", .leftPillar),
            ("-right_pillar.mp4", .rightPillar),
            ("-front.mp4", .front),
            ("-back.mp4", .rear),
            ("-rear.mp4", .rear),
        ]

        guard let (suffix, camera) = suffixes.first(where: { lowercased.hasSuffix($0.0) }) else {
            return nil
        }
        return (camera, String(filename.dropLast(suffix.count)))
    }
}

struct TeslaEvent: Hashable, Sendable {
    let timestamp: Date?
    let city: String?
    let street: String?
    let reason: String?

    var locationText: String? {
        let values: [String?] = [city, street]
        let parts: [String] = values.compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var reasonTitle: String {
        reasonTitle(for: .simplifiedChinese)
    }

    func reasonTitle(for language: AppLanguage) -> String {
        switch reason {
        case "user_interaction_honk": return language.text("鸣笛保存", "Saved by Honk")
        case "user_interaction_dashcam_icon_tapped": return language.text("手动保存", "Manually Saved")
        case "sentry_aware_object_detection": return language.text("哨兵检测", "Sentry Detection")
        case "sentry_aware_accel": return language.text("哨兵震动", "Sentry Impact")
        case let value? where !value.isEmpty:
            return value.replacingOccurrences(of: "_", with: " ")
        default:
            return language.text("事件", "Event")
        }
    }
}

struct TeslaDrive: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let teslaCamURL: URL

    init(displayName: String, teslaCamURL: URL) {
        let standardizedURL = teslaCamURL.standardizedFileURL
        self.id = standardizedURL.path
        self.displayName = displayName
        self.teslaCamURL = standardizedURL
    }
}

struct TeslaClip: Identifiable, Hashable, Sendable {
    let id: String
    let category: TeslaClipCategory
    let displayDate: Date?
    let playbackStartDate: Date?
    let cameraSegments: [TeslaCamera: [URL]]
    let thumbnailURL: URL?
    let event: TeslaEvent?

    static func == (lhs: TeslaClip, rhs: TeslaClip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var displayTitle: String {
        guard let displayDate else { return URL(fileURLWithPath: id).lastPathComponent }
        return Self.displayFormatter.string(from: displayDate)
    }

    var displaySubtitle: String {
        displaySubtitle(for: .simplifiedChinese)
    }

    func displaySubtitle(for language: AppLanguage) -> String {
        let cameraText = language.text("\(cameraSegments.count) 个视角", "\(cameraSegments.count) cameras")
        let segmentCount = cameraSegments.values.map(\.count).max() ?? 0
        let segmentText = segmentCount > 1
            ? language.text(" · \(segmentCount) 段", " · \(segmentCount) segments")
            : ""
        return cameraText + segmentText
    }

    var previewVideoURL: URL? {
        cameraSegments[.front]?.first ?? cameraSegments.values.first?.first
    }

    var eventOffset: Double? {
        guard let eventDate = event?.timestamp, let playbackStartDate else { return nil }
        let offset = eventDate.timeIntervalSince(playbackStartDate)
        return offset.isFinite && offset >= 0 ? offset : nil
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd  HH:mm:ss"
        return formatter
    }()
}

enum TeslaPlaybackError: LocalizedError {
    case noPlayableVideo

    var errorDescription: String? {
        message(for: .simplifiedChinese)
    }

    func message(for language: AppLanguage) -> String {
        language.text("没有找到可播放的视频轨道", "No playable video track was found")
    }
}

enum TeslaExportMode: Sendable {
    case full
    case aroundCurrent(radius: Double)

    var filenameSuffix: String {
        filenameSuffix(for: .simplifiedChinese)
    }

    func filenameSuffix(for language: AppLanguage) -> String {
        switch self {
        case .full: return language.text("完整录像", "Full Video")
        case .aroundCurrent: return language.text("事件片段", "Video Clip")
        }
    }
}

enum TeslaExportError: LocalizedError {
    case unavailable
    case invalidRange
    case cannotCreateExporter

    var errorDescription: String? {
        message(for: .simplifiedChinese)
    }

    func message(for language: AppLanguage) -> String {
        switch self {
        case .unavailable: return language.text("当前视角没有可导出的录像", "This camera has no video to export")
        case .invalidRange: return language.text("所选时间段无效", "The selected time range is invalid")
        case .cannotCreateExporter: return language.text("无法创建视频导出任务", "The video export could not be created")
        }
    }
}

enum TeslaDeleteError: LocalizedError {
    case noFiles
    case incomplete

    var errorDescription: String? {
        message(for: .simplifiedChinese)
    }

    func message(for language: AppLanguage) -> String {
        switch self {
        case .noFiles: return language.text("找不到这条录像对应的文件", "No files were found for this recording")
        case .incomplete: return language.text("部分文件未能移到废纸篓，请刷新后重试", "Some files could not be moved to Trash. Refresh and try again.")
        }
    }
}

@MainActor
final class TeslaPlaybackSession {
    let id = UUID()
    private(set) var players: [TeslaCamera: AVPlayer]
    let duration: Double
    let segmentMarkers: [Double]

    private init(players: [TeslaCamera: AVPlayer], duration: Double, segmentMarkers: [Double]) {
        self.players = players
        self.duration = duration
        self.segmentMarkers = segmentMarkers
    }

    static func build(for clip: TeslaClip) async throws -> TeslaPlaybackSession {
        var players: [TeslaCamera: AVPlayer] = [:]
        var durations: [TeslaCamera: Double] = [:]
        var markersByCamera: [TeslaCamera: [Double]] = [:]

        for camera in TeslaCamera.displayOrder {
            try Task.checkCancellation()
            guard let urls = clip.cameraSegments[camera], !urls.isEmpty else { continue }
            guard let result = try await makeComposition(from: urls, includeAudio: camera == .front) else { continue }
            let composition = result.composition

            let seconds = composition.duration.seconds
            guard seconds.isFinite, seconds > 0 else { continue }

            let item = AVPlayerItem(asset: composition)
            item.preferredForwardBufferDuration = 3
            item.preferredMaximumResolution = camera == .front
                ? CGSize(width: 1920, height: 1080)
                : CGSize(width: 1280, height: 720)

            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .pause
            player.automaticallyWaitsToMinimizeStalling = true
            player.volume = camera == .front ? 1 : 0
            players[camera] = player
            durations[camera] = seconds
            markersByCamera[camera] = result.segmentMarkers
        }

        guard !players.isEmpty else { throw TeslaPlaybackError.noPlayableVideo }
        let primaryCamera: TeslaCamera = players[.front] == nil
            ? TeslaCamera.displayOrder.first(where: { players[$0] != nil })!
            : .front
        let duration = durations[primaryCamera] ?? durations.values.max() ?? 0
        return TeslaPlaybackSession(
            players: players,
            duration: duration,
            segmentMarkers: markersByCamera[primaryCamera] ?? []
        )
    }

    func player(for camera: TeslaCamera) -> AVPlayer? { players[camera] }

    func asset(for camera: TeslaCamera) -> AVAsset? {
        players[camera]?.currentItem?.asset
    }

    var primaryPlayer: AVPlayer? {
        players[.front] ?? TeslaCamera.displayOrder.compactMap { players[$0] }.first
    }

    func play(rate: Float = 1) {
        let sanitizedRate = rate.isFinite ? min(2, max(0.25, rate)) : 1
        for player in players.values { player.playImmediately(atRate: sanitizedRate) }
    }

    func pause() {
        for player in players.values { player.pause() }
    }

    func setMuted(_ muted: Bool) {
        for player in players.values { player.isMuted = muted }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let target = CMTime(seconds: max(0, min(duration, seconds)), preferredTimescale: 600)
        for player in players.values {
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func correctDrift(relativeTo seconds: Double) {
        guard seconds.isFinite else { return }
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        for player in players.values where player !== primaryPlayer {
            let playerTime = player.currentTime().seconds
            guard playerTime.isFinite, abs(playerTime - seconds) > 0.35 else { continue }
            player.seek(
                to: target,
                toleranceBefore: CMTime(seconds: 0.08, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.08, preferredTimescale: 600)
            )
        }
    }

    func invalidate() {
        pause()
        for player in players.values {
            player.cancelPendingPrerolls()
            player.replaceCurrentItem(with: nil)
        }
        players.removeAll()
    }

    private struct CompositionResult {
        let composition: AVMutableComposition
        let segmentMarkers: [Double]
    }

    private static func makeComposition(from urls: [URL], includeAudio: Bool) async throws -> CompositionResult? {
        let composition = AVMutableComposition()
        var destinationVideoTrack: AVMutableCompositionTrack?
        var destinationAudioTrack: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        var segmentEnds: [Double] = []

        for url in urls {
            try Task.checkCancellation()
            do {
                let asset = AVURLAsset(url: url)
                guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first else { continue }
                let sourceRange = try await sourceVideoTrack.load(.timeRange)
                guard sourceRange.duration.isNumeric, sourceRange.duration.seconds > 0 else { continue }

                if destinationVideoTrack == nil {
                    destinationVideoTrack = composition.addMutableTrack(
                        withMediaType: .video,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                    if let transform = try? await sourceVideoTrack.load(.preferredTransform) {
                        destinationVideoTrack?.preferredTransform = transform
                    }
                }

                try destinationVideoTrack?.insertTimeRange(sourceRange, of: sourceVideoTrack, at: cursor)

                if includeAudio,
                   let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
                   let sourceAudioTrack = audioTracks.first,
                   let audioRange = try? await sourceAudioTrack.load(.timeRange) {
                    if destinationAudioTrack == nil {
                        destinationAudioTrack = composition.addMutableTrack(
                            withMediaType: .audio,
                            preferredTrackID: kCMPersistentTrackID_Invalid
                        )
                    }
                    let audioDuration = CMTimeMinimum(sourceRange.duration, audioRange.duration)
                    if audioDuration.isNumeric, audioDuration.seconds > 0 {
                        try? destinationAudioTrack?.insertTimeRange(
                            CMTimeRange(start: audioRange.start, duration: audioDuration),
                            of: sourceAudioTrack,
                            at: cursor
                        )
                    }
                }

                cursor = CMTimeAdd(cursor, sourceRange.duration)
                if cursor.seconds.isFinite { segmentEnds.append(cursor.seconds) }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A single damaged segment should not make the entire event unplayable.
                continue
            }
        }

        guard cursor.seconds.isFinite, cursor.seconds > 0 else { return nil }
        return CompositionResult(
            composition: composition,
            segmentMarkers: Array(segmentEnds.dropLast())
        )
    }
}

@MainActor
final class TeslaCamViewModel: ObservableObject {
    private static let driveBookmarkKey = "selectedTeslaCamDriveBookmark"

    @Published private(set) var availableDrives: [TeslaDrive] = []
    @Published var selectedDriveID: TeslaDrive.ID?
    @Published private(set) var selectedCategory: TeslaClipCategory = .recent
    @Published var selectedClipID: TeslaClip.ID?
    @Published private(set) var activeClip: TeslaClip?
    @Published private(set) var session: TeslaPlaybackSession?
    @Published private(set) var isLoading = false
    @Published private(set) var isPreparingPlayback = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var playbackError: String?
    @Published var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isExporting = false
    @Published private(set) var exportErrorMessage: String?
    @Published private(set) var isDeleting = false
    @Published private(set) var playbackRate: Float = 1
    @Published private(set) var isMuted = false
    @Published private(set) var language: AppLanguage = .simplifiedChinese

    private var clipsByCategory: [TeslaClipCategory: [TeslaClip]] = [:]
    private var scanTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var periodicTimeObserver: Any?
    private weak var timeObserverPlayer: AVPlayer?
    private var playbackEndedObserver: NSObjectProtocol?
    private var wasPlayingBeforeScrub = false
    private var isScrubbing = false
    private var lastDriftCorrectionSecond = -1
    private var securityScopedURL: URL?

    isolated deinit {
        if let periodicTimeObserver, let player = timeObserverPlayer {
            player.removeTimeObserver(periodicTimeObserver)
        }
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
        }
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    var safeDuration: Double {
        duration.isFinite && duration > 0 ? duration : 0
    }

    var safeCurrentTime: Double {
        guard currentTime.isFinite else { return 0 }
        return max(0, min(safeDuration, currentTime))
    }

    var eventMarkerTime: Double? {
        guard let offset = activeClip?.eventOffset,
              offset.isFinite,
              offset >= 0,
              safeDuration > 0,
              offset <= safeDuration else { return nil }
        return offset
    }

    func bootstrap() {
        if let savedCategory = UserDefaults.standard.string(forKey: "selectedCategory"),
           let category = TeslaClipCategory(rawValue: savedCategory) {
            selectedCategory = category
        }
        restoreSecurityScopedDrive()
        refreshDrives()
        loadSelectedDrive()
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        if !isLoading, !clipsByCategory.isEmpty {
            let count = clipsByCategory.values.reduce(0) { $0 + $1.count }
            statusMessage = language.text("已加载 \(count) 条录像", "Loaded \(count) recordings")
        }
    }

    func clips(for category: TeslaClipCategory) -> [TeslaClip] {
        clipsByCategory[category] ?? []
    }

    var canSelectPreviousClip: Bool {
        guard let selectedClipID,
              let index = clips(for: selectedCategory).firstIndex(where: { $0.id == selectedClipID }) else { return false }
        return index > 0
    }

    var canSelectNextClip: Bool {
        guard let selectedClipID,
              let index = clips(for: selectedCategory).firstIndex(where: { $0.id == selectedClipID }) else { return false }
        return index + 1 < clips(for: selectedCategory).count
    }

    func selectDrive(_ driveID: TeslaDrive.ID?) {
        guard selectedDriveID != driveID else { return }
        selectedDriveID = driveID
        loadSelectedDrive()
    }

    func selectCategory(_ category: TeslaClipCategory) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        UserDefaults.standard.set(category.rawValue, forKey: "selectedCategory")
        selectedClipID = clips(for: category).first?.id
        activateSelectedClip()
    }

    func selectClip(_ clip: TeslaClip) {
        guard clip.category == selectedCategory else { return }
        guard selectedClipID != clip.id else { return }
        selectedClipID = clip.id
        activateSelectedClip()
    }

    func selectAdjacentClip(offset: Int) {
        let categoryClips = clips(for: selectedCategory)
        guard let selectedClipID,
              let currentIndex = categoryClips.firstIndex(where: { $0.id == selectedClipID }) else { return }
        let targetIndex = currentIndex + offset
        guard categoryClips.indices.contains(targetIndex) else { return }
        selectClip(categoryClips[targetIndex])
    }

    func refreshDrives() {
        let fm = FileManager.default
        let volumes = (try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var drives: [TeslaDrive] = []
        for volume in volumes {
            let teslaCam = volume.appendingPathComponent("TeslaCam", isDirectory: true)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: teslaCam.path, isDirectory: &isDirectory), isDirectory.boolValue {
                drives.append(TeslaDrive(displayName: volume.lastPathComponent, teslaCamURL: teslaCam))
            }
        }

        if let securityScopedURL {
            let scopedTeslaCam = securityScopedURL.lastPathComponent == "TeslaCam"
                ? securityScopedURL
                : securityScopedURL.appendingPathComponent("TeslaCam", isDirectory: true)
            let manualDrive = TeslaDrive(displayName: securityScopedURL.lastPathComponent, teslaCamURL: scopedTeslaCam)
            if !drives.contains(where: { $0.id == manualDrive.id }) { drives.insert(manualDrive, at: 0) }
        }

        availableDrives = drives.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        if let selectedDriveID, availableDrives.contains(where: { $0.id == selectedDriveID }) {
            return
        }
        selectedDriveID = availableDrives.first?.id
    }

    func pickDriveManually() {
        let panel = NSOpenPanel()
        panel.prompt = language.text("选择", "Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = language.text("请选择 TeslaCam 文件夹或 U 盘根目录", "Choose the TeslaCam folder or the root of the USB drive")

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let teslaCamURL = selectedURL.lastPathComponent == "TeslaCam"
            ? selectedURL
            : selectedURL.appendingPathComponent("TeslaCam", isDirectory: true)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: teslaCamURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusMessage = language.text("所选位置中没有 TeslaCam 文件夹", "The selected location does not contain a TeslaCam folder")
            return
        }

        securityScopedURL?.stopAccessingSecurityScopedResource()
        _ = selectedURL.startAccessingSecurityScopedResource()
        securityScopedURL = selectedURL
        persistSecurityScopedDrive(selectedURL)

        let drive = TeslaDrive(displayName: selectedURL.lastPathComponent, teslaCamURL: teslaCamURL)
        if !availableDrives.contains(where: { $0.id == drive.id }) { availableDrives.insert(drive, at: 0) }
        selectedDriveID = drive.id
        loadSelectedDrive()
    }

    private func restoreSecurityScopedDrive() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.driveBookmarkKey) else { return }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard url.startAccessingSecurityScopedResource() else {
                UserDefaults.standard.removeObject(forKey: Self.driveBookmarkKey)
                return
            }
            securityScopedURL = url
            if isStale { persistSecurityScopedDrive(url) }
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.driveBookmarkKey)
        }
    }

    private func persistSecurityScopedDrive(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.driveBookmarkKey)
        } catch {
            statusMessage = language.text("目录已打开，但无法保存下次访问权限", "The folder is open, but access could not be saved for next time")
        }
    }

    func loadSelectedDrive() {
        scanTask?.cancel()
        stopPlayback()

        guard let drive = availableDrives.first(where: { $0.id == selectedDriveID }) else {
            clipsByCategory = [:]
            selectedClipID = nil
            statusMessage = language.text("请插入 Tesla U 盘或手动选择目录", "Insert a Tesla USB drive or choose a folder")
            return
        }

        isLoading = true
        playbackError = nil
        statusMessage = language.text("正在扫描 \(drive.displayName)…", "Scanning \(drive.displayName)…")
        let driveID = drive.id

        scanTask = Task { [weak self] in
            let scanned = await Self.scan(teslaCamURL: drive.teslaCamURL)
            guard let self, !Task.isCancelled, self.selectedDriveID == driveID else { return }

            self.clipsByCategory = scanned
            self.isLoading = false
            let eventCount = scanned.values.reduce(0) { $0 + $1.count }
            self.statusMessage = self.language.text("已加载 \(eventCount) 条录像", "Loaded \(eventCount) recordings")

            let selectedExists = self.clips(for: self.selectedCategory).contains { $0.id == self.selectedClipID }
            if !selectedExists { self.selectedClipID = self.clips(for: self.selectedCategory).first?.id }
            self.activateSelectedClip()
        }
    }

    func activateSelectedClip() {
        if activeClip?.id == selectedClipID, isPreparingPlayback || session != nil {
            return
        }
        playbackTask?.cancel()
        releaseSession()

        guard let selectedClipID,
              let clip = clips(for: selectedCategory).first(where: { $0.id == selectedClipID }) else {
            activeClip = nil
            return
        }

        activeClip = clip
        isPreparingPlayback = true
        playbackError = nil
        currentTime = 0
        duration = 0
        let clipID = clip.id

        playbackTask = Task { [weak self] in
            do {
                let newSession = try await TeslaPlaybackSession.build(for: clip)
                guard let self, !Task.isCancelled, self.selectedClipID == clipID else {
                    newSession.invalidate()
                    return
                }
                self.session = newSession
                self.duration = newSession.duration.isFinite ? max(0, newSession.duration) : 0
                newSession.setMuted(self.isMuted)
                self.isPreparingPlayback = false
                self.configureObservers()
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.selectedClipID == clipID else { return }
                self.isPreparingPlayback = false
                self.playbackError = self.message(for: error)
            }
        }
    }

    func togglePlayPause() {
        guard let session else { return }
        if isPlaying {
            session.pause()
            isPlaying = false
        } else {
            if safeDuration > 0, safeCurrentTime >= safeDuration - 0.1 {
                session.seek(to: 0)
                currentTime = 0
            }
            session.play(rate: playbackRate)
            isPlaying = true
        }
    }

    func seekRelative(by delta: Double) {
        seekAll(to: safeCurrentTime + delta)
    }

    func seekAll(to seconds: Double) {
        guard let session else { return }
        let sanitized = seconds.isFinite ? max(0, min(safeDuration, seconds)) : 0
        session.seek(to: sanitized)
        currentTime = sanitized
    }

    func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        session?.pause()
    }

    func updateScrubbing(to seconds: Double) {
        currentTime = seconds.isFinite ? max(0, min(safeDuration, seconds)) : 0
    }

    func endScrubbing() {
        guard isScrubbing else { return }
        session?.seek(to: safeCurrentTime)
        isScrubbing = false
        if wasPlayingBeforeScrub {
            session?.play(rate: playbackRate)
            isPlaying = true
        }
        wasPlayingBeforeScrub = false
    }

    func seekToEvent() {
        guard let eventMarkerTime else { return }
        seekAll(to: eventMarkerTime)
    }

    func seekToAdjacentSegment(forward: Bool) {
        guard let markers = session?.segmentMarkers, !markers.isEmpty else { return }
        if forward {
            let target = markers.first(where: { $0 > safeCurrentTime + 0.5 }) ?? safeDuration
            seekAll(to: target)
        } else {
            let target = markers.last(where: { $0 < safeCurrentTime - 0.5 }) ?? 0
            seekAll(to: target)
        }
    }

    func setPlaybackRate(_ rate: Float) {
        guard rate.isFinite else { return }
        playbackRate = min(2, max(0.25, rate))
        if isPlaying { session?.play(rate: playbackRate) }
    }

    func toggleMute() {
        isMuted.toggle()
        session?.setMuted(isMuted)
    }

    func revealActiveClip() {
        guard let clip = activeClip else { return }
        let clipURL = URL(fileURLWithPath: clip.id)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: clipURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            NSWorkspace.shared.activateFileViewerSelecting([clipURL])
        } else {
            let urls = clip.cameraSegments.values.flatMap { $0 }
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
    }

    func timeText(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "00:00" }
        let total = Int(value.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    func export(camera: TeslaCamera, mode: TeslaExportMode) {
        guard !isExporting else { return }
        guard let session, let asset = session.asset(for: camera) else {
            exportErrorMessage = TeslaExportError.unavailable.message(for: language)
            return
        }

        let exportRange: CMTimeRange?
        switch mode {
        case .full:
            exportRange = nil
        case .aroundCurrent(let radius):
            let center = safeCurrentTime
            let start = max(0, center - radius)
            let end = min(safeDuration, center + radius)
            guard start.isFinite, end.isFinite, end > start else {
                exportErrorMessage = TeslaExportError.invalidRange.message(for: language)
                return
            }
            exportRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )
        }

        let panel = NSSavePanel()
        panel.title = language.text("导出视频", "Export Video")
        panel.prompt = language.text("导出", "Export")
        switch mode {
        case .full:
            panel.message = language.text("导出当前视角的完整连续录像", "Export the complete video for the current camera")
        case .aroundCurrent:
            panel.message = language.text("导出当前播放位置前后各 30 秒（首尾会自动截断）", "Export 30 seconds before and after the current position")
        }
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = exportFilename(camera: camera, mode: mode)

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let destinationURL = selectedURL.pathExtension.isEmpty
            ? selectedURL.appendingPathExtension("mp4")
            : selectedURL

        isExporting = true
        exportErrorMessage = nil
        statusMessage = language.text("正在导出 \(camera.title(for: language))…", "Exporting \(camera.title(for: language))…")

        Task { [weak self] in
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                guard let exporter = AVAssetExportSession(
                    asset: asset,
                    presetName: AVAssetExportPresetPassthrough
                ) else {
                    throw TeslaExportError.cannotCreateExporter
                }
                if let exportRange { exporter.timeRange = exportRange }
                try await exporter.export(to: destinationURL, as: .mp4)

                guard let self else { return }
                self.isExporting = false
                self.statusMessage = self.language.text("已导出：\(destinationURL.lastPathComponent)", "Exported: \(destinationURL.lastPathComponent)")
            } catch is CancellationError {
                self?.isExporting = false
            } catch {
                guard let self else { return }
                self.isExporting = false
                self.statusMessage = self.language.text("视频导出失败", "Video export failed")
                self.exportErrorMessage = self.message(for: error)
            }
        }
    }

    func clearExportError() {
        exportErrorMessage = nil
    }

    func deleteClip(_ clip: TeslaClip) {
        guard !isDeleting, !isExporting else { return }
        let urls = deletionURLs(for: clip).filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !urls.isEmpty else {
            statusMessage = language.text("删除失败：", "Delete failed: ") + TeslaDeleteError.noFiles.message(for: language)
            return
        }

        let category = clip.category
        let originalIndex = clips(for: category).firstIndex(where: { $0.id == clip.id }) ?? 0
        let wasActive = activeClip?.id == clip.id
        if wasActive {
            playbackTask?.cancel()
            releaseSession()
        }

        isDeleting = true
        statusMessage = language.text("正在将 \(clip.displayTitle) 移到废纸篓…", "Moving \(clip.displayTitle) to Trash…")

        Task { [weak self] in
            do {
                try await Self.recycleItems(at: urls)
                guard let self else { return }

                var remaining = self.clips(for: category)
                remaining.removeAll { $0.id == clip.id }
                self.clipsByCategory[category] = remaining
                self.isDeleting = false
                self.statusMessage = self.language.text("已移到废纸篓：\(clip.displayTitle)", "Moved to Trash: \(clip.displayTitle)")

                if self.selectedClipID == clip.id {
                    self.activeClip = nil
                    if remaining.isEmpty {
                        self.selectedClipID = nil
                    } else {
                        self.selectedClipID = remaining[min(originalIndex, remaining.count - 1)].id
                        self.activateSelectedClip()
                    }
                }
            } catch {
                guard let self else { return }
                self.isDeleting = false
                self.statusMessage = self.language.text("删除失败：", "Delete failed: ") + self.message(for: error)
                if wasActive, self.selectedClipID == clip.id {
                    self.activeClip = nil
                    self.activateSelectedClip()
                }
            }
        }
    }

    static func recycleItems(at urls: [URL]) async throws {
        guard !urls.isEmpty else { throw TeslaDeleteError.noFiles }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle(urls) { recycled, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if recycled.count != urls.count {
                    continuation.resume(throwing: TeslaDeleteError.incomplete)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func shutdown() {
        scanTask?.cancel()
        playbackTask?.cancel()
        releaseSession()
    }

    private func exportFilename(camera: TeslaCamera, mode: TeslaExportMode) -> String {
        let clipName = (activeClip?.displayTitle ?? "TeslaCam")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "  ", with: " ")
        return "\(clipName) \(camera.title(for: language)) \(mode.filenameSuffix(for: language)).mp4"
    }

    private func message(for error: Error) -> String {
        if let error = error as? TeslaPlaybackError { return error.message(for: language) }
        if let error = error as? TeslaExportError { return error.message(for: language) }
        if let error = error as? TeslaDeleteError { return error.message(for: language) }
        return error.localizedDescription
    }

    private func deletionURLs(for clip: TeslaClip) -> [URL] {
        let clipURL = URL(fileURLWithPath: clip.id)
        var isDirectory: ObjCBool = false
        if clip.category != .recent,
           FileManager.default.fileExists(atPath: clipURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return [clipURL]
        }

        return Array(Set(clip.cameraSegments.values.flatMap { $0 }))
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func configureObservers() {
        removeObservers()
        guard let player = session?.primaryPlayer else { return }

        timeObserverPlayer = player
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.handleTimeUpdate(time.seconds)
            }
        }

        playbackEndedObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.safeDuration
            }
        }
    }

    private func handleTimeUpdate(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if !isScrubbing { currentTime = max(0, min(safeDuration, seconds)) }

        let wholeSecond = Int(seconds)
        if isPlaying, wholeSecond != lastDriftCorrectionSecond {
            lastDriftCorrectionSecond = wholeSecond
            session?.correctDrift(relativeTo: seconds)
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        activeClip = nil
        releaseSession()
    }

    private func releaseSession() {
        removeObservers()
        session?.invalidate()
        session = nil
        isPreparingPlayback = false
        isPlaying = false
        isScrubbing = false
        wasPlayingBeforeScrub = false
        currentTime = 0
        duration = 0
        lastDriftCorrectionSecond = -1
    }

    private func removeObservers() {
        if let periodicTimeObserver, let player = timeObserverPlayer {
            player.removeTimeObserver(periodicTimeObserver)
        }
        periodicTimeObserver = nil
        timeObserverPlayer = nil

        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
            self.playbackEndedObserver = nil
        }
    }

    private nonisolated static func scan(teslaCamURL: URL) async -> [TeslaClipCategory: [TeslaClip]] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

                var output: [TeslaClipCategory: [TeslaClip]] = [:]
                output[.recent] = scanRecent(
                    folder: teslaCamURL.appendingPathComponent(TeslaClipCategory.recent.rawValue, isDirectory: true),
                    formatter: formatter
                )
                output[.saved] = scanEvents(
                    category: .saved,
                    folder: teslaCamURL.appendingPathComponent(TeslaClipCategory.saved.rawValue, isDirectory: true),
                    formatter: formatter
                )
                output[.sentry] = scanEvents(
                    category: .sentry,
                    folder: teslaCamURL.appendingPathComponent(TeslaClipCategory.sentry.rawValue, isDirectory: true),
                    formatter: formatter
                )
                continuation.resume(returning: output)
            }
        }
    }

    private nonisolated static func scanRecent(folder: URL, formatter: DateFormatter) -> [TeslaClip] {
        let files = directoryContents(folder).filter { $0.pathExtension.lowercased() == "mp4" }
        let grouped = groupedVideos(files)
        return grouped.map { baseName, cameras in
            TeslaClip(
                id: folder.appendingPathComponent(baseName).path,
                category: .recent,
                displayDate: formatter.date(from: baseName),
                playbackStartDate: formatter.date(from: baseName),
                cameraSegments: cameras.mapValues { [$0] },
                thumbnailURL: nil,
                event: nil
            )
        }
        .sorted { ($0.displayDate ?? .distantPast) > ($1.displayDate ?? .distantPast) }
    }

    private nonisolated static func scanEvents(
        category: TeslaClipCategory,
        folder: URL,
        formatter: DateFormatter
    ) -> [TeslaClip] {
        let entries = directoryContents(folder)
        var clips: [TeslaClip] = []

        for eventFolder in entries where isDirectory(eventFolder) {
            let files = directoryContents(eventFolder)
            let videos = files.filter { $0.pathExtension.lowercased() == "mp4" }
            let grouped = groupedVideoSegments(videos)
            guard !grouped.isEmpty else { continue }

            let event = readEvent(at: eventFolder.appendingPathComponent("event.json"))
            let videoDates = videos.compactMap { url -> Date? in
                guard let match = TeslaCamera.match(filename: url.lastPathComponent) else { return nil }
                return formatter.date(from: match.baseName)
            }
            let playbackStart = videoDates.min()
            let folderDate = formatter.date(from: eventFolder.lastPathComponent)
            let thumbnail = eventFolder.appendingPathComponent("thumb.png")

            clips.append(TeslaClip(
                id: eventFolder.standardizedFileURL.path,
                category: category,
                displayDate: event?.timestamp ?? folderDate ?? playbackStart,
                playbackStartDate: playbackStart,
                cameraSegments: grouped,
                thumbnailURL: FileManager.default.fileExists(atPath: thumbnail.path) ? thumbnail : nil,
                event: event
            ))
        }

        let flatVideos = entries.filter { $0.pathExtension.lowercased() == "mp4" }
        let flatGroups = groupedVideos(flatVideos)
        clips.append(contentsOf: flatGroups.map { baseName, cameras in
            TeslaClip(
                id: folder.appendingPathComponent(baseName).path,
                category: category,
                displayDate: formatter.date(from: baseName),
                playbackStartDate: formatter.date(from: baseName),
                cameraSegments: cameras.mapValues { [$0] },
                thumbnailURL: nil,
                event: nil
            )
        })

        return clips.sorted { ($0.displayDate ?? .distantPast) > ($1.displayDate ?? .distantPast) }
    }

    private nonisolated static func groupedVideos(_ files: [URL]) -> [String: [TeslaCamera: URL]] {
        var grouped: [String: [TeslaCamera: URL]] = [:]
        for file in files {
            guard let match = TeslaCamera.match(filename: file.lastPathComponent) else { continue }
            grouped[match.baseName, default: [:]][match.camera] = file
        }
        return grouped
    }

    private nonisolated static func groupedVideoSegments(_ files: [URL]) -> [TeslaCamera: [URL]] {
        var grouped: [TeslaCamera: [URL]] = [:]
        for file in files {
            guard let match = TeslaCamera.match(filename: file.lastPathComponent) else { continue }
            grouped[match.camera, default: []].append(file)
        }
        return grouped.mapValues { $0.sorted { $0.lastPathComponent < $1.lastPathComponent } }
    }

    private nonisolated static func directoryContents(_ folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private nonisolated static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private nonisolated static func readEvent(at url: URL) -> TeslaEvent? {
        struct Payload: Decodable {
            let timestamp: String?
            let city: String?
            let street: String?
            let reason: String?
        }

        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return TeslaEvent(
            timestamp: payload.timestamp.flatMap { formatter.date(from: $0) },
            city: payload.city,
            street: payload.street,
            reason: payload.reason
        )
    }
}
