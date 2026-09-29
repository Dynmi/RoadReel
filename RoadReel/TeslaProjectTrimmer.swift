import Foundation
import AVFoundation
import AppKit

enum TeslaTrimError: LocalizedError {
    case incompleteCameras, rangeNotCovered, sourceChanged, invalidOutput
    case recoveryRequired(URL)
    case originalUnavailable(URL)

    var errorDescription: String? { message(for: .english) }

    func message(for language: AppLanguage) -> String {
        switch self {
        case .incompleteCameras:
            return language.text("部分机位存在缺失或损坏的片段，无法同步截取。原录像未改动。", "Some cameras have missing or damaged segments and cannot be trimmed together. The originals are unchanged.")
        case .rangeNotCovered:
            return language.text("所选时间段超出了部分机位的录像范围。请重新打开截取功能，选择所有机位都覆盖的时间段。原录像未改动。", "The selected range extends beyond some cameras’ recordings. Reopen Trim to select a range covered by all cameras. The originals are unchanged.")
        case .sourceChanged:
            return language.text("处理期间源文件发生变化，请重新载入后再试。", "The source files changed during processing. Reload the recording and try again.")
        case .invalidOutput:
            return language.text("截取结果校验失败，原录像未改动。", "The trimmed videos could not be verified. The originals are unchanged.")
        case .originalUnavailable(let url):
            return language.text("截取后的项目已保留在原位置，但无法确认原项目的废纸篓状态。请检查废纸篓及备份目录：\(url.path)", "The trimmed project is in place, but the original’s Trash status could not be confirmed. Check Trash and the backup folder: \(url.path)")
        case .recoveryRequired(let url):
            return language.text("替换未能完成。恢复文件保留在：\(url.path)", "Replacement could not be completed. Recovery files are preserved at: \(url.path)")
        }
    }
}

/// All writes are staged next to the source. Only a verified project can be committed.
@MainActor
enum TeslaProjectTrimmer {
    struct Prepared {
        let transaction: URL
        let replacement: URL
        let original: URL
        let sourceFiles: [URL]
        let isFolder: Bool
        fileprivate let snapshot: [String: FileStamp]

        func discard() { try? FileManager.default.removeItem(at: transaction) }
    }

    fileprivate struct FileStamp: Equatable {
        let size: Int?
        let modified: Date?
    }

