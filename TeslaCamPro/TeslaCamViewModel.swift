import Foundation
import AVKit
import AppKit
import Combine

enum TeslaClipCategory: String, CaseIterable, Identifiable {
    case recent = "RecentClips"
    case saved = "SavedClips"
    case sentry = "SentryClips"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Recent Clips"
        case .saved: return "Saved Clips"
        case .sentry: return "Sentry Clips"
        }
    }
}

enum TeslaCamera: String, CaseIterable, Hashable {
    case front = "front"
    case rear = "back"
    case leftRepeater = "left_repeater"
    case rightRepeater = "right_repeater"

    var title: String {
        switch self {
        case .front: return "Front"
        case .rear: return "Rear"
        case .leftRepeater: return "Left"
        case .rightRepeater: return "Right"
        }
    }

    static func from(filename: String) -> TeslaCamera? {
        let lowercased = filename.lowercased()
        if lowercased.hasSuffix("-front.mp4") { return .front }
        if lowercased.hasSuffix("-back.mp4") || lowercased.hasSuffix("-rear.mp4") { return .rear }
        if lowercased.hasSuffix("-left_repeater.mp4") { return .leftRepeater }
        if lowercased.hasSuffix("-right_repeater.mp4") { return .rightRepeater }
        return nil
    }
}

struct TeslaDrive: Identifiable, Hashable {
    let id: UUID
    let displayName: String
    let teslaCamURL: URL

    init(displayName: String, teslaCamURL: URL) {
        self.id = UUID()
        self.displayName = displayName
        self.teslaCamURL = teslaCamURL
    }
}

struct TeslaClip: Identifiable, Hashable {
    let id: UUID
    let category: TeslaClipCategory
    let baseName: String
    let date: Date?
    let cameraURLs: [TeslaCamera: URL]

    init(category: TeslaClipCategory, baseName: String, date: Date?, cameraURLs: [TeslaCamera: URL]) {
        self.id = UUID()
        self.category = category
        self.baseName = baseName
        self.date = date
        self.cameraURLs = cameraURLs
    }

    var displayTitle: String {
        if let date {
            return TeslaClip.formatter.string(from: date)
        }
        return baseName
    }

