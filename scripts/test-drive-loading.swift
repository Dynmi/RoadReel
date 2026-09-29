import Foundation
import AppKit

@main
struct DriveLoadingTests {
    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let volumes = root.appendingPathComponent("Volumes")
        try fm.createDirectory(at: volumes, withIntermediateDirectories: true)
        let suite = "RoadReel.DriveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(TeslaClipCategory.sentry.rawValue, forKey: "selectedCategory")
        let unresolvedBookmark = Data([1, 2, 3])
        defaults.set(unresolvedBookmark, forKey: "selectedTeslaCamDriveBookmark")
        let model = TeslaCamViewModel(defaults: defaults, volumesDirectory: volumes)
        defer { model.shutdown() }

        func check(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: message, code: 1) }
        }
        func waitFor(_ message: String, _ predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(8)
            while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            if !predicate() {
                print("FAILED: \(message); selected=\(model.selectedDriveID ?? "nil"), sentry=\(model.clips(for: .sentry).count), loading=\(model.isLoading), error=\(String(describing: model.sourceReadError))")
            }
            try check(predicate(), message)
        }
        func notify(_ name: Notification.Name, _ volume: URL) {
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil,
                userInfo: [NSWorkspace.volumeURLUserInfoKey: volume])
        }
        func fixture(_ drive: URL) throws {
            let event = drive.appendingPathComponent("TeslaCam/SentryClips/2026-01-01_12-00-00")
            try fm.createDirectory(at: event, withIntermediateDirectories: true)
            try fm.copyItem(at: root.appendingPathComponent("sample.mp4"),
                            to: event.appendingPathComponent("2026-01-01_12-00-00-front.mp4"))
        }

        let drive = volumes.appendingPathComponent("TESLADRIVE")
        try fixture(drive)
        model.bootstrap()
        try await waitFor("Startup loads connected drive") { model.clips(for: .sentry).count == 1 && !model.isLoading }
        try check(model.sourceReadError == nil && model.clips(for: .recent).isEmpty, "Missing optional categories are valid")
        try check(defaults.data(forKey: "selectedTeslaCamDriveBookmark") == unresolvedBookmark, "Unresolved bookmark is retained")
        print("PASS: startup discovers and loads connected drive; offline bookmark is retained")

        try await waitFor("Playback is ready") { model.session != nil }
        let sessionID = model.session!.id
        let unrelated = volumes.appendingPathComponent("OTHER")
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: true)
        notify(NSWorkspace.didMountNotification, unrelated)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(200))
        try check(model.session?.id == sessionID, "Unrelated mount and activation preserve playback")
        print("PASS: unrelated mounts and app activation do not reset active playback")

        let offline = root.appendingPathComponent("unplugged")
        try fm.moveItem(at: drive, to: offline)
        notify(NSWorkspace.didUnmountNotification, drive)
        try await waitFor("Unmount clears stale drive and footage") {
            model.selectedDriveID == nil && model.clips(for: .sentry).isEmpty && model.session == nil && !model.isLoading
        }
        try check(defaults.data(forKey: "selectedTeslaCamDriveBookmark") == unresolvedBookmark, "Unmount preserves authorization")
        try fm.moveItem(at: offline, to: drive)
        notify(NSWorkspace.didMountNotification, drive)
        try await waitFor("Reconnect loads automatically") { model.clips(for: .sentry).count == 1 && !model.isLoading }
        print("PASS: unplug clears state; replug automatically reloads footage")

        let renamed = volumes.appendingPathComponent("TESLADRIVE 1")
        try fm.moveItem(at: drive, to: renamed)
        notify(NSWorkspace.didRenameVolumeNotification, renamed)
        try await waitFor("Changed mount path is rediscovered") {
            model.selectedDriveID == renamed.appendingPathComponent("TeslaCam").path && model.clips(for: .sentry).count == 1 && !model.isLoading
        }
        print("PASS: changed mount path is rediscovered")

        let sentry = renamed.appendingPathComponent("TeslaCam/SentryClips")
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: sentry.path)
        model.loadSelectedDrive()
        try await waitFor("Permission failure is not an empty library") { model.needsSourceAccess && !model.isLoading }
        try check(model.sourceErrorMessage != nil, "Permission failure has a visible explanation")
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sentry.path)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await waitFor("Activation recovers failed scan") { model.clips(for: .sentry).count == 1 && model.sourceReadError == nil && !model.isLoading }
        print("PASS: denied access is reported; activation recovers after access is restored")

        try fm.moveItem(at: renamed, to: offline)
        notify(NSWorkspace.didUnmountNotification, renamed)
        try await waitFor("Unmount clears selection") { model.selectedDriveID == nil }
        // The device appears before TeslaCam is ready; no second mount event follows.
        try fm.createDirectory(at: drive, withIntermediateDirectories: true)
        notify(NSWorkspace.didMountNotification, drive)
        try await Task.sleep(for: .milliseconds(100))
        try fixture(drive)
        try await waitFor("Delayed recording directory is retried") { model.clips(for: .sentry).count == 1 && !model.isLoading }
        print("PASS: mount readiness retry discovers delayed TeslaCam directory")

        model.shutdown()
        try fm.moveItem(at: drive, to: root.appendingPathComponent("after-shutdown"))
        notify(NSWorkspace.didUnmountNotification, drive)
        try await Task.sleep(for: .milliseconds(200))
        try check(model.selectedDriveID != nil, "Shutdown removes drive observers")
        print("PASS: shutdown removes observers and cancels retries")
    }
}
