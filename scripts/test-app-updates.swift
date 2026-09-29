import AppKit
import Combine

/// Runs the production updater against a local, signed fixture feed. The shell
/// runner gives every scenario its own sandbox and installed application copy.
@MainActor
final class UpdateTestDelegate: NSObject, NSApplicationDelegate {
    private let updater = AppUpdater()
    private var observations: Set<AnyCancellable> = []
    private var timeout: Timer?
    private var beganInstall = false
    private var manualCheck = false
    private var didCancel = false
    private var scenario: String { Bundle.main.object(forInfoDictionaryKey: "UpdateTestScenario") as! String }
    private var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("updater-test-result.txt")
    }

    func record(_ text: String) {
        let directory = logURL.deletingLastPathComponent()
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        try! (previous + text + "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    func finish(_ text: String) {
        record(text)
        timeout?.invalidate()
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "UpdateTestRole") as? String == "target" {
            guard Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" else {
                finish("FAIL wrong installed version")
                return
            }
            finish("PASS installed build 2 and relaunched")
            return
        }

        record("START " + scenario)
        timeout = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish("FAIL timeout") }
        }
        updater.$availableVersion.compactMap { $0 }.sink { [weak self] version in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self, !self.beganInstall else { return }
                self.beganInstall = true
                guard self.updater.phase == .idle else {
                    self.finish("FAIL downloaded without clicking")
                    return
                }
                self.record("PASS found " + version + " without downloading")
                let window = UUID()
                self.updater.setFileOperationInProgress(true, window: window)
                self.updater.install()
                guard self.updater.phase == .idle else {
                    self.finish("FAIL updated while recording operation was active")
                    return
                }
                self.record("PASS recording operation blocks installation")
                self.updater.setFileOperationInProgress(false, window: window)
                self.updater.install()
            }
        }.store(in: &observations)
        updater.$phase.sink { [weak self] phase in
            DispatchQueue.main.async {
                guard let self else { return }
                self.record("PHASE \(phase)")
                if phase == .downloading && ["cancel", "cancel-retry"].contains(self.scenario)
                    && !self.didCancel && self.updater.canCancel {
                    self.didCancel = true
                    self.updater.cancel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.updater.phase == .idle && self.updater.canInstall {
                            if self.scenario == "cancel-retry" {
                                self.record("PASS cancelled; retrying")
                                self.updater.install()
                            } else {
                                self.finish("PASS cancelled download; original intact; retry available")
                            }
                        } else {
                            self.finish("FAIL cancellation did not reset updater")
                        }
                    }
                }
            }
        }.store(in: &observations)
        updater.$notice.compactMap { $0 }.sink { [weak self] notice in
            DispatchQueue.main.async {
                guard let self else { return }
                self.record("NOTICE " + notice)
                if self.scenario == "corrupt" && self.beganInstall {
                    self.finish("PASS rejected corrupt update")
                } else if ["offline", "feed-corrupt"].contains(self.scenario) && self.manualCheck {
                    if self.scenario == "offline" && !notice.contains("No download or installation has started") {
                        self.finish("FAIL feed error incorrectly describes an installation failure")
                        return
                    }
                    self.finish("PASS manual check reports unavailable feed")
                } else if self.scenario == "current" && self.manualCheck {
                    self.finish("PASS current build does not offer downgrade")
                } else {
                    self.finish("FAIL unexpected updater notice")
                }
            }
        }.store(in: &observations)

        updater.start()
        if ["offline", "current", "feed-corrupt"].contains(scenario) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard self.updater.notice == nil && self.updater.availableVersion == nil else {
                    self.finish("FAIL automatic check interrupted the user")
                    return
                }
                self.record("PASS automatic check stayed quiet")
                self.manualCheck = true
                self.updater.checkForUpdates()
            }
        }
    }
}

@main
struct UpdateTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = UpdateTestDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) { }
    }
}