    var displaySubtitle: String {
        "\(cameraURLs.count) 个视角"
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

final class TeslaPlaybackSession {
    private(set) var players: [TeslaCamera: AVPlayer] = [:]

    init(clip: TeslaClip) {
        for (camera, url) in clip.cameraURLs {
            let player = AVPlayer(url: url)
            player.actionAtItemEnd = .pause
            player.volume = camera == .front ? 1.0 : 0
            players[camera] = player
        }
    }

    func player(for camera: TeslaCamera) -> AVPlayer? {
        players[camera]
    }

    var primaryPlayer: AVPlayer? {
        players[.front] ?? players.values.first
    }
}

@MainActor
final class TeslaCamViewModel: ObservableObject {
    @Published var availableDrives: [TeslaDrive] = []
    @Published var selectedDriveID: TeslaDrive.ID?
    @Published var selectedCategory: TeslaClipCategory = .recent
    @Published var selectedClipID: TeslaClip.ID?
    @Published var session: TeslaPlaybackSession?
    @Published var isLoading = false
    @Published var statusMessage: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false

    private var clipsByCategory: [TeslaClipCategory: [TeslaClip]] = [:]
    private var selectedClip: TeslaClip?
    private var periodicTimeObserver: Any?

    deinit {
        if let periodicTimeObserver, let player = session?.primaryPlayer {
            player.removeTimeObserver(periodicTimeObserver)
        }
    }

    func bootstrap() {
        refreshDrives()
        loadSelectedDrive()
    }

    func clips(for category: TeslaClipCategory) -> [TeslaClip] {
        clipsByCategory[category] ?? []
    }

    func refreshDrives() {
        let fm = FileManager.default
        let volumes = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []

        var drives: [TeslaDrive] = []
        for volume in volumes {
            let teslaCam = volume.appendingPathComponent("TeslaCam", isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: teslaCam.path, isDirectory: &isDir), isDir.boolValue {
                drives.append(TeslaDrive(displayName: volume.lastPathComponent, teslaCamURL: teslaCam))
            }
        }

        availableDrives = drives.sorted { $0.displayName < $1.displayName }
        if selectedDriveID == nil {
            selectedDriveID = availableDrives.first?.id
        } else if !availableDrives.contains(where: { $0.id == selectedDriveID }) {
            selectedDriveID = availableDrives.first?.id
        }
    }

    func pickDriveManually() {
        let panel = NSOpenPanel()
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "请选择 TeslaCam 文件夹或其上一级U盘根目录"

        if panel.runModal() == .OK, let url = panel.url {
            let teslaCamURL: URL
            if url.lastPathComponent == "TeslaCam" {
                teslaCamURL = url
            } else {
                teslaCamURL = url.appendingPathComponent("TeslaCam", isDirectory: true)
            }

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: teslaCamURL.path, isDirectory: &isDir), isDir.boolValue else {
                statusMessage = "未找到 TeslaCam 文件夹"
                return
            }

            let drive = TeslaDrive(displayName: url.lastPathComponent, teslaCamURL: teslaCamURL)
            availableDrives.insert(drive, at: 0)
            selectedDriveID = drive.id
            loadSelectedDrive()
        }
    }

    func loadSelectedDrive() {
        guard let drive = availableDrives.first(where: { $0.id == selectedDriveID }) else {
            clipsByCategory = [:]
            selectedClipID = nil
            session = nil
            statusMessage = "请先插入Tesla U盘"
            return
        }

        isLoading = true
        statusMessage = "正在扫描 \(drive.displayName)…"

        Task {
            let scanned = await Self.scan(teslaCamURL: drive.teslaCamURL)
            clipsByCategory = scanned
            isLoading = false
            statusMessage = "已加载 \(scanned.values.flatMap { $0 }.count) 条视频"

            if let first = clips(for: selectedCategory).first {
                selectedClipID = first.id
                activateSelectedClip()
            } else {
                session = nil
                selectedClipID = nil
            }
        }
    }

    func activateSelectedClip() {
        guard let selectedClipID else { return }
        guard let clip = clips(for: selectedCategory).first(where: { $0.id == selectedClipID }) else { return }

        selectedClip = clip
        session = TeslaPlaybackSession(clip: clip)
        configureTimeObserver()
        currentTime = 0
        duration = session?.primaryPlayer?.currentItem?.asset.duration.seconds ?? 0
        isPlaying = false
    }

    func togglePlayPause() {
        guard let session else { return }
        if isPlaying {
            for p in session.players.values { p.pause() }
        } else {
            for p in session.players.values { p.play() }
        }
        isPlaying.toggle()
    }

    func seekRelative(by delta: Double) {
        seekAll(to: max(0, min(duration, currentTime + delta)))
    }

    func seekAll(to seconds: Double) {
        guard let session else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        for p in session.players.values {
            p.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        currentTime = seconds
    }

    func timeText(_ value: Double) -> String {
        guard value.isFinite else { return "00:00" }
        let total = Int(value)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func configureTimeObserver() {
        if let periodicTimeObserver, let player = session?.primaryPlayer {
            player.removeTimeObserver(periodicTimeObserver)
            self.periodicTimeObserver = nil
        }

        guard let player = session?.primaryPlayer else { return }
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        periodicTimeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            if !self.currentTime.isNaN {
                self.currentTime = time.seconds
                self.duration = player.currentItem?.duration.seconds ?? 0
            }
        }
    }

    private static func scan(teslaCamURL: URL) async -> [TeslaClipCategory: [TeslaClip]] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fm = FileManager.default
                var output: [TeslaClipCategory: [TeslaClip]] = [:]
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

                for category in TeslaClipCategory.allCases {
                    let folder = teslaCamURL.appendingPathComponent(category.rawValue, isDirectory: true)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
                        output[category] = []
                        continue
                    }

                    let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil)
                    var grouped: [String: [TeslaCamera: URL]] = [:]

                    while let file = enumerator?.nextObject() as? URL {
                        guard file.pathExtension.lowercased() == "mp4" else { continue }
                        let name = file.lastPathComponent
                        guard let camera = TeslaCamera.from(filename: name) else { continue }

                        var base = name
                        base = base.replacingOccurrences(of: "-front.mp4", with: "")
                        base = base.replacingOccurrences(of: "-back.mp4", with: "")
                        base = base.replacingOccurrences(of: "-rear.mp4", with: "")
                        base = base.replacingOccurrences(of: "-left_repeater.mp4", with: "")
                        base = base.replacingOccurrences(of: "-right_repeater.mp4", with: "")

                        grouped[base, default: [:]][camera] = file
                    }

                    let clips = grouped.map { key, value in
                        TeslaClip(category: category, baseName: key, date: dateFormatter.date(from: key), cameraURLs: value)
                    }
                    .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

                    output[category] = clips
                }

                continuation.resume(returning: output)
            }
        }
    }
}