    static func prepare(
        clip: TeslaClip,
        selection: TeslaTrimSelection,
        progress: (Int, Int) -> Void
    ) async throws -> Prepared {
        let fm = FileManager.default
        let original = URL(fileURLWithPath: clip.id)
        let isFolder = (try? original.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let sources = clip.cameraSegments.values.flatMap { $0 }
        guard !sources.isEmpty,
              sources.allSatisfy({ $0.deletingLastPathComponent().resolvingSymlinksInPath().path == (isFolder ? original : original.deletingLastPathComponent()).resolvingSymlinksInPath().path }),
              selection.duration > 0 else { throw TeslaTrimError.incompleteCameras }
        let snapshot = try sourceSnapshot(original: original, files: sources, isFolder: isFolder)
        let transaction = original.deletingLastPathComponent()
            .appendingPathComponent(".RoadReel-trim-\(UUID().uuidString)", isDirectory: true)
        let replacement = transaction.appendingPathComponent("replacement", isDirectory: true)
        try fm.createDirectory(at: replacement, withIntermediateDirectories: true)
        let prepared = Prepared(transaction: transaction, replacement: replacement, original: original,
                                sourceFiles: sources, isFolder: isFolder, snapshot: snapshot)
        do {
            if isFolder {
                for file in try fm.contentsOfDirectory(at: original, includingPropertiesForKeys: nil) {
                    if !sources.contains(file), file.lastPathComponent != "thumb.png" {
                        try fm.copyItem(at: file, to: replacement.appendingPathComponent(file.lastPathComponent))
                    }
                }
            }

            let cameras = TeslaCamera.displayOrder.filter { clip.cameraSegments[$0] != nil }
            var referenceNames: [String]?
            var referenceDurations: [Double]?
            var assets: [TeslaCamera: AVAsset] = [:]
            var previewURL: URL?
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            guard !isFolder || clip.playbackStartDate != nil else { throw TeslaTrimError.incompleteCameras }

            // Validate every camera before exporting. Tesla cameras can have different
            // frame counts for identically named segments; that is not missing footage.
            for camera in cameras {
                try Task.checkCancellation()
                let urls = clip.cameraSegments[camera]!
                let names = urls.compactMap { TeslaCamera.match(filename: $0.lastPathComponent)?.baseName }
                guard names.count == urls.count else { throw TeslaTrimError.incompleteCameras }
                var durations: [Double] = []
                for url in urls {
                    guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first else {
                        throw TeslaTrimError.incompleteCameras
                    }
                    let seconds = try await track.load(.timeRange).duration.seconds
                    guard seconds.isFinite, seconds > 0 else { throw TeslaTrimError.incompleteCameras }
                    durations.append(seconds)
                }
                if let referenceNames {
                    guard names == referenceNames else {
                        throw TeslaTrimError.incompleteCameras
                    }
                } else {
                    referenceNames = names
                    referenceDurations = durations
                }
                let asset = try await TeslaPlaybackSession.assetForTrimming(from: urls)
                guard try await asset.load(.duration).seconds >= selection.end - 0.002 else {
                    throw TeslaTrimError.rangeNotCovered
                }
                assets[camera] = asset
            }

            // One export per camera (at most six) runs concurrently; segments within
            // each camera stay sequential. The group drains cancelled exports before
            // the outer catch removes staging, so no writer can outlive cleanup.
            let cameraAssets = assets
            let segmentDurations = referenceDurations!
            try await withThrowingTaskGroup(of: (TeslaCamera, URL?).self) { group in
                for camera in cameras {
                    group.addTask { @MainActor in
                        var firstOutput: URL?
                        try Task.checkCancellation()
                        let urls = clip.cameraSegments[camera]!
                        let asset = cameraAssets[camera]!
                        guard let sourceTrack = try await asset.loadTracks(withMediaType: .video).first else {
                            throw TeslaTrimError.incompleteCameras
                        }
                        let sourceSize = try await sourceTrack.load(.naturalSize)
                        let sourceTransform = try await sourceTrack.load(.preferredTransform)
                        var cursor = 0.0
                        for (index, seconds) in segmentDurations.enumerated() {
                            let start = max(cursor, selection.start)
                            let end = min(cursor + seconds, selection.end)
                            cursor += seconds
                            guard end - start > 0.001 else { continue }
                            try Task.checkCancellation()
                            let filename = isFolder
                                ? "\(formatter.string(from: clip.playbackStartDate!.addingTimeInterval(start)))-\(camera.rawValue).mp4"
                                : urls[index].lastPathComponent
                            let destination = replacement.appendingPathComponent(filename)
                            guard !fm.fileExists(atPath: destination.path),
                                  let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
                                throw TeslaExportError.cannotCreateExporter
                            }
                            exporter.timeRange = CMTimeRange(
                                start: CMTime(seconds: start, preferredTimescale: 600),
                                end: CMTime(seconds: end, preferredTimescale: 600)
                            )
                            try await exportAsset(exporter, to: destination)
                            try Task.checkCancellation()
                            let output = AVURLAsset(url: destination)
                            guard let outputTrack = try await output.loadTracks(withMediaType: .video).first else {
                                throw TeslaTrimError.invalidOutput
                            }
                            let outputDuration = try await outputTrack.load(.timeRange).duration.seconds
                            let size = try await outputTrack.load(.naturalSize)
                            let transform = try await outputTrack.load(.preferredTransform)
                            let expectedSize = CGRect(origin: .zero, size: sourceSize).applying(sourceTransform).standardized.size
                            let actualSize = CGRect(origin: .zero, size: size).applying(transform).standardized.size
                            guard abs(outputDuration - (end - start)) < 0.1,
                                  abs(expectedSize.width - actualSize.width) < 1,
                                  abs(expectedSize.height - actualSize.height) < 1 else { throw TeslaTrimError.invalidOutput }
                            if firstOutput == nil { firstOutput = destination }
                        }
                        return (camera, firstOutput)
                    }
                }
                var completed = 0
                for try await (camera, firstOutput) in group {
                    try Task.checkCancellation()
                    if camera == cameras.first { previewURL = firstOutput }
                    completed += 1
                    progress(completed, cameras.count)
                }
            }
            if isFolder, let previewURL {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: previewURL))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 640, height: 640)
                let (image, _) = try await generator.image(at: .zero)
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    throw TeslaTrimError.invalidOutput
                }
                try data.write(to: replacement.appendingPathComponent("thumb.png"))
            }
            try Task.checkCancellation()
            return prepared
        } catch {
            prepared.discard()
            throw error
        }
    }

    static func commit(_ prepared: Prepared, recycle: ([URL]) async throws -> Void) async throws {
        let fm = FileManager.default
        guard try sourceSnapshot(original: prepared.original, files: prepared.sourceFiles, isFolder: prepared.isFolder) == prepared.snapshot else {
            prepared.discard()
            throw TeslaTrimError.sourceChanged
        }
        let backup = prepared.transaction.appendingPathComponent("original", isDirectory: true)
            .appendingPathComponent(prepared.original.lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        var movedOriginals: [(URL, URL)] = []
        var installed: [(URL, URL)] = []
        do {
            if prepared.isFolder {
                try fm.moveItem(at: prepared.original, to: backup)
                movedOriginals.append((prepared.original, backup))
                try fm.moveItem(at: prepared.replacement, to: prepared.original)
                installed.append((prepared.replacement, prepared.original))
            } else {
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                for source in prepared.sourceFiles {
                    let saved = backup.appendingPathComponent(source.lastPathComponent)
                    try fm.moveItem(at: source, to: saved)
                    movedOriginals.append((source, saved))
                }
                for output in try fm.contentsOfDirectory(at: prepared.replacement, includingPropertiesForKeys: nil) {
                    let destination = prepared.original.deletingLastPathComponent().appendingPathComponent(output.lastPathComponent)
                    try fm.moveItem(at: output, to: destination)
                    installed.append((output, destination))
                }
            }
            try await recycle([backup])
        } catch {
            // Never remove the new project unless every original is still available for rollback.
            guard movedOriginals.allSatisfy({ fm.fileExists(atPath: $0.1.path) }) else {
                throw TeslaTrimError.originalUnavailable(prepared.transaction)
            }
            do {
                for (staged, destination) in installed.reversed() { try fm.moveItem(at: destination, to: staged) }
                for (source, saved) in movedOriginals.reversed() { try fm.moveItem(at: saved, to: source) }
            } catch { throw TeslaTrimError.recoveryRequired(prepared.transaction) }
            prepared.discard()
            throw error
        }
        prepared.discard()
    }

    private static func sourceSnapshot(original: URL, files: [URL], isFolder: Bool) throws -> [String: FileStamp] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        var urls = files
        if !isFolder {
            let siblings = try FileManager.default.contentsOfDirectory(at: original.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            urls = Array(Set(files + siblings.filter { TeslaCamera.match(filename: $0.lastPathComponent)?.baseName == original.lastPathComponent }))
        }
        if isFolder {
            guard let enumerator = FileManager.default.enumerator(at: original, includingPropertiesForKeys: Array(keys)) else {
                throw TeslaTrimError.sourceChanged
            }
            urls = [original] + enumerator.allObjects.compactMap { $0 as? URL }
        }
        var result: [String: FileStamp] = [:]
        for url in urls {
            let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw TeslaTrimError.sourceChanged }
            result[url.path] = FileStamp(size: values.fileSize, modified: values.contentModificationDate)
        }
        return result
    }
}
