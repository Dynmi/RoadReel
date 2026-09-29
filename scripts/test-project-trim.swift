import Foundation
import AVFoundation

@main
struct TrimTests {
    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "2026-01-01_12-00-00"
        let startDate = formatter.date(from: name)!
        let metadata = Data("{\"timestamp\":\"2026-01-01T12:00:04\",\"reason\":\"sentry_aware_object_detection\",\"city\":\"Test\"}".utf8)
        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: message, code: 1) }
        }
        func clip(at folder: URL, flat: Bool = false) throws -> TeslaClip {
            let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            var cameras: [TeslaCamera: [URL]] = [:]
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if let match = TeslaCamera.match(filename: file.lastPathComponent) {
                    if flat && match.baseName != name { continue }
                    cameras[match.camera, default: []].append(file)
                }
            }
            let firstDate = cameras.values.flatMap { $0 }.compactMap {
                TeslaCamera.match(filename: $0.lastPathComponent).flatMap { formatter.date(from: $0.baseName) }
            }.min()
            return TeslaClip(id: flat ? folder.appendingPathComponent(name).path : folder.path,
                             category: flat ? .recent : .sentry, displayDate: startDate,
                             playbackStartDate: firstDate, cameraSegments: cameras,
                             thumbnailURL: flat ? nil : folder.appendingPathComponent("thumb.png"), event: nil)
        }
        func fixture(_ label: String, flat: Bool = false) throws -> TeslaClip {
            let folder = root.appendingPathComponent(label).appendingPathComponent(flat ? "RecentClips" : name)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for camera in TeslaCamera.displayOrder {
                for (i, color) in (flat ? ["red"] : ["red", "lime", "blue"]).enumerated() {
                    let prefix = formatter.string(from: startDate.addingTimeInterval(Double(i * 3)))
                    try fm.copyItem(at: root.appendingPathComponent("\(color).mp4"),
                                    to: folder.appendingPathComponent("\(prefix)-\(camera.rawValue).mp4"))
                }
            }
            if !flat { try metadata.write(to: folder.appendingPathComponent("event.json")) }
            return try clip(at: folder, flat: flat)
        }
        func bytes(_ clip: TeslaClip) throws -> [String: Data] {
            try Dictionary(uniqueKeysWithValues: clip.cameraSegments.values.flatMap { $0 }.map { ($0.path, try Data(contentsOf: $0)) })
        }
        func range(_ duration: Double = 9, _ start: Double = 2, _ end: Double = 7) -> TeslaTrimSelection {
            var range = TeslaTrimSelection(duration: duration)!
            range.setStart(start); range.setEnd(end)
            return range
        }
        func mockTrash(_ urls: [URL]) async throws {
            let trash = root.appendingPathComponent("trash-\(UUID().uuidString)")
            try fm.createDirectory(at: trash, withIntermediateDirectories: true)
            for url in urls { try fm.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent)) }
        }
        func verify(_ clip: TeslaClip, duration: Double) async throws {
            try check(clip.cameraSegments.count == 6, "All six cameras retained")
            for urls in clip.cameraSegments.values {
                var total = 0.0
                for url in urls {
                    let asset = AVURLAsset(url: url)
                    let track = try await asset.loadTracks(withMediaType: .video).first!
                    total += try await track.load(.timeRange).duration.seconds
                    let size = try await track.load(.naturalSize)
                    try check(size == CGSize(width: 192, height: 128), "Native dimensions preserved")
                    try check(!(try await asset.loadTracks(withMediaType: .audio)).isEmpty, "Audio retained")
                }
                try check(abs(total - duration) < 0.1, "Camera duration \(total) must be \(duration)")
            }
        }

        var bounds = range()
        bounds.setStart(.nan); bounds.setEnd(.infinity)
        try check(bounds.start == 2 && bounds.end == 7, "Ignore non-finite input")
        bounds.setStart(100); bounds.setEnd(-100)
        try check(bounds.start == 6 && bounds.end == 7, "Prevent inverted or empty ranges")
        try check(TeslaTrimSelection(duration: 0) == nil, "Reject zero duration")
        var fractional = TeslaTrimSelection(duration: 9.12)!
        fractional.setStart(100)
        try check(fractional.start == 8, "Start matches native whole-second timestamps")
        print("PASS: range validation")

        let success = try fixture("success")
        let originals = try bytes(success)
        var progressUpdates: [(Int, Int)] = []
        let prepared = try await TeslaProjectTrimmer.prepare(clip: success, selection: range()) { done, total in
            progressUpdates.append((done, total))
        }
        try check(progressUpdates.map { $0.0 } == Array(1...6) && progressUpdates.allSatisfy { $0.1 == 6 },
                  "Parallel completion reports monotonic progress")
        try check(try bytes(success) == originals, "Preparation must not modify originals")
        try await TeslaProjectTrimmer.commit(prepared, recycle: mockTrash)
        let trimmed = try clip(at: URL(fileURLWithPath: success.id))
        try await verify(trimmed, duration: 5)
        try check(try Data(contentsOf: URL(fileURLWithPath: success.id).appendingPathComponent("event.json")) == metadata, "Preserve exact event metadata")
        try check(trimmed.playbackStartDate == startDate.addingTimeInterval(2), "Update native timestamps")
        try check(fm.fileExists(atPath: trimmed.thumbnailURL!.path), "Regenerate thumbnail")
        try check(!fm.fileExists(atPath: prepared.transaction.path), "Clean staging on success")
        print("PASS: six-camera cross-segment replacement, metadata, dimensions, audio, timestamps, thumbnail")

        let repeated = try fixture("repeat")
        let first = try await TeslaProjectTrimmer.prepare(clip: repeated, selection: range()) { _, _ in }
        try await TeslaProjectTrimmer.commit(first, recycle: mockTrash)
        let secondClip = try clip(at: URL(fileURLWithPath: repeated.id))
        let second = try await TeslaProjectTrimmer.prepare(clip: secondClip, selection: range(5, 2, 4)) { _, _ in }
        try await TeslaProjectTrimmer.commit(second, recycle: mockTrash)
        try await verify(try clip(at: URL(fileURLWithPath: repeated.id)), duration: 2)
        print("PASS: repeat trimming of an already shortened project")

        let native = try fixture("native-size")
        for source in native.cameraSegments[.front]! {
            try fm.removeItem(at: source)
            try fm.copyItem(at: root.appendingPathComponent("native-hevc.mp4"), to: source)
        }
        let nativePrepared = try await TeslaProjectTrimmer.prepare(clip: native, selection: range()) { _, _ in }
        try await TeslaProjectTrimmer.commit(nativePrepared, recycle: mockTrash)
        let nativeTrimmed = try clip(at: URL(fileURLWithPath: native.id))
        for source in nativeTrimmed.cameraSegments[.front]! {
            let track = try await AVURLAsset(url: source).loadTracks(withMediaType: .video).first!
            try check(try await track.load(.naturalSize) == CGSize(width: 1544, height: 1000), "HEVC native frame dimensions")
        }
        print("PASS: mixed camera dimensions and native 1544×1000 HEVC footage without audio")

        let varied = try fixture("camera-duration-variation")
        for (camera, index, file) in [(TeslaCamera.leftPillar, 0, "red-short"), (.rear, 1, "lime-short")] {
            let destination = varied.cameraSegments[camera]![index]
            try fm.removeItem(at: destination)
            try fm.copyItem(at: root.appendingPathComponent("\(file).mp4"), to: destination)
        }
        let variedOriginals = try bytes(varied)
        let variedSession = try await TeslaPlaybackSession.build(for: varied)
        try check(abs(variedSession.duration - 9) < 0.01 && abs(variedSession.trimDuration - 8.5) < 0.01,
                  "Trim uses the shortest camera, playback keeps the primary duration")
        var coveredRange = TeslaTrimSelection(duration: variedSession.trimDuration)!
        coveredRange.setStart(2)
        coveredRange.setEnd(9)
        try check(abs(coveredRange.end - 8.5) < 0.01, "End cannot extend beyond common coverage")
        variedSession.invalidate()
        do {
            _ = try await TeslaProjectTrimmer.prepare(clip: varied, selection: range(9, 2, 9)) { _, _ in }
            throw NSError(domain: "Expected uncovered range rejection", code: 1)
        } catch TeslaTrimError.rangeNotCovered { }
        try check(try bytes(varied) == variedOriginals, "Out-of-coverage range keeps every original")
        let variedPrepared = try await TeslaProjectTrimmer.prepare(clip: varied, selection: coveredRange) { _, _ in }
        try await TeslaProjectTrimmer.commit(variedPrepared, recycle: mockTrash)
        let variedTrimmed = try clip(at: URL(fileURLWithPath: varied.id))
        try await verify(variedTrimmed, duration: 6.5)
        let variedNames = variedTrimmed.cameraSegments.values.map { $0.compactMap { TeslaCamera.match(filename: $0.lastPathComponent)?.baseName } }
        try check(variedNames.allSatisfy { $0 == variedNames.first! }, "All trimmed cameras retain matching filenames")
        let variedAgain = try await TeslaProjectTrimmer.prepare(clip: variedTrimmed, selection: range(6.5, 1, 5)) { _, _ in }
        try await TeslaProjectTrimmer.commit(variedAgain, recycle: mockTrash)
        try await verify(try clip(at: URL(fileURLWithPath: varied.id)), duration: 4)
        print("PASS: unequal Tesla camera durations, shared endpoint, range rejection, and repeated trim")

        let rollback = try fixture("rollback")
        let rollbackBytes = try bytes(rollback)
        let failed = try await TeslaProjectTrimmer.prepare(clip: rollback, selection: range()) { _, _ in }
        do {
            try await TeslaProjectTrimmer.commit(failed) { _ in throw CocoaError(.fileWriteNoPermission) }
            throw NSError(domain: "Expected recycle failure", code: 1)
        } catch is CocoaError { }
        try check(try bytes(rollback) == rollbackBytes, "Restore every original after recycle failure")
        print("PASS: recycle failure rolls back every original byte")

        let uncertain = try fixture("uncertain-trash")
        let uncertainPrepared = try await TeslaProjectTrimmer.prepare(clip: uncertain, selection: range()) { _, _ in }
        do {
            try await TeslaProjectTrimmer.commit(uncertainPrepared) { urls in
                try await mockTrash(urls)
                throw CocoaError(.fileWriteUnknown)
            }
            throw NSError(domain: "Expected uncertain Trash result", code: 1)
        } catch TeslaTrimError.originalUnavailable { }
        try await verify(try clip(at: URL(fileURLWithPath: uncertain.id)), duration: 5)
        print("PASS: uncertain Trash completion keeps the verified replacement")

        let changed = try fixture("changed")
        let changedPrepared = try await TeslaProjectTrimmer.prepare(clip: changed, selection: range()) { _, _ in }
        try Data("changed by another process".utf8).write(to: URL(fileURLWithPath: changed.id).appendingPathComponent("event.json"))
        do {
            try await TeslaProjectTrimmer.commit(changedPrepared, recycle: mockTrash)
            throw NSError(domain: "Expected source change rejection", code: 1)
        } catch TeslaTrimError.sourceChanged { }
        try check(try bytes(changed) == Dictionary(uniqueKeysWithValues: originals.map { ( $0.key.replacingOccurrences(of: "/success/", with: "/changed/"), $0.value) }), "Source changes leave video intact")
        print("PASS: source change blocks replacement")

        let missing = try fixture("missing")
        try fm.removeItem(at: missing.cameraSegments[.rear]![1])
        do {
            _ = try await TeslaProjectTrimmer.prepare(clip: try clip(at: URL(fileURLWithPath: missing.id)), selection: range()) { _, _ in }
            throw NSError(domain: "Expected incomplete-camera rejection", code: 1)
        } catch TeslaTrimError.incompleteCameras { }
        print("PASS: missing camera segment rejected")

        let cancelled = try fixture("cancelled")
        let cancelledBytes = try bytes(cancelled)
        let task = Task { try await TeslaProjectTrimmer.prepare(clip: cancelled, selection: range()) { _, _ in } }
        task.cancel()
        do { _ = try await task.value; throw NSError(domain: "Expected cancellation", code: 1) }
        catch is CancellationError { }
        try check(try bytes(cancelled) == cancelledBytes, "Cancellation keeps original bytes")
        print("PASS: cancellation preserves originals")

        // Observe outputs from multiple cameras before any camera finishes, then
        // interrupt real AVFoundation work. No injected export mocks are involved.
        for failExport in [false, true] {
            let active = try fixture(failExport ? "parallel-failure" : "parallel-cancellation")
            for source in active.cameraSegments.values.flatMap({ $0 }) {
                try fm.removeItem(at: source)
                try fm.copyItem(at: root.appendingPathComponent("native-hevc.mp4"), to: source)
            }
            let originalBytes = try bytes(active)
            let parent = URL(fileURLWithPath: active.id).deletingLastPathComponent()
            var finished = false
            var completed = 0
            let operation = Task {
                defer { finished = true }
                return try await TeslaProjectTrimmer.prepare(clip: active, selection: range()) { done, _ in completed = done }
            }
            var interrupted = false
            var observedCameraCount = 0
            let deadline = Date().addingTimeInterval(10)
            while !finished && Date() < deadline {
                if let staging = try fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
                    .first(where: { $0.lastPathComponent.hasPrefix(".RoadReel-trim-") }) {
                    let replacement = staging.appendingPathComponent("replacement")
                    let files = (try? fm.contentsOfDirectory(at: replacement, includingPropertiesForKeys: nil)) ?? []
                    let startedCameras = Set(files.compactMap { TeslaCamera.match(filename: $0.lastPathComponent)?.camera })
                    if startedCameras.count >= 2 && completed == 0 {
                        observedCameraCount = startedCameras.count
                        if failExport {
                            // Collide with an upcoming segment while other exports are active.
                            let collision = replacement.appendingPathComponent("2026-01-01_12-00-06-back.mp4")
                            try Data("occupied destination".utf8).write(to: collision, options: .withoutOverwriting)
                        } else {
                            operation.cancel()
                        }
                        interrupted = true
                        break
                    }
                }
                await Task.yield()
            }
            if !interrupted { operation.cancel() }
            do {
                let unexpected = try await operation.value
                unexpected.discard()
                throw NSError(domain: "Expected interrupted parallel trim", code: 1)
            } catch is CancellationError {
                try check(!failExport && interrupted, "Cancellation occurs during concurrent exports")
            } catch TeslaExportError.cannotCreateExporter {
                try check(failExport && interrupted, "A failed export stops sibling cameras")
            }
            try check(interrupted, "Multiple camera jobs must overlap before completion")
            try check(try bytes(active) == originalBytes, "Interrupted parallel trim preserves all original bytes")
            try check(try fm.contentsOfDirectory(atPath: parent.path) == [URL(fileURLWithPath: active.id).lastPathComponent],
                      "All exporters have stopped and staging is removed")
            print("PASS: \(observedCameraCount) cameras overlap; \(failExport ? "failure" : "in-flight cancellation") drains exports and preserves originals")
        }

        let flat = try fixture("flat", flat: true)
        let unrelated = URL(fileURLWithPath: flat.id).deletingLastPathComponent().appendingPathComponent("2026-01-01_13-00-00-front.mp4")
        try fm.copyItem(at: root.appendingPathComponent("blue.mp4"), to: unrelated)
        let unrelatedBytes = try Data(contentsOf: unrelated)
        let flatPrepared = try await TeslaProjectTrimmer.prepare(clip: flat, selection: range(3, 1, 2)) { _, _ in }
        try await TeslaProjectTrimmer.commit(flatPrepared, recycle: mockTrash)
        try await verify(try clip(at: URL(fileURLWithPath: flat.id).deletingLastPathComponent(), flat: true), duration: 1)
        try check(try Data(contentsOf: unrelated) == unrelatedBytes, "Other Recent recordings untouched")
        print("PASS: flat Recent layout, unrelated recordings preserved")

        let ui = root.appendingPathComponent("UI/TeslaCam/SentryClips", isDirectory: true)
        try fm.createDirectory(at: ui, withIntermediateDirectories: true)
        let uiSource = try fixture("ui-source")
        try fm.copyItem(at: URL(fileURLWithPath: uiSource.id), to: ui.appendingPathComponent(name))
        print("UI fixture: \(ui.deletingLastPathComponent().path)")
    }
}
