import AppKit
import Combine
import Sparkle

/// One updater per application, shared by every window. Sparkle owns download,
/// signature verification, sandboxed installation, rollback and relaunch.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUserDriver, SPUUpdaterDelegate {
    static let repositoryURL = URL(string: "https://github.com/Dynmi/RoadReel")!

    enum Phase { case idle, checking, downloading, extracting, installing }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var availableVersion: String?
    @Published private(set) var progress: Double?
    @Published private(set) var canCancel = false
    @Published private(set) var isFileOperationInProgress = false
    @Published var notice: String?
    var language: AppLanguage = .english

    private var updater: SPUUpdater!
    private var started = false
    private var startupError: Error?
    private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    private var cancelAction: (() -> Void)?
    private var installAfterCheck = false
    private var downloadedBytes: UInt64 = 0
    private var expectedBytes: UInt64 = 0
    private var busyWindows: Set<UUID> = []

    override init() {
        super.init()
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
    }

    var isInstalling: Bool { phase == .downloading || phase == .extracting || phase == .installing }
    var canInstall: Bool { availableVersion != nil && phase == .idle && !isFileOperationInProgress }

    var statusText: String {
        switch phase {
        case .idle: return language.text("更新", "Update")
        case .checking: return language.text("正在检查更新…", "Checking for updates…")
        case .downloading: return language.text("正在下载更新…", "Downloading update…")
        case .extracting: return language.text("正在验证并准备更新…", "Verifying and preparing update…")
        case .installing: return language.text("正在更新并重新打开…", "Installing and reopening…")
        }
    }

    func start() {
        guard !started else { return }
        started = true
        do {
            try updater.start()
            updater.checkForUpdatesInBackground()
        } catch {
            startupError = error
        }
    }

    func checkForUpdates() {
        start()
        if let startupError {
            notice = startupError.localizedDescription
        } else {
            updater.checkForUpdates()
        }
    }

    func setFileOperationInProgress(_ busy: Bool, window: UUID) {
        if busy { busyWindows.insert(window) } else { busyWindows.remove(window) }
        isFileOperationInProgress = !busyWindows.isEmpty
    }

    func install() {
        guard canInstall else { return }
        notice = nil
        if let reply = updateReply {
            updateReply = nil
            phase = .downloading
            reply(.install)
        } else {
            // An aborted download needs a fresh check; it must not reuse a stale reply.
            installAfterCheck = true
            checkForUpdates()
        }
    }

    func cancel() {
        let action = cancelAction
        cancelAction = nil
        canCancel = false
        installAfterCheck = false
        action?()
    }

    func show(_ request: SPUUpdatePermissionRequest,
                                     reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, automaticUpdateDownloading: false,
                                        sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        phase = .checking
        cancelAction = cancellation
        canCancel = true
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancelAction = nil
        canCancel = false
        phase = .idle
        guard !appcastItem.isInformationOnlyUpdate else {
            notice = language.text("此版本需要从 GitHub Release 页面手动安装。",
                                   "This release requires installation from the GitHub Releases page.")
            reply(.dismiss)
            return
        }
        availableVersion = appcastItem.displayVersionString
        updateReply = reply
        if installAfterCheck {
            installAfterCheck = false
            install()
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        availableVersion = nil
        notice = error.localizedDescription
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let failure = error as NSError
        if !isInstalling && failure.domain == SUSparkleErrorDomain
            && (failure.code == SUError.downloadError.rawValue || failure.code == SUError.appcastError.rawValue) {
            notice = language.text(
                "暂时无法从 GitHub 获取更新信息。尚未开始下载安装，RoadReel 仍可正常使用。请稍后再检查。",
                "Couldn’t check for updates on GitHub. No download or installation has started. You can keep using RoadReel and check again later."
            )
        } else {
            let summary = isInstalling
                ? language.text("更新未完成，当前版本仍可使用。", "Update not completed. Your current version is still available.")
                : language.text("暂时无法检查更新，当前版本仍可使用。", "Couldn’t check for updates. Your current version is still available.")
            notice = summary + "\n\n" + error.localizedDescription
        }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        phase = .downloading
        progress = nil
        downloadedBytes = 0
        expectedBytes = 0
        cancelAction = cancellation
        canCancel = true
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedBytes += length
        progress = expectedBytes > 0 ? min(1, Double(downloadedBytes) / Double(expectedBytes)) : nil
    }

    func showDownloadDidStartExtractingUpdate() {
        phase = .extracting
        progress = nil
        cancelAction = nil
        canCancel = false
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        self.progress = min(1, max(0, progress))
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // The sidebar click already authorizes installation and relaunch. Check
        // all windows again before allowing the installer to terminate the app.
        guard !isFileOperationInProgress else {
            notice = language.text("请等待录像处理完成后再更新。", "Wait for recording operations to finish, then try updating again.")
            reply(.skip)
            return
        }
        phase = .installing
        progress = nil
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
        canCancel = false
        progress = nil
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        availableVersion = nil
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        phase = .idle
        progress = nil
        canCancel = false
        updateReply = nil
        cancelAction = nil
        installAfterCheck = false
    }

    func showUpdateInFocus() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }
}
