import SwiftUI
import AVFoundation
import AppKit

private enum AppPalette {
    // Keep the video workspace white; use macOS semantic colors for its controls.
    static let window = Color.white
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let browser = Color(nsColor: .textBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceRaised = Color(nsColor: .quaternaryLabelColor).opacity(0.45)
    static let board = Color(nsColor: .windowBackgroundColor)
    static let hover = Color(nsColor: .quaternaryLabelColor).opacity(0.3)
    static let border = Color(nsColor: .separatorColor).opacity(0.65)
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .secondaryLabelColor)
    static let accent = Color.accentColor
    static let sidebarSelection = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let event = Color(nsColor: .systemOrange)
    static let eventOnVideo = Color(nsColor: .systemYellow)
    static let eventCamera = event
}

private enum PlaybackLayout: Hashable, CaseIterable {
    case focus
    case overview
    case spatial
}

private func validAspectRatio(_ ratio: CGFloat?) -> CGFloat {
    guard let ratio, ratio.isFinite, ratio > 0 else { return 16 / 9 }
    return ratio
}

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var updater: AppUpdater
    @State private var updateWindowID = UUID()
    @State private var language: AppLanguage
    let onChangeLanguage: (AppLanguage) -> Void

    @StateObject private var viewModel = TeslaCamViewModel()
    @State private var searchText = ""
    @State private var clipPendingDeletion: TeslaClip?
    @State private var selectedCamera: TeslaCamera = .front
    @State private var playbackLayout: PlaybackLayout = .focus
    @State private var isFullScreen = false
    @AppStorage("newestFirst") private var newestFirst = true
    @State private var showingTelemetryInfo = false
    @FocusState private var isSearchFocused: Bool

    init(
        language: AppLanguage = .english,
        onChangeLanguage: @escaping (AppLanguage) -> Void = { _ in }
    ) {
        _language = State(initialValue: language)
        self.onChangeLanguage = onChangeLanguage
    }

    var body: some View {
        Group {
            if isFullScreen,
               playbackLayout == .focus,
               let session = viewModel.session,
               let player = session.player(for: selectedCamera) {
                fullScreenSingleView(session: session, player: player)
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: 104)
                    separator
                    clipBrowser.frame(width: 260)
                    separator
                    playerPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(.container, edges: .top)
                }
            }
        }
        .disabled(viewModel.isTrimming || updater.isInstalling)
        .overlay {
            if viewModel.isTrimming {
                ZStack {
                    AppPalette.window.opacity(0.65)
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text(viewModel.trimProgressText).font(.headline)
                        if !viewModel.isCommittingTrim {
                            Button(t("取消", "Cancel")) { viewModel.cancelTrimProcessing() }
                                .buttonStyle(QuietButtonStyle())
                        }
                    }
                    .padding(28)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(AppPalette.border, lineWidth: 1) }
                }
            }
        }
        .overlay {
            if updater.isInstalling {
                ZStack {
                    AppPalette.window.opacity(0.75)
                    VStack(spacing: 14) {
                        ProgressView(value: updater.progress).frame(width: 220)
                            .tint(Color(red: 0.60, green: 0.39, blue: 0.02))
                        Text(updater.statusText).font(.headline)
                        Text(t("完成后将自动重新打开 RoadReel", "RoadReel will reopen automatically"))
                            .font(.callout).foregroundStyle(AppPalette.textSecondary)
                        if updater.canCancel {
                            Button(t("取消", "Cancel")) { updater.cancel() }
                        }
                    }
                    .padding(28)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(AppPalette.border, lineWidth: 1) }
                }
            }
        }
        .foregroundStyle(AppPalette.textPrimary)
        .background(isFullScreen && playbackLayout == .focus ? Color.black : AppPalette.window)
        .frame(minWidth: 1020, minHeight: 720)
        .preferredColorScheme(.light)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: isFullScreen)
        .onAppear {
            updater.language = language
            updater.start()
            updater.setFileOperationInProgress(isProcessingRecordings, window: updateWindowID)
            viewModel.setLanguage(language)
            viewModel.bootstrap()
            syncFullScreenWithWindow()
            DispatchQueue.main.async { syncFullScreenWithWindow() }
        }
        .onChange(of: language) { _, newLanguage in
            viewModel.setLanguage(newLanguage)
            updater.language = newLanguage
        }
        .onChange(of: isProcessingRecordings) { _, busy in
            updater.setFileOperationInProgress(busy, window: updateWindowID)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            syncFullScreenWithWindow(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            syncFullScreenWithWindow(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            syncFullScreenWithWindow(notification)
        }
        .onDisappear {
            viewModel.shutdown()
            updater.setFileOperationInProgress(false, window: updateWindowID)
        }
        .alert(t("软件更新", "Software Update"), isPresented: Binding(
            get: { updater.notice != nil },
            set: { if !$0 { updater.notice = nil } }
        )) {
            Button(t("好", "OK")) { updater.notice = nil }
        } message: {
            Text(updater.notice ?? "")
        }
        .alert(
            t("导出失败", "Export Failed"),
            isPresented: Binding(
                get: { viewModel.exportErrorMessage != nil },
                set: { if !$0 { viewModel.clearExportError() } }
            )
        ) {
            Button(t("好", "OK")) { viewModel.clearExportError() }
        } message: {
            Text(viewModel.exportErrorMessage ?? t("未知错误", "Unknown error"))
        }
        .alert(
            t("截取并替换项目？", "Trim and replace recording?"),
            isPresented: $viewModel.confirmingTrim,
            presenting: viewModel.trimSelection
        ) { _ in
            Button(t("截取并替换", "Trim & Replace"), role: .destructive) { viewModel.applyTrim() }
            Button(t("取消", "Cancel"), role: .cancel) { }
        } message: { selection in
            Text(t(
                "所有机位仅保留 \(viewModel.timeText(selection.start))–\(viewModel.timeText(selection.end))。新项目保留原名称和录像结构，原项目移入废纸篓。",
                "Keep \(viewModel.timeText(selection.start))–\(viewModel.timeText(selection.end)) for all cameras, with the same project name and recording structure. The original goes to Trash."
            ))
        }
        .alert(
            t("截取未完成", "Trim Not Completed"),
            isPresented: Binding(
                get: { viewModel.trimErrorMessage != nil },
                set: { if !$0 { viewModel.clearTrimError() } }
            )
        ) {
            Button(t("好", "OK")) { viewModel.clearTrimError() }
        } message: {
            Text(viewModel.trimErrorMessage ?? "")
        }
        .alert(
            t("删除录像？", "Delete Recording?"),
            isPresented: Binding(
                get: { clipPendingDeletion != nil },
                set: { if !$0 { clipPendingDeletion = nil } }
            ),
            presenting: clipPendingDeletion
        ) { clip in
            Button(t("移到废纸篓", "Move to Trash"), role: .destructive) {
                viewModel.deleteClip(clip)
                clipPendingDeletion = nil
            }
            Button(t("取消", "Cancel"), role: .cancel) { clipPendingDeletion = nil }
        } message: { clip in
            let videoCount = clip.cameraSegments.values.reduce(0) { $0 + $1.count }
            Text(t(
                "“\(clip.displayTitle)”及其 \(videoCount) 个视频文件将被移到废纸篓，可在清空废纸篓前恢复。",
                "“\(clip.displayTitle)” and its \(videoCount) video \(videoCount == 1 ? "file" : "files") will be moved to Trash and can be restored until Trash is emptied."
            ))
        }
    }

    private func t(_ chinese: String, _ english: String) -> String {
        language.text(chinese, english)
    }

    private var separator: some View {
        Rectangle().fill(AppPalette.border).frame(width: 0.5)
    }

    private var isProcessingRecordings: Bool {
        viewModel.isTrimming || viewModel.isExporting || viewModel.isDeleting
    }

    private var selectedDrive: TeslaDrive? {
        viewModel.availableDrives.first { $0.id == viewModel.selectedDriveID }
    }

    private var suggestedCategory: TeslaClipCategory? {
        TeslaClipCategory.allCases.first {
            $0 != viewModel.selectedCategory && !viewModel.clips(for: $0).isEmpty
        }
    }

    private var sidebar: some View {
        VStack(alignment: .center, spacing: 0) {
            VStack(spacing: 7) {
                Link(destination: AppUpdater.repositoryURL) {
                    Image("BrandLogo")
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .frame(width: 44, height: 44)
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(AppPalette.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help(t("打开 RoadReel 开源项目", "Open the RoadReel repository"))
                .accessibilityLabel(t("RoadReel GitHub 项目", "RoadReel on GitHub"))

                Text("RoadReel")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            VStack(spacing: 6) {
                ForEach(TeslaClipCategory.allCases) { category in
                    categoryButton(category)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 16)
            updateControl
            statusCard
            driveCard
            capacityIndicator
            languageControl
            Link(destination: AppUpdater.repositoryURL) {
                Label("GitHub", systemImage: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(AppPalette.textSecondary)
            .help(t("打开 RoadReel 开源项目", "Open the RoadReel repository"))
            .padding(.top, 9)
        }
        .padding(.horizontal, 9)
        .padding(.top, 18)
        .padding(.bottom, 11)
        .background(AppPalette.sidebar)
    }

    @ViewBuilder
    private var updateControl: some View {
        if let version = updater.availableVersion {
            Button {
                guard !isProcessingRecordings else { return }
                updater.install()
            } label: {
                Label(t("更新", "Update"), systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.60, green: 0.39, blue: 0.02), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!updater.canInstall || isProcessingRecordings)
            .opacity(updater.canInstall && !isProcessingRecordings ? 1 : 0.5)
            .help(isProcessingRecordings
                  ? t("录像处理完成后即可更新", "Available after recording operations finish")
                  : t("下载 \(version) 并自动重启更新", "Download \(version), install and restart"))
            .accessibilityLabel(t("更新到 \(version)", "Update to \(version)"))
            .padding(.bottom, 10)
        } else if updater.phase == .checking {
            ProgressView().controlSize(.small)
                .help(updater.statusText)
                .padding(.bottom, 10)
        }
    }

    private var languageControl: some View {
        Picker(t("语言", "Language"), selection: Binding(get: { language }, set: { changeLanguage(to: $0) })) {
            ForEach(AppLanguage.allCases) { option in
                Text(option.shortName).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func changeLanguage(to newLanguage: AppLanguage) {
        guard language != newLanguage else { return }
        language = newLanguage
        onChangeLanguage(newLanguage)
    }

    private var driveCard: some View {
        VStack(spacing: 8) {
            Menu {
                ForEach(viewModel.availableDrives) { drive in
                    Button {
                        viewModel.selectDrive(drive.id)
                    } label: {
                        if drive.id == viewModel.selectedDriveID {
                            Label(drive.displayName, systemImage: "checkmark")
                        } else {
                            Text(drive.displayName)
                        }
                    }
                }
                Divider()
                Button(t("选择其他目录…", "Choose Another Folder…")) { viewModel.pickDriveManually() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppPalette.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(AppPalette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(selectedDrive == nil
                ? t("选择录像来源", "Choose a recording source")
                : [selectedDrive?.displayName, driveCapacityText].compactMap { $0 }.joined(separator: " · "))

            Text(selectedDrive?.displayName ?? t("未连接", "No drive"))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .help(selectedDrive?.displayName ?? t("未连接", "No drive"))

            HStack(spacing: 6) {
                Button { viewModel.pickDriveManually() } label: {
                    Image(systemName: "folder").frame(width: 14)
                }
                .buttonStyle(RailActionButtonStyle())
                .help(t("打开 TeslaCam 文件夹或 U 盘", "Open a TeslaCam folder or USB drive"))
                Button {
                    viewModel.refreshDrives()
                    viewModel.loadSelectedDrive()
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 14)
                }
                .buttonStyle(RailActionButtonStyle())
                .help(t("重新扫描录像", "Rescan recordings"))
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        }
    }

    private func categoryButton(_ category: TeslaClipCategory) -> some View {
        let selected = viewModel.selectedCategory == category
        let shortTitle: String
        switch category {
        case .recent: shortTitle = t("最近", "Recent")
        case .saved: shortTitle = t("已保存", "Saved")
        case .sentry: shortTitle = t("哨兵", "Sentry")
        }
        let count = viewModel.clips(for: category).count
        return Button {
            searchText = ""
            selectedCamera = .front
            viewModel.selectCategory(category)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? AppPalette.accent : AppPalette.textSecondary)
                    .frame(height: 23)
                Text(shortTitle)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(selected ? AppPalette.sidebarSelection : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppPalette.textSecondary)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 17, minHeight: 16)
                    .background(AppPalette.surfaceRaised, in: Capsule())
                    .padding(5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(category.title(for: language))
        .accessibilityLabel("\(category.title(for: language)), \(count)")
    }

    @ViewBuilder
    private var statusCard: some View {
        if viewModel.isLoading || viewModel.isDeleting || viewModel.isExporting || viewModel.statusMessage != nil {
            Group {
                if viewModel.isLoading || viewModel.isDeleting || viewModel.isExporting {
                    ProgressView().controlSize(.small).tint(AppPalette.accent)
                } else if selectedDrive == nil {
                    Image(systemName: "externaldrive.badge.questionmark").foregroundStyle(AppPalette.textSecondary)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppPalette.accent)
                }
            }
            .frame(width: 26, height: 26)
            .frame(maxWidth: .infinity)
            .help(viewModel.statusMessage ?? t("正在处理…", "Working…"))
            .accessibilityLabel(viewModel.statusMessage ?? t("正在处理…", "Working…"))
        }
    }

    private var driveCapacityText: String? {
        guard let capacity = driveCapacity else { return nil }
        let availableText = ByteCountFormatter.string(fromByteCount: capacity.available, countStyle: .file)
        return t("\(availableText) 可用", "\(availableText) free")
    }

    private var driveCapacity: (total: Int64, available: Int64)? {
        guard let selectedDrive,
              let values = try? selectedDrive.teslaCamURL.resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
              ),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity,
              total > 0,
              available >= 0 else { return nil }
        return (Int64(total), min(Int64(available), Int64(total)))
    }

    @ViewBuilder
    private var capacityIndicator: some View {
        if selectedDrive != nil {
            if let capacity = driveCapacity {
                let used = capacity.total - capacity.available
                let fraction = Double(used) / Double(capacity.total)
                let percent = Int((fraction * 100).rounded())
                let availableText = ByteCountFormatter.string(fromByteCount: capacity.available, countStyle: .file)
                let usedText = ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
                let totalText = ByteCountFormatter.string(fromByteCount: capacity.total, countStyle: .file)

                HStack(alignment: .center, spacing: 9) {
                    GeometryReader { geometry in
                        ZStack(alignment: .bottom) {
                            Capsule().fill(AppPalette.border)
                            Capsule()
                                .fill(AppPalette.accent)
                                .frame(height: geometry.size.height * fraction)
                        }
                    }
                    .frame(width: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("可用", "Free"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppPalette.textSecondary)
                        Text(availableText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppPalette.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text(t("容量", "Storage"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppPalette.textSecondary)
                        Text("\(percent)%")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppPalette.textPrimary)
                    }
                }
                .frame(minHeight: 100, idealHeight: 170, maxHeight: 170)
                .help(t("已用 \(usedText) / 总计 \(totalText)", "\(usedText) used of \(totalText)"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t("磁盘已用 \(percent)%，剩余 \(availableText)", "Storage \(percent)% used, \(availableText) free"))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 11)
                .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppPalette.border, lineWidth: 1)
                }
                .padding(.top, 10)
            } else {
                Text(t("容量不可用", "Storage unavailable"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppPalette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }
        }
    }

    private var filteredClips: [TeslaClip] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var clips = viewModel.clips(for: viewModel.selectedCategory)
        if !query.isEmpty {
            clips = clips.filter { clip in
                [clip.displayTitle, clip.event?.reasonTitle(for: language), clip.event?.locationText]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        return clips.sorted {
            let lhs = $0.displayDate ?? .distantPast
            let rhs = $1.displayDate ?? .distantPast
            return newestFirst ? lhs > rhs : lhs < rhs
        }
    }

    private var clipGroups: [ClipDayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredClips) { clip in
            clip.displayDate.map { calendar.startOfDay(for: $0) } ?? .distantPast
        }
        return groups.map { ClipDayGroup(date: $0.key, clips: $0.value) }
            .sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
    }

    private var clipBrowser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(viewModel.selectedCategory.title(for: language))
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if !searchText.isEmpty {
                    Text("\(filteredClips.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppPalette.textSecondary)
                        .accessibilityLabel(t("找到 \(filteredClips.count) 条录像", "\(filteredClips.count) results"))
                }

                Menu {
                    Button { newestFirst = true } label: {
                        Label(t("最新优先", "Newest First"), systemImage: newestFirst ? "checkmark" : "arrow.down")
                    }
                    Button { newestFirst = false } label: {
                        Label(t("最早优先", "Oldest First"), systemImage: newestFirst ? "arrow.up" : "checkmark")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").frame(width: 14, height: 16)
                }
                .menuStyle(.borderedButton)
                .menuIndicator(.hidden)
                .controlSize(.large)
                .help(t("更改排序", "Change sort order"))

                Button { requestDeleteSelectedClip() } label: {
                    Image(systemName: "trash").frame(width: 14, height: 16)
                }
                .buttonStyle(HeaderButtonStyle())
                .foregroundStyle(viewModel.selectedClipID == nil ? AppPalette.textTertiary : AppPalette.textSecondary)
                .disabled(viewModel.selectedClipID == nil || viewModel.isDeleting || viewModel.isExporting)
                .help(t("将所选录像移到废纸篓", "Move the selected recording to Trash"))
            }
            .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 12)

            searchField.padding(.horizontal, 12).padding(.bottom, 12)
            Rectangle().fill(AppPalette.border).frame(height: 1)

            Group {
                if viewModel.isLoading && filteredClips.isEmpty {
                    LoadingStateView(language: language)
                } else if filteredClips.isEmpty {
                    BrowserEmptyView(
                        language: language,
                        category: viewModel.selectedCategory,
                        hasDrive: selectedDrive != nil,
                        isSearching: !searchText.isEmpty,
                        suggestedCategory: suggestedCategory,
                        onClearSearch: { searchText = "" }
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                            ForEach(clipGroups) { group in
                                Section {
                                    ForEach(group.clips) { clip in clipButton(clip) }
                                } header: {
                                    ClipDayHeader(date: group.date, count: group.clips.count, language: language)
                                }
                            }
                        }
                        .padding(.horizontal, 8).padding(.bottom, 18)
                    }
                    .onDeleteCommand { requestDeleteSelectedClip() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppPalette.browser)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(AppPalette.textTertiary)
            TextField("", text: $searchText, prompt: Text(t("搜索录像", "Search recordings")).foregroundColor(AppPalette.textTertiary))
                .textFieldStyle(.plain).font(.subheadline)
                .accessibilityLabel(t("搜索录像", "Search recordings"))
                .focused($isSearchFocused)
                .help(t("按日期、地点或事件搜索", "Search by date, location, or event"))
                .keyboardShortcut("f", modifiers: .command)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppPalette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).frame(height: 35)
        .background(AppPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSearchFocused ? AppPalette.accent.opacity(0.5) : Color.clear, lineWidth: 2)
        }
    }

    private func clipButton(_ clip: TeslaClip) -> some View {
        Button {
            selectedCamera = .front
            viewModel.selectClip(clip)
        } label: {
            ClipRow(clip: clip, isSelected: clip.id == viewModel.selectedClipID, language: language)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                viewModel.selectClip(clip)
                viewModel.revealActiveClip()
            } label: {
                Label(t("在 Finder 中显示", "Show in Finder"), systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) { clipPendingDeletion = clip } label: {
                Label(t("移到废纸篓…", "Move to Trash…"), systemImage: "trash")
            }
            .disabled(viewModel.isDeleting || viewModel.isExporting)
        }
    }

    private func requestDeleteSelectedClip() {
        guard !viewModel.isDeleting,
              !viewModel.isExporting,
              let selectedClipID = viewModel.selectedClipID,
              let clip = viewModel.clips(for: viewModel.selectedCategory).first(where: { $0.id == selectedClipID }) else { return }
        clipPendingDeletion = clip
    }

    private var playerPanel: some View {
        VStack(spacing: 0) {
            Group {
                if viewModel.isPreparingPlayback {
                    PlayerLoadingView(clip: viewModel.activeClip, language: language)
                } else if let error = viewModel.playbackError {
                    ContentUnavailableView(
                        t("无法播放录像", "Unable to Play Recording"),
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(error)
                    )
                } else if let session = viewModel.session {
                    VStack(spacing: 6) {
                        VideoWorkspace(
                            session: session,
                            eventCamera: viewModel.activeClip?.event?.triggerCamera,
                            selectedCamera: $selectedCamera,
                            playbackLayout: $playbackLayout,
                            isExporting: viewModel.isExporting,
                            language: language,
                            onToggleFullScreen: toggleFullScreenPlayback,
                            onExport: { camera, mode in viewModel.export(camera: camera, mode: mode) }
                        )
                        .id(session.id)
                        ControlDeck(
                            viewModel: viewModel,
                            session: session,
                            language: language,
                            playbackLayout: $playbackLayout,
                            recordingActions: recordingActions
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .task(id: session.id) {
                        if session.player(for: selectedCamera) == nil {
                            selectedCamera = TeslaCamera.displayOrder.first(where: { session.player(for: $0) != nil }) ?? .front
                        }
                        if session.players.count < 2 {
                            playbackLayout = .focus
                        }
                    }
                } else {
                    PlayerEmptyView(
                        language: language,
                        hasDrive: selectedDrive != nil,
                        suggestedCategory: suggestedCategory,
                        errorMessage: viewModel.sourceErrorMessage,
                        needsAccess: viewModel.needsSourceAccess,
                        onChooseFolder: viewModel.pickDriveManually,
                        onSelectCategory: viewModel.selectCategory
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppPalette.window)
    }

    private var recordingActions: some View {
        HStack(spacing: 6) {
            if viewModel.isExporting {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small).tint(AppPalette.accent)
                    Text(t("正在导出", "Exporting")).font(.caption).foregroundStyle(AppPalette.textSecondary)
                }
            }

            Button { showingTelemetryInfo = true } label: {
                Image(systemName: "info.circle").frame(width: 14, height: 16)
            }
            .buttonStyle(HeaderButtonStyle())
            .help(t("为何没有车辆遥测数据？", "Why is vehicle telemetry unavailable?"))
            .popover(isPresented: $showingTelemetryInfo, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Label(t("车辆遥测", "Vehicle telemetry"), systemImage: "gauge.with.dots.needle.33percent")
                        .font(.headline)
                    Text(t(
                        "TeslaCam U 盘录像不包含车速、方向盘角度、刹车或电门数据。车机播放器可以使用车辆内部数据，但这些数据不会随录像导出。",
                        "TeslaCam USB recordings do not include speed, steering, brake, or accelerator data. The in-car player can access vehicle data that is not exported with the videos."
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(width: 320)
            }

            Button { viewModel.revealActiveClip() } label: {
                Image(systemName: "folder").frame(width: 14, height: 16)
            }
            .buttonStyle(HeaderButtonStyle()).help(t("在 Finder 中显示", "Show in Finder"))

            Menu {
                if playbackLayout == .focus {
                    Section(selectedCamera.title(for: language)) {
                        exportActions(for: selectedCamera)
                    }
                } else {
                    ForEach(TeslaCamera.displayOrder.filter { viewModel.session?.player(for: $0) != nil }, id: \.self) { camera in
                        Menu {
                            exportActions(for: camera)
                        } label: {
                            Label(camera.title(for: language), systemImage: camera.systemImage)
                        }
                    }
                }
            } label: {
                Label(t("导出", "Export"), systemImage: "square.and.arrow.up")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderedButton)
            .controlSize(.large)
            .fixedSize()
            .disabled(viewModel.session == nil || viewModel.isExporting)

            Button { toggleFullScreenPlayback() } label: {
                Image(systemName: isFullScreen ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .frame(width: 14, height: 16)
            }
            .buttonStyle(HeaderButtonStyle())
            .keyboardShortcut("f", modifiers: [.command, .control])
            .help(isFullScreen ? t("退出全屏", "Exit Full Screen") : t("全屏播放", "Play Full Screen"))
        }
        .fixedSize()
    }

    private func toggleFullScreenPlayback() {
        guard viewModel.session != nil else { return }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        if !window.styleMask.contains(.fullScreen) { playbackLayout = .focus }
        window.toggleFullScreen(nil)
    }

    private func fullScreenSingleView(session: TeslaPlaybackSession, player: AVPlayer) -> some View {
        GeometryReader { geometry in
            let aspect = validAspectRatio(session.aspectRatios[selectedCamera])
            let videoWidth = min(geometry.size.width, geometry.size.height * aspect)
            let videoHeight = videoWidth / aspect

            ZStack {
                Color.black
                CameraTile(
                    camera: selectedCamera,
                    player: player,
                    selected: true,
                    showsSelection: false,
                    prominent: true,
                    isEventCamera: false,
                    isExporting: viewModel.isExporting,
                    language: language,
                    onSelect: {},
                    onToggleFullScreen: toggleFullScreenPlayback,
                    onExport: { mode in viewModel.export(camera: selectedCamera, mode: mode) }
                )
                .id(ObjectIdentifier(player))
                .frame(width: videoWidth, height: videoHeight)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if viewModel.trimSelection != nil {
                        TrimControls(viewModel: viewModel, language: language)
                            .padding(12)
                            .background(AppPalette.board, in: RoundedRectangle(cornerRadius: 10))
                            .frame(maxWidth: 850)
                    }
                    fullScreenControls(session: session)
                }
                .padding(20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private func fullScreenControls(session: TeslaPlaybackSession) -> some View {
        HStack(spacing: 12) {
            Button { viewModel.beginTrimming() } label: { Image(systemName: "scissors") }
                .disabled(viewModel.trimSelection != nil || viewModel.isExporting)
                .help(t("截取录像", "Trim recording"))
                .accessibilityLabel(t("截取", "Trim"))
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(viewModel.isPlaying ? t("暂停播放", "Pause") : t("播放录像", "Play"))

            PlaybackSpeedControl(viewModel: viewModel, language: language)
            Text(viewModel.timeText(viewModel.safeCurrentTime))
                .frame(width: 42, alignment: .trailing)
            EventTimeline(
                language: language,
                value: Binding(
                    get: { viewModel.safeCurrentTime },
                    set: { viewModel.updateScrubbing(to: $0) }
                ),
                maximumValue: max(viewModel.safeDuration, 0.1),
                eventMarker: viewModel.eventMarkerTime,
                segmentMarkers: session.segmentMarkers,
                trimSelection: viewModel.trimSelection,
                onTrimBoundary: { viewModel.setTrimBoundary($0, isStart: $1) },
                onEditingChanged: { editing in
                    if editing { viewModel.beginScrubbing() } else { viewModel.endScrubbing() }
                }
            )
            Text(viewModel.timeText(viewModel.safeDuration))
                .frame(width: 42, alignment: .leading)
            PictureAdjustmentControls(adjustments: $viewModel.videoAdjustments, language: language)
            Button(action: toggleFullScreenPlayback) {
                Image(systemName: "rectangle.compress.vertical")
            }
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel(t("退出全屏", "Exit Full Screen"))
            .help(t("退出全屏", "Exit Full Screen"))
        }
        .buttonStyle(ImmersiveControlButtonStyle())
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(maxWidth: 850)
        .frame(height: 54)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func exportActions(for camera: TeslaCamera) -> some View {
        Button { viewModel.export(camera: camera, mode: .aroundCurrent(radius: 30)) } label: {
            Label(t("导出当前位置前后 30 秒…", "Export ±30 Seconds…"), systemImage: "scissors")
        }
        Button { viewModel.export(camera: camera, mode: .full) } label: {
            Label(t("导出完整视角…", "Export Full Camera…"), systemImage: "square.and.arrow.up")
        }
    }

    private func syncFullScreenWithWindow(_ notification: Notification? = nil) {
        let window = (notification?.object as? NSWindow)
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
        guard let window,
              window == NSApp.keyWindow || window == NSApp.mainWindow else { return }
        let actualState = window.styleMask.contains(.fullScreen)
        if isFullScreen != actualState { isFullScreen = actualState }
    }
}

private struct ClipDayGroup: Identifiable {
    let date: Date
    let clips: [TeslaClip]
    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

private struct ClipDayHeader: View {
    let date: Date
    let count: Int
    let language: AppLanguage

    var body: some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.textSecondary)
            Spacer()
            Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(AppPalette.textTertiary)
        }
        .padding(.horizontal, 9).padding(.top, 18).padding(.bottom, 7)
        .background(AppPalette.browser)
    }

    private var title: String {
        guard date != .distantPast else { return language.text("未知日期", "Unknown Date") }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return language.text("今天", "Today") }
        if calendar.isDateInYesterday(date) { return language.text("昨天", "Yesterday") }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language == .simplifiedChinese ? "M 月 d 日 EEEE" : "EEEE, MMM d"
        return formatter.string(from: date)
    }
}

private struct ClipRow: View {
    let clip: TeslaClip
    let isSelected: Bool
    let language: AppLanguage
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                ClipThumbnail(clip: clip)
                LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
                Text(language.text("\(clip.cameraSegments.count) 视角", "\(clip.cameraSegments.count) \(clip.cameraSegments.count == 1 ? "cam" : "cams")"))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 4)
            }
            .frame(width: 120, height: 75)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(timeText).font(.system(size: 13, weight: .semibold).monospacedDigit())
                if let event = clip.event, event.reason != "sentry_aware_object_detection" {
                    Text(event.reasonTitle(for: language)).font(.caption).foregroundStyle(isSelected ? .white : AppPalette.event).lineLimit(1)
                }
                if let detailText {
                    HStack(spacing: 4) {
                        if clip.event?.locationText != nil { Image(systemName: "mappin") }
                        Text(detailText).lineLimit(1)
                    }
                    .font(.caption2).foregroundStyle(isSelected ? Color.white.opacity(0.85) : AppPalette.textSecondary)
                }
            }
            .foregroundStyle(isSelected ? Color.white : AppPalette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            isSelected ? AppPalette.accent : (isHovering ? AppPalette.hover : Color.clear),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .contentShape(Rectangle()).onHover { isHovering = $0 }
    }

    private var timeText: String {
        guard let date = clip.displayDate else { return clip.displayTitle }
        return Self.formatter.string(from: date)
    }

    private var detailText: String? {
        let segmentCount = clip.cameraSegments.values.map(\.count).max() ?? 0
        let segmentText = segmentCount > 1
            ? language.text("\(segmentCount) 段", "\(segmentCount) segments")
            : nil
        let text = [clip.event?.locationText, segmentText]
            .compactMap { $0 }
            .joined(separator: " · ")
        return text.isEmpty ? nil : text
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct ClipThumbnail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let clip: TeslaClip
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            AppPalette.surfaceRaised
            if let image {
                Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Image(systemName: "video.fill").font(.title3).foregroundStyle(AppPalette.textTertiary)
            }
        }
        .clipped()
        .task(id: clip.thumbnailRevision) {
            image = nil
            guard let data = await ThumbnailService.shared.imageData(for: clip), !Task.isCancelled else { return }
            if reduceMotion {
                image = NSImage(data: data)
            } else {
                withAnimation(.easeOut(duration: 0.16)) { image = NSImage(data: data) }
            }
        }
    }
}

private struct PlaybackLayoutPicker: View {
    @Binding var playbackLayout: PlaybackLayout
    let language: AppLanguage
    let hasMultipleCameras: Bool

    var body: some View {
        Picker(language.text("镜头布局", "Camera Layout"), selection: $playbackLayout) {
            Text(language.text("单镜头", "Single")).tag(PlaybackLayout.focus)
            Text(language.text("多视角", "All Cameras")).tag(PlaybackLayout.overview)
            Text(language.text("方位", "Spatial")).tag(PlaybackLayout.spatial)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(width: language == .english ? 264 : 218)
        .disabled(!hasMultipleCameras)
        .accessibilityLabel(language.text("镜头布局", "Camera Layout"))
    }
}

private struct VideoWorkspace: View {
    let session: TeslaPlaybackSession
    let eventCamera: TeslaCamera?
    @Binding var selectedCamera: TeslaCamera
    @Binding var playbackLayout: PlaybackLayout
    let isExporting: Bool
    let language: AppLanguage
    let onToggleFullScreen: () -> Void
    let onExport: (TeslaCamera, TeslaExportMode) -> Void

    private var availableCameras: [TeslaCamera] {
        TeslaCamera.displayOrder.filter { session.player(for: $0) != nil }
    }

    @ViewBuilder
    var body: some View {
        if playbackLayout == .overview {
            overviewGrid
        } else if playbackLayout == .spatial {
            spatialWorkspace
        } else {
            focusWorkspace
        }
    }

    private var focusWorkspace: some View {
        VStack(spacing: 6) {
            if let player = session.player(for: selectedCamera) {
                CameraTile(
                    camera: selectedCamera,
                    player: player,
                    selected: true,
                    showsSelection: false,
                    prominent: true,
                    isEventCamera: false,
                    isExporting: isExporting,
                    language: language,
                    onSelect: {},
                    onToggleFullScreen: onToggleFullScreen,
                    onExport: { onExport(selectedCamera, $0) }
                )
                .id(ObjectIdentifier(player))
                .aspectRatio(validAspectRatio(session.aspectRatios[selectedCamera]), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            AdaptiveCameraLayout(aspectRatios: availableCameras.map { validAspectRatio(session.aspectRatios[$0]) }) {
                ForEach(availableCameras, id: \.self) { camera in
                    cameraTile(camera)
                }
            }
            .padding(6)
            .background(AppPalette.board, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppPalette.border, lineWidth: 1)
            }
        }
    }

    private var overviewGrid: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 10
            let count = availableCameras.count
            let tileAspect = availableCameras.map { validAspectRatio(session.aspectRatios[$0]) }.min() ?? 16 / 9
            let twoColumnRows = CGFloat(max(1, (count + 1) / 2))
            let threeColumnRows = CGFloat(max(1, (count + 2) / 3))
            let twoColumnWidth = min(
                (geometry.size.width - spacing) / 2,
                (geometry.size.height - (twoColumnRows - 1) * spacing) / twoColumnRows * tileAspect
            )
            let threeColumnWidth = min(
                (geometry.size.width - 2 * spacing) / 3,
                (geometry.size.height - (threeColumnRows - 1) * spacing) / threeColumnRows * tileAspect
            )
            let columnCount = count >= 3 && threeColumnWidth > twoColumnWidth ? 3 : 2
            let rowCount = max(1, (availableCameras.count + columnCount - 1) / columnCount)
            let widthLimited = (geometry.size.width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
            let heightLimited = (geometry.size.height - CGFloat(rowCount - 1) * spacing) / CGFloat(rowCount) * tileAspect
            let tileWidth = max(1, min(widthLimited, heightLimited))

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: columnCount),
                spacing: spacing
            ) {
                ForEach(availableCameras, id: \.self) { camera in
                    if let player = session.player(for: camera) {
                        CameraTile(
                            camera: camera,
                            player: player,
                            selected: camera == selectedCamera,
                            showsSelection: false,
                            prominent: false,
                            isEventCamera: camera == eventCamera,
                            isExporting: isExporting,
                            language: language,
                            onSelect: {
                                selectedCamera = camera
                                playbackLayout = .focus
                            },
                            onToggleFullScreen: {},
                            onExport: { onExport(camera, $0) }
                        )
                        .frame(
                            width: tileWidth,
                            height: tileWidth / validAspectRatio(session.aspectRatios[camera])
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppPalette.board, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppPalette.border, lineWidth: 1)
        }
        .accessibilityLabel(language.text("多视角同步总览", "Synchronized camera overview"))
    }

    private var spatialWorkspace: some View {
        SpatialCameraWorkspace(
            session: session,
            eventCamera: eventCamera,
            selectedCamera: $selectedCamera,
            playbackLayout: $playbackLayout,
            isExporting: isExporting,
            language: language,
            onExport: onExport
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cameraTile(_ camera: TeslaCamera) -> some View {
        if let player = session.player(for: camera) {
            CameraTile(
                camera: camera,
                player: player,
                selected: camera == selectedCamera,
                showsSelection: true,
                prominent: false,
                isEventCamera: false,
                isExporting: isExporting,
                language: language,
                onSelect: { selectedCamera = camera },
                onToggleFullScreen: {},
                onExport: { onExport(camera, $0) }
            )
        }
    }
}

private struct SpatialCameraWorkspace: View {
    let session: TeslaPlaybackSession
    let eventCamera: TeslaCamera?
    @Binding var selectedCamera: TeslaCamera
    @Binding var playbackLayout: PlaybackLayout
    let isExporting: Bool
    let language: AppLanguage
    let onExport: (TeslaCamera, TeslaExportMode) -> Void

    var body: some View {
        GeometryReader { geometry in
            let metrics = SpatialCameraMetrics(size: geometry.size, aspectRatios: session.aspectRatios)

            ZStack {
                ModelYTopDown()
                    .frame(width: metrics.carWidth, height: metrics.carHeight)
                    .position(metrics.center)
                    .accessibilityLabel(language.text("车辆摄像头拍摄方向示意图", "Vehicle camera viewing directions"))

                Canvas { context, _ in
                    for camera in TeslaCamera.allCases {
                        let directionColor = camera == eventCamera ? AppPalette.event : AppPalette.accent
                        let anchor = metrics.carAnchor(for: camera)
                        let direction = metrics.viewDirection(for: camera)
                        let length = metrics.directionLength(for: camera)
                        let perpendicular = CGVector(dx: -direction.dy, dy: direction.dx)
                        let isAvailable = session.player(for: camera) != nil
                        let end = CGPoint(
                            x: anchor.x + direction.dx * length,
                            y: anchor.y + direction.dy * length
                        )
                        let halfWidth: CGFloat = camera == .front || camera == .rear ? 8 : 11
                        var fieldOfView = Path()
                        fieldOfView.move(to: anchor)
                        fieldOfView.addLine(to: CGPoint(
                            x: end.x + perpendicular.dx * halfWidth,
                            y: end.y + perpendicular.dy * halfWidth
                        ))
                        fieldOfView.addLine(to: CGPoint(
                            x: end.x - perpendicular.dx * halfWidth,
                            y: end.y - perpendicular.dy * halfWidth
                        ))
                        fieldOfView.closeSubpath()
                        context.fill(
                            fieldOfView,
                            with: .color(directionColor.opacity(isAvailable ? (camera == eventCamera ? 0.16 : 0.075) : 0.02))
                        )
                        context.stroke(
                            fieldOfView,
                            with: .color(directionColor.opacity(isAvailable ? 0.25 : 0.04)),
                            lineWidth: 0.8
                        )
                    }

                    for camera in TeslaCamera.allCases {
                        let directionColor = camera == eventCamera ? AppPalette.event : AppPalette.accent
                        let isAvailable = session.player(for: camera) != nil
                        let anchor = metrics.carAnchor(for: camera)
                        let direction = metrics.viewDirection(for: camera)
                        let perpendicular = CGVector(dx: -direction.dy, dy: direction.dx)
                        let length = metrics.directionLength(for: camera)
                        let tip = CGPoint(
                            x: anchor.x + direction.dx * length,
                            y: anchor.y + direction.dy * length
                        )
                        let arrowBase = CGPoint(
                            x: tip.x - direction.dx * 8,
                            y: tip.y - direction.dy * 8
                        )
                        var arrow = Path()
                        arrow.move(to: anchor)
                        arrow.addLine(to: tip)
                        arrow.move(to: CGPoint(
                            x: arrowBase.x + perpendicular.dx * 5,
                            y: arrowBase.y + perpendicular.dy * 5
                        ))
                        arrow.addLine(to: tip)
                        arrow.addLine(to: CGPoint(
                            x: arrowBase.x - perpendicular.dx * 5,
                            y: arrowBase.y - perpendicular.dy * 5
                        ))
                        context.stroke(
                            arrow,
                            with: .color(directionColor.opacity(isAvailable ? 0.86 : 0.24)),
                            style: StrokeStyle(lineWidth: camera == eventCamera ? 2.4 : 1.7, lineCap: .round, lineJoin: .round)
                        )

                        let marker = Path(ellipseIn: CGRect(x: anchor.x - 4, y: anchor.y - 4, width: 8, height: 8))
                        context.fill(marker, with: .color(AppPalette.board))
                        context.stroke(
                            marker,
                            with: .color(directionColor.opacity(isAvailable ? 1 : 0.28)),
                            lineWidth: 2
                        )
                    }
                }
                .allowsHitTesting(false)

                ForEach(TeslaCamera.allCases, id: \.self) { camera in
                    spatialTile(for: camera)
                        .frame(width: metrics.tileWidth, height: metrics.tileHeight(for: camera))
                        .position(metrics.tileCenter(for: camera))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(AppPalette.board, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppPalette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private func spatialTile(for camera: TeslaCamera) -> some View {
        if let player = session.player(for: camera) {
            CameraTile(
                camera: camera,
                player: player,
                selected: camera == selectedCamera,
                showsSelection: false,
                prominent: false,
                isEventCamera: camera == eventCamera,
                isExporting: isExporting,
                language: language,
                onSelect: {
                    selectedCamera = camera
                    playbackLayout = .focus
                },
                onToggleFullScreen: {},
                onExport: { onExport(camera, $0) }
            )
        } else {
            VStack(spacing: 5) {
                Image(systemName: "video.slash").font(.title3)
                Text(camera.title(for: language)).font(.caption2.weight(.semibold))
                Text(language.text("无录像", "Not recorded")).font(.caption2)
            }
            .foregroundStyle(AppPalette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AppPalette.border, lineWidth: 1)
            }
            .accessibilityLabel(language.text("\(camera.title(for: language))无录像", "No recording from \(camera.title(for: language))"))
        }
    }
}

private struct SpatialCameraMetrics {
    private static let edgePadding: CGFloat = 6
    private static let spacing: CGFloat = 8
    let size: CGSize
    let tileWidth: CGFloat
    let carWidth: CGFloat
    let carHeight: CGFloat
    private let sideOffset: CGFloat
    private let aspectRatios: [TeslaCamera: CGFloat]

    init(size: CGSize, aspectRatios: [TeslaCamera: CGFloat]) {
        self.size = size
        self.aspectRatios = aspectRatios
        let smallestAspect = TeslaCamera.allCases.map { validAspectRatio(aspectRatios[$0]) }.min() ?? 16 / 9
        // Use the available width with compact gaps, leaving room for the car and its arrows.
        let widthLimit = (size.width - 2 * Self.edgePadding - 2 * Self.spacing) / 3
        let heightLimit = max(1, (size.height - 2 * Self.edgePadding) * 0.36 * smallestAspect)
        tileWidth = max(1, min(widthLimit, heightLimit))
        let tallestTile = tileWidth / smallestAspect
        carHeight = max(1, min(size.height * 0.26, size.height - 2 * tallestTile - 2 * Self.edgePadding - 36))
        carWidth = carHeight * 0.54
        sideOffset = tileWidth + Self.spacing
    }

    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    func tileHeight(for camera: TeslaCamera) -> CGFloat {
        let aspectRatio = validAspectRatio(aspectRatios[camera])
        return tileWidth / aspectRatio
    }

    func tileCenter(for camera: TeslaCamera) -> CGPoint {
        // Place feeds by mounting position; the arrows separately show viewing direction.
        // Repeaters sit on the front fenders, ahead of the door-pillar cameras.
        switch camera {
        case .front: return CGPoint(x: center.x, y: tileHeight(for: .front) / 2 + Self.edgePadding)
        case .rear: return CGPoint(x: center.x, y: size.height - tileHeight(for: .rear) / 2 - Self.edgePadding)
        case .leftRepeater: return CGPoint(x: center.x - sideOffset, y: center.y - (tileHeight(for: .leftPillar) + Self.spacing) / 2)
        case .rightRepeater: return CGPoint(x: center.x + sideOffset, y: center.y - (tileHeight(for: .rightPillar) + Self.spacing) / 2)
        case .leftPillar: return CGPoint(x: center.x - sideOffset, y: center.y + (tileHeight(for: .leftRepeater) + Self.spacing) / 2)
        case .rightPillar: return CGPoint(x: center.x + sideOffset, y: center.y + (tileHeight(for: .rightRepeater) + Self.spacing) / 2)
        }
    }

    func carAnchor(for camera: TeslaCamera) -> CGPoint {
        switch camera {
        case .front: return CGPoint(x: center.x, y: center.y - carHeight / 2 + 5)
        case .rear: return CGPoint(x: center.x, y: center.y + carHeight / 2 - 5)
        case .leftRepeater: return CGPoint(x: center.x - carWidth * 0.36, y: center.y - carHeight * 0.20)
        case .rightRepeater: return CGPoint(x: center.x + carWidth * 0.36, y: center.y - carHeight * 0.20)
        case .leftPillar: return CGPoint(x: center.x - carWidth * 0.39, y: center.y + carHeight * 0.07)
        case .rightPillar: return CGPoint(x: center.x + carWidth * 0.39, y: center.y + carHeight * 0.07)
        }
    }

    func viewDirection(for camera: TeslaCamera) -> CGVector {
        switch camera {
        case .front: return CGVector(dx: 0, dy: -1)
        case .rear: return CGVector(dx: 0, dy: 1)
        case .leftRepeater: return CGVector(dx: -0.87, dy: 0.49)
        case .rightRepeater: return CGVector(dx: 0.87, dy: 0.49)
        case .leftPillar: return CGVector(dx: -0.94, dy: -0.34)
        case .rightPillar: return CGVector(dx: 0.94, dy: -0.34)
        }
    }

    func directionLength(for camera: TeslaCamera) -> CGFloat {
        if camera == .front || camera == .rear {
            let tileHeight = tileHeight(for: camera)
            return min(24, max(11, (size.height - carHeight) / 2 - tileHeight + 8))
        }
        return 36
    }
}

// Original vector; proportions reference Tesla's Model Y Owner's Manual camera-location diagram.
private struct ModelYTopDown: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let outline = silhouette(in: size)

            ZStack {
                wheel(in: size, left: true, front: true)
                    .fill(Color(red: 0.29, green: 0.29, blue: 0.30))
                wheel(in: size, left: false, front: true)
                    .fill(Color(red: 0.29, green: 0.29, blue: 0.30))
                wheel(in: size, left: true, front: false)
                    .fill(Color(red: 0.29, green: 0.29, blue: 0.30))
                wheel(in: size, left: false, front: false)
                    .fill(Color(red: 0.29, green: 0.29, blue: 0.30))

                outline.fill(Color(red: 0.83, green: 0.83, blue: 0.84))
                outline.stroke(Color(red: 0.37, green: 0.37, blue: 0.39), lineWidth: 1.3)

                mirror(in: size, left: true)
                    .fill(Color(red: 0.58, green: 0.58, blue: 0.60))
                mirror(in: size, left: false)
                    .fill(Color(red: 0.58, green: 0.58, blue: 0.60))

                hoodSeam(in: size)
                    .stroke(AppPalette.textSecondary.opacity(0.36), lineWidth: 1)
                rearSeam(in: size)
                    .stroke(AppPalette.textSecondary.opacity(0.31), lineWidth: 1)

                headlight(in: size, left: true)
                    .stroke(AppPalette.textSecondary.opacity(0.72), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                headlight(in: size, left: false)
                    .stroke(AppPalette.textSecondary.opacity(0.72), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

                canopy(in: size)
                    .fill(Color(red: 0.68, green: 0.68, blue: 0.70))
                canopy(in: size)
                    .stroke(AppPalette.textSecondary.opacity(0.48), lineWidth: 1)

                windshield(in: size)
                    .fill(Color(red: 0.74, green: 0.74, blue: 0.76))
                roofGlass(in: size)
                    .fill(Color(red: 0.46, green: 0.46, blue: 0.48))
                rearGlass(in: size)
                    .fill(Color(red: 0.66, green: 0.66, blue: 0.68))

                glassDivider(in: size, y: 0.40)
                    .stroke(AppPalette.textPrimary.opacity(0.40), lineWidth: 1)
                glassDivider(in: size, y: 0.76)
                    .stroke(AppPalette.textPrimary.opacity(0.34), lineWidth: 0.9)

                sideHighlight(in: size, left: true)
                    .stroke(Color.white.opacity(0.78), lineWidth: 0.8)
                sideHighlight(in: size, left: false)
                    .stroke(Color.white.opacity(0.78), lineWidth: 0.8)
            }
        }
    }

    private func silhouette(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.37, y: h * 0.025))
        path.addQuadCurve(to: CGPoint(x: w * 0.63, y: h * 0.025), control: CGPoint(x: w * 0.5, y: h * 0.005))
        path.addCurve(to: CGPoint(x: w * 0.82, y: h * 0.20), control1: CGPoint(x: w * 0.76, y: h * 0.035), control2: CGPoint(x: w * 0.81, y: h * 0.10))
        path.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.34), control1: CGPoint(x: w * 0.84, y: h * 0.24), control2: CGPoint(x: w * 0.86, y: h * 0.29))
        path.addCurve(to: CGPoint(x: w * 0.82, y: h * 0.47), control1: CGPoint(x: w * 0.86, y: h * 0.39), control2: CGPoint(x: w * 0.83, y: h * 0.42))
        path.addCurve(to: CGPoint(x: w * 0.84, y: h * 0.76), control1: CGPoint(x: w * 0.81, y: h * 0.58), control2: CGPoint(x: w * 0.84, y: h * 0.69))
        path.addCurve(to: CGPoint(x: w * 0.73, y: h * 0.95), control1: CGPoint(x: w * 0.84, y: h * 0.85), control2: CGPoint(x: w * 0.79, y: h * 0.93))
        path.addQuadCurve(to: CGPoint(x: w * 0.27, y: h * 0.95), control: CGPoint(x: w * 0.5, y: h * 0.99))
        path.addCurve(to: CGPoint(x: w * 0.16, y: h * 0.76), control1: CGPoint(x: w * 0.21, y: h * 0.93), control2: CGPoint(x: w * 0.16, y: h * 0.85))
        path.addCurve(to: CGPoint(x: w * 0.18, y: h * 0.47), control1: CGPoint(x: w * 0.16, y: h * 0.69), control2: CGPoint(x: w * 0.19, y: h * 0.58))
        path.addCurve(to: CGPoint(x: w * 0.14, y: h * 0.34), control1: CGPoint(x: w * 0.17, y: h * 0.42), control2: CGPoint(x: w * 0.14, y: h * 0.39))
        path.addCurve(to: CGPoint(x: w * 0.18, y: h * 0.20), control1: CGPoint(x: w * 0.14, y: h * 0.29), control2: CGPoint(x: w * 0.16, y: h * 0.24))
        path.addCurve(to: CGPoint(x: w * 0.37, y: h * 0.025), control1: CGPoint(x: w * 0.19, y: h * 0.10), control2: CGPoint(x: w * 0.24, y: h * 0.035))
        path.closeSubpath()
        return path
    }

    private func wheel(in size: CGSize, left: Bool, front: Bool) -> Path {
        Path(roundedRect: CGRect(
            x: size.width * (left ? 0.09 : 0.80),
            y: size.height * (front ? 0.25 : 0.70),
            width: size.width * 0.11,
            height: size.height * 0.14
        ), cornerRadius: size.width * 0.025)
    }

    private func canopy(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.29, y: h * 0.25))
        path.addQuadCurve(to: CGPoint(x: w * 0.71, y: h * 0.25), control: CGPoint(x: w * 0.5, y: h * 0.235))
        path.addCurve(to: CGPoint(x: w * 0.78, y: h * 0.45), control1: CGPoint(x: w * 0.76, y: h * 0.31), control2: CGPoint(x: w * 0.78, y: h * 0.39))
        path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.78))
        path.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.88), control: CGPoint(x: w * 0.73, y: h * 0.85))
        path.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.88), control: CGPoint(x: w * 0.5, y: h * 0.91))
        path.addQuadCurve(to: CGPoint(x: w * 0.26, y: h * 0.78), control: CGPoint(x: w * 0.27, y: h * 0.85))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.45))
        path.addCurve(to: CGPoint(x: w * 0.29, y: h * 0.25), control1: CGPoint(x: w * 0.22, y: h * 0.39), control2: CGPoint(x: w * 0.24, y: h * 0.31))
        path.closeSubpath()
        return path
    }

    private func hoodSeam(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.22, y: h * 0.22))
        path.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.22), control: CGPoint(x: w * 0.5, y: h * 0.19))
        return path
    }

    private func rearSeam(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.28, y: h * 0.91))
        path.addQuadCurve(to: CGPoint(x: w * 0.72, y: h * 0.91), control: CGPoint(x: w * 0.5, y: h * 0.93))
        return path
    }

    private func glassDivider(in size: CGSize, y: CGFloat) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        let inset = y < 0.5 ? 0.23 : 0.26
        path.move(to: CGPoint(x: w * inset, y: h * y))
        path.addLine(to: CGPoint(x: w * (1 - inset), y: h * y))
        return path
    }

    private func windshield(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.29, y: h * 0.26))
        path.addLine(to: CGPoint(x: w * 0.71, y: h * 0.26))
        path.addLine(to: CGPoint(x: w * 0.77, y: h * 0.395))
        path.addLine(to: CGPoint(x: w * 0.23, y: h * 0.395))
        path.closeSubpath()
        return path
    }

    private func roofGlass(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.235, y: h * 0.41))
        path.addLine(to: CGPoint(x: w * 0.765, y: h * 0.41))
        path.addLine(to: CGPoint(x: w * 0.745, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.255, y: h * 0.75))
        path.closeSubpath()
        return path
    }

    private func rearGlass(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.26, y: h * 0.765))
        path.addLine(to: CGPoint(x: w * 0.74, y: h * 0.765))
        path.addLine(to: CGPoint(x: w * 0.66, y: h * 0.87))
        path.addLine(to: CGPoint(x: w * 0.34, y: h * 0.87))
        path.closeSubpath()
        return path
    }

    private func headlight(in size: CGSize, left: Bool) -> Path {
        let w = size.width
        let h = size.height
        let sign: CGFloat = left ? -1 : 1
        var path = Path()
        path.move(to: CGPoint(x: w * (0.5 + sign * 0.25), y: h * 0.14))
        path.addQuadCurve(
            to: CGPoint(x: w * (0.5 + sign * 0.36), y: h * 0.19),
            control: CGPoint(x: w * (0.5 + sign * 0.34), y: h * 0.14)
        )
        return path
    }

    private func mirror(in size: CGSize, left: Bool) -> Path {
        let w = size.width
        let h = size.height
        var path = Path()
        let sign: CGFloat = left ? -1 : 1
        path.move(to: CGPoint(x: w * (0.5 + sign * 0.32), y: h * 0.31))
        path.addLine(to: CGPoint(x: w * (0.5 + sign * 0.43), y: h * 0.35))
        path.addQuadCurve(to: CGPoint(x: w * (0.5 + sign * 0.37), y: h * 0.37), control: CGPoint(x: w * (0.5 + sign * 0.44), y: h * 0.38))
        path.closeSubpath()
        return path
    }

    private func sideHighlight(in size: CGSize, left: Bool) -> Path {
        let w = size.width
        let h = size.height
        let x: CGFloat = left ? 0.19 : 0.81
        var path = Path()
        path.move(to: CGPoint(x: w * x, y: h * 0.39))
        path.addLine(to: CGPoint(x: w * x, y: h * 0.76))
        return path
    }
}

private struct AdaptiveCameraLayout: Layout {
    let aspectRatios: [CGFloat]
    private let spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let proposedWidth = proposal.width ?? CGFloat(subviews.count) * 130
        let width = proposedWidth.isFinite ? max(1, proposedWidth) : CGFloat(subviews.count) * 130
        let columns = subviews.count
        let cardWidth = min(160, max(1, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)))
        let heights = rowHeights(count: subviews.count, columns: columns, cardWidth: cardWidth)
        return CGSize(width: width, height: heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let columns = subviews.count
        let cardWidth = min(160, max(1, (bounds.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)))
        let heights = rowHeights(count: subviews.count, columns: columns, cardWidth: cardWidth)
        var rowY = bounds.minY
        for (row, rowHeight) in heights.enumerated() {
            for column in 0..<columns {
                let index = row * columns + column
                guard index < subviews.count else { break }
                let cardHeight = cardWidth / validAspectRatio(aspectRatios.indices.contains(index) ? aspectRatios[index] : nil)
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(column) * (cardWidth + spacing),
                        y: rowY + (rowHeight - cardHeight) / 2
                    ),
                    proposal: ProposedViewSize(width: cardWidth, height: cardHeight)
                )
            }
            rowY += rowHeight + spacing
        }
    }

    private func rowHeights(count: Int, columns: Int, cardWidth: CGFloat) -> [CGFloat] {
        let rows = (count + columns - 1) / columns
        return (0..<rows).map { row in
            (row * columns..<min(count, (row + 1) * columns))
                .map { cardWidth / validAspectRatio(aspectRatios.indices.contains($0) ? aspectRatios[$0] : nil) }
                .max() ?? 0
        }
    }
}

private struct CameraTile: View {
    let camera: TeslaCamera
    let player: AVPlayer
    let selected: Bool
    let showsSelection: Bool
    let prominent: Bool
    let isEventCamera: Bool
    let isExporting: Bool
    let language: AppLanguage
    let onSelect: () -> Void
    let onToggleFullScreen: () -> Void
    let onExport: (TeslaExportMode) -> Void
    @State private var isHovering = false
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @GestureState private var liveMagnification = LiveMagnification()
    @GestureState private var liveDrag: CGSize = .zero

    private struct LiveMagnification {
        var scale: CGFloat = 1
        var anchor: UnitPoint = .center
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = clampedScale(zoomScale * liveMagnification.scale)
            let offset = clampedOffset(
                magnifiedOffset(
                    from: zoomOffset,
                    oldScale: zoomScale,
                    newScale: scale,
                    anchor: liveMagnification.anchor,
                    viewport: geometry.size
                ) + liveDrag,
                scale: scale,
                viewport: geometry.size
            )

            ZStack(alignment: .topLeading) {
                MacVideoPlayer(player: player)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color.black)
                    .scaleEffect(prominent ? scale : 1)
                    .offset(prominent ? offset : .zero)
                LinearGradient(
                    colors: [.black.opacity(prominent ? 0.48 : 0.62), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .allowsHitTesting(false)

                HStack(spacing: 6) {
                    Image(systemName: camera.systemImage)
                    Text(camera.title(for: language))
                }
                .font(prominent ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(prominent ? 12 : 7)
                .allowsHitTesting(false)

                if !prominent, selected, showsSelection {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 19, height: 19)
                        .background(AppPalette.accent, in: Circle())
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .topTrailing).allowsHitTesting(false)
                }

                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture(count: 2) { if prominent { onToggleFullScreen() } }
                    .onTapGesture { onSelect() }
                    .simultaneousGesture(
                        magnifyGesture(in: geometry.size), including: prominent ? .all : .none
                    )
                    .simultaneousGesture(panGesture(in: geometry.size), including: prominent ? .all : .none)
                    .contextMenu {
                        if !prominent && !(selected && showsSelection) {
                            Button {
                                onSelect()
                            } label: {
                                Label(language.text("设为主画面", "Make Primary"), systemImage: "rectangle.inset.filled")
                            }
                            Divider()
                        }
                        Button {
                            onExport(.aroundCurrent(radius: 30))
                        } label: {
                            Label(language.text("导出当前位置前后 30 秒…", "Export ±30 Seconds…"), systemImage: "scissors")
                        }
                        .disabled(isExporting)
                        Button {
                            onExport(.full)
                        } label: {
                            Label(
                                language.text("导出完整当前视角…", "Export Full Camera…"),
                                systemImage: "square.and.arrow.up")
                        }
                        .disabled(isExporting)
                        if prominent {
                            Divider()
                            Button {
                                setZoom(zoomScale * 1.5, in: geometry.size)
                            } label: {
                                Label(language.text("放大画面", "Zoom In"), systemImage: "plus.magnifyingglass")
                            }
                            .disabled(zoomScale >= 4)
                            Button {
                                setZoom(zoomScale / 1.5, in: geometry.size)
                            } label: {
                                Label(language.text("缩小画面", "Zoom Out"), systemImage: "minus.magnifyingglass")
                            }
                            .disabled(zoomScale <= 1)
                            Button {
                                resetZoom()
                            } label: {
                                Label(language.text("重置缩放", "Reset Zoom"), systemImage: "arrow.counterclockwise")
                            }
                            .disabled(zoomScale <= 1)
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: prominent ? 9 : 8, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if isEventCamera {
                    Label(language.text("事件镜头", "Event camera"), systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppPalette.eventOnVideo)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 4))
                        .padding(7)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: prominent ? 9 : 8, style: .continuous)
                    .stroke(
                        isEventCamera
                            ? AppPalette.eventOnVideo
                            : selected && showsSelection
                                ? AppPalette.accent.opacity(prominent ? 0.38 : 0.9)
                                : Color.white.opacity(isHovering ? 0.3 : 0.07),
                        lineWidth: isEventCamera ? 2 : selected && showsSelection ? 1.5 : 1
                    )
            }
            .onHover { isHovering = $0 }
            .help(
                prominent
                    ? language.text(
                        "双指缩放，拖动查看细节；双击全屏，右键导出",
                        "Pinch to zoom, drag to inspect; double-click for full screen; right-click to export")
                    : language.text("单击切换主视角，右键导出", "Click to make primary; right-click to export")
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                isEventCamera
                    ? language.text(
                        "\(camera.title(for: language))，事件镜头", "\(camera.title(for: language)), event camera")
                    : camera.title(for: language)
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(
                prominent
                    ? language.text(
                        "双指缩放，拖动查看细节；双击打开全屏播放",
                        "Pinch to zoom, drag to inspect; double-click for full-screen playback")
                    : language.text("设为主画面", "Make primary view")
            )
            .accessibilityAction { if prominent { onToggleFullScreen() } else { onSelect() } }
            .overlay(alignment: .bottomTrailing) {
                if prominent && scale > 1.01 {
                    Button(action: resetZoom) {
                        Label(String(format: "%.1f×", Double(scale)), systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .help(language.text("重置画面缩放", "Reset video zoom"))
                    .padding(12)
                }
            }
        }
    }

    private func magnifyGesture(in viewport: CGSize) -> some Gesture {
        MagnifyGesture()
            .updating($liveMagnification) { value, state, _ in
                state.scale = value.magnification
                state.anchor = value.startAnchor
            }
            .onEnded { value in
                let nextScale = clampedScale(zoomScale * value.magnification)
                zoomOffset = clampedOffset(
                    magnifiedOffset(
                        from: zoomOffset,
                        oldScale: zoomScale,
                        newScale: nextScale,
                        anchor: value.startAnchor,
                        viewport: viewport
                    ),
                    scale: nextScale,
                    viewport: viewport
                )
                zoomScale = nextScale
            }
    }

    private func panGesture(in viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($liveDrag) { value, state, _ in
                if zoomScale > 1 { state = value.translation }
            }
            .onEnded { value in
                guard zoomScale > 1 else { return }
                zoomOffset = clampedOffset(zoomOffset + value.translation, scale: zoomScale, viewport: viewport)
            }
    }

    private func setZoom(_ value: CGFloat, in viewport: CGSize) {
        let nextScale = clampedScale(value)
        zoomOffset = clampedOffset(zoomOffset, scale: nextScale, viewport: viewport)
        zoomScale = nextScale
    }

    private func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
    }

    private func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(4, max(1, scale))
    }

    private func magnifiedOffset(from offset: CGSize, oldScale: CGFloat, newScale: CGFloat, anchor: UnitPoint, viewport: CGSize) -> CGSize {
        let ratio = newScale / oldScale
        return CGSize(
            width: offset.width * ratio + (anchor.x - 0.5) * viewport.width * (1 - ratio),
            height: offset.height * ratio + (anchor.y - 0.5) * viewport.height * (1 - ratio)
        )
    }

    private func clampedOffset(_ offset: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        let maxX = viewport.width * (scale - 1) / 2
        let maxY = viewport.height * (scale - 1) / 2
        return CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height))
        )
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

private struct ControlDeck<RecordingActions: View>: View {
    @ObservedObject var viewModel: TeslaCamViewModel
    let session: TeslaPlaybackSession
    let language: AppLanguage
    @Binding var playbackLayout: PlaybackLayout
    let recordingActions: RecordingActions

    var body: some View {
        VStack(spacing: 5) {
            if viewModel.trimSelection != nil {
                TrimControls(viewModel: viewModel, language: language)
            }
            HStack(spacing: 10) {
                if let clip = viewModel.activeClip {
                    Text(clip.displayTitle)
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(AppPalette.textPrimary)
                        .fixedSize()
                    Rectangle().fill(AppPalette.border).frame(width: 1, height: 14)
                }
                Text(viewModel.timeText(viewModel.safeCurrentTime))
                    .foregroundStyle(AppPalette.textPrimary)
                    .fixedSize()
                EventTimeline(
                    language: language,
                    value: Binding(
                        get: { viewModel.safeCurrentTime },
                        set: { viewModel.updateScrubbing(to: $0) }
                    ),
                    maximumValue: max(viewModel.safeDuration, 0.1),
                    eventMarker: viewModel.eventMarkerTime,
                    segmentMarkers: session.segmentMarkers,
                    trimSelection: viewModel.trimSelection,
                    onTrimBoundary: { viewModel.setTrimBoundary($0, isStart: $1) },
                    onEditingChanged: { editing in
                        if editing { viewModel.beginScrubbing() } else { viewModel.endScrubbing() }
                    }
                )
                Text("−\(viewModel.timeText(max(0, viewModel.safeDuration - viewModel.safeCurrentTime)))")
                    .foregroundStyle(AppPalette.textSecondary)
                    .fixedSize()
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    transportControls
                    PlaybackSpeedControl(viewModel: viewModel, language: language)
                    Spacer(minLength: 8)
                    layoutPicker
                    Spacer(minLength: 8)
                    playbackOptions
                    recordingActions
                }
                VStack(spacing: 5) {
                    HStack(spacing: 8) {
                        transportControls
                        PlaybackSpeedControl(viewModel: viewModel, language: language)
                        Spacer(minLength: 8)
                        playbackOptions
                    }
                    HStack {
                        layoutPicker
                        Spacer(minLength: 8)
                        recordingActions
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppPalette.board, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AppPalette.border, lineWidth: 0.5) }
    }

    private var layoutPicker: some View {
        PlaybackLayoutPicker(playbackLayout: $playbackLayout, language: language,
                             hasMultipleCameras: session.players.count > 1)
            .fixedSize()
    }

    private var transportControls: some View {
        Button { viewModel.togglePlayPause() } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold)).offset(x: viewModel.isPlaying ? 0 : 1)
                .frame(width: 21, height: 18)
        }
        .buttonStyle(PlayButtonStyle()).keyboardShortcut(.space, modifiers: [])
        .help(viewModel.isPlaying ? language.text("暂停播放", "Pause playback") : language.text("播放录像", "Play recording"))
        .accessibilityLabel(viewModel.isPlaying ? language.text("暂停", "Pause") : language.text("播放", "Play"))
        .fixedSize()
    }

    private var playbackOptions: some View {
        HStack(spacing: 6) {
            PictureAdjustmentControls(adjustments: $viewModel.videoAdjustments, language: language)
                .buttonStyle(HeaderButtonStyle())
            if viewModel.trimSelection == nil {
                Button { viewModel.beginTrimming() } label: {
                    Label(language.text("截取", "Trim"), systemImage: "scissors")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(viewModel.isExporting || viewModel.isDeleting)
                .help(language.text("选择所有机位要保留的时间段", "Choose the time range to keep for all cameras"))
            }
        }
        .fixedSize()
    }
}

private struct PlaybackSpeedControl: View {
    @ObservedObject var viewModel: TeslaCamViewModel
    let language: AppLanguage
    @State private var isPresented = false
    private let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2, 4, 8]

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "speedometer").font(.system(size: 14, weight: .medium))
                Text(rateText(viewModel.playbackRate)).font(.system(size: 15, weight: .semibold).monospacedDigit())
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .frame(width: 82, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .help(language.text("播放速度", "Playback speed"))
        .accessibilityLabel(language.text("播放速度", "Playback speed"))
        .accessibilityValue(rateText(viewModel.playbackRate))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("播放速度", "Playback speed"))
                    .font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(rates, id: \.self) { rate in
                        Toggle(isOn: Binding(get: { viewModel.playbackRate == rate }, set: { selected in
                            if selected {
                                viewModel.setPlaybackRate(rate)
                                isPresented = false
                            }
                        })) {
                            Text(rateText(rate))
                                .font(.system(size: 14, weight: .medium).monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 20)
                        }
                        .toggleStyle(.button)
                        .controlSize(.large)
                        .accessibilityAddTraits(viewModel.playbackRate == rate ? .isSelected : [])
                    }
                }
            }
            .foregroundStyle(AppPalette.textPrimary)
            .padding(14)
            .frame(width: 290)
            .background(AppPalette.surface)
            .preferredColorScheme(.light)
        }
    }

    private func rateText(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(String(format: "%.3g", rate))×"
    }
}

private struct PictureAdjustmentControls: View {
    @Binding var adjustments: VideoAdjustments
    let language: AppLanguage

    var body: some View {
        PictureAdjustmentButton(
            value: $adjustments.brightness,
            title: language.text("亮度", "Brightness"),
            symbol: "sun.max",
            range: -0.5...0.5,
            defaultValue: 0,
            displayValue: String(format: "%+.0f", adjustments.brightness * 100),
            language: language
        )
        PictureAdjustmentButton(
            value: $adjustments.contrast,
            title: language.text("对比度", "Contrast"),
            symbol: "circle.lefthalf.filled",
            range: 0.5...2,
            defaultValue: 1,
            displayValue: String(format: "%.0f%%", adjustments.contrast * 100),
            language: language
        )
    }
}

private struct PictureAdjustmentButton: View {
    @Binding var value: Double
    let title: String
    let symbol: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    let displayValue: String
    let language: AppLanguage
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: symbol)
                .overlay(alignment: .bottomTrailing) {
                    if value != defaultValue {
                        Circle().fill(AppPalette.accent).frame(width: 4, height: 4).offset(x: 4, y: 3)
                    }
                }
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(displayValue)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(spacing: 12) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(displayValue).font(.system(size: 12, weight: .medium).monospacedDigit())
                }
                Slider(value: $value, in: range, step: 0.01)
                    .tint(AppPalette.accent)
                    .accessibilityLabel(title)
                    .accessibilityValue(displayValue)
                HStack {
                    Spacer()
                    Button(language.text("恢复默认", "Reset")) { value = defaultValue }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(value == defaultValue)
                }
            }
            .foregroundStyle(AppPalette.textPrimary)
            .padding(14)
            .frame(width: 240)
            .background(AppPalette.surface)
            .preferredColorScheme(.light)
        }
    }
}

private struct TrimControls: View {
    @ObservedObject var viewModel: TeslaCamViewModel
    let language: AppLanguage

    var body: some View {
        if let selection = viewModel.trimSelection {
            HStack(spacing: 8) {
                Button { viewModel.setTrimBoundary(viewModel.safeCurrentTime, isStart: true) } label: {
                    Text(language.text("起点", "Start") + " " + viewModel.timeText(selection.start))
                }
                .help(language.text("将当前位置设为起点", "Set start at the playhead"))
                Button { viewModel.setTrimBoundary(viewModel.safeCurrentTime, isStart: false) } label: {
                    Text(language.text("终点", "End") + " " + viewModel.timeText(selection.end))
                }
                .help(language.text("将当前位置设为终点", "Set end at the playhead"))
                Text(viewModel.timeText(selection.duration))
                    .foregroundStyle(AppPalette.accent)
                    .accessibilityLabel(language.text("保留时长", "Kept duration"))
                Spacer(minLength: 0)
                Button { viewModel.requestTrimConfirmation() } label: {
                    Label(language.text("截取并替换", "Trim & Replace"), systemImage: "scissors")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canApplyTrim)
                Button { viewModel.endTrimming() } label: { Image(systemName: "xmark") }
                    .help(language.text("退出截取", "Exit trim"))
                    .accessibilityLabel(language.text("退出截取", "Exit trim"))
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(AppPalette.textPrimary)
            .buttonStyle(QuietButtonStyle())

        }
    }
}

private struct EventTimeline: View {
    let language: AppLanguage
    @Binding var value: Double
    let maximumValue: Double
    let eventMarker: Double?
    let segmentMarkers: [Double]
    var trimSelection: TeslaTrimSelection? = nil
    var onTrimBoundary: ((Double, Bool) -> Void)? = nil
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            if let selection = trimSelection {
                GeometryReader { geometry in
                    let width = max(0, geometry.size.width - 18)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppPalette.accent.opacity(0.22))
                        .overlay { RoundedRectangle(cornerRadius: 4).stroke(AppPalette.accent, lineWidth: 1) }
                        .frame(width: width * selection.duration / maximumValue, height: 24)
                        .position(x: 9 + width * (selection.start + selection.end) / (2 * maximumValue), y: geometry.size.height / 2)
                }
                .allowsHitTesting(false)
            }
            Slider(value: $value, in: 0...maximumValue, onEditingChanged: onEditingChanged)
                .tint(AppPalette.accent)
                .accessibilityLabel(language.text("录像时间轴", "Recording timeline"))
            GeometryReader { geometry in
                let usableWidth = max(0, geometry.size.width - 18)
                ForEach(Array(segmentMarkers.enumerated()), id: \.offset) { _, marker in
                    if marker.isFinite, marker > 0, marker < maximumValue {
                        let x = 9 + usableWidth * min(1, max(0, marker / maximumValue))
                        Capsule().fill(AppPalette.textTertiary.opacity(0.85)).frame(width: 2, height: 8)
                            .position(x: x, y: geometry.size.height / 2)
                    }
                }
                if let eventMarker, eventMarker.isFinite, maximumValue.isFinite, maximumValue > 0 {
                    let x = 9 + usableWidth * min(1, max(0, eventMarker / maximumValue))
                    VStack(spacing: 0) {
                        Image(systemName: "triangle.fill").font(.system(size: 7))
                        Capsule().frame(width: 3, height: 12)
                    }
                    .foregroundStyle(AppPalette.event).position(x: x, y: geometry.size.height / 2 - 1)
                }
            }
            .allowsHitTesting(false)
            if let selection = trimSelection {
                GeometryReader { geometry in
                    let width = max(1, geometry.size.width - 18)
                    trimHandle(seconds: selection.start, isStart: true, width: width)
                        .position(x: 9 + width * selection.start / maximumValue, y: geometry.size.height / 2)
                    trimHandle(seconds: selection.end, isStart: false, width: width)
                        .position(x: 9 + width * selection.end / maximumValue, y: geometry.size.height / 2)
                }
            }
        }
        .coordinateSpace(name: "trimTimeline")
        .frame(height: trimSelection == nil ? 22 : 30)
    }

    private func trimHandle(seconds: Double, isStart: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(AppPalette.accent)
            .frame(width: 14, height: 28)
            .overlay { Capsule().fill(.white).frame(width: 2, height: 13) }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trimTimeline"))
                .onChanged { gesture in
                    onTrimBoundary?((gesture.location.x - 9) / width * maximumValue, isStart)
                })
            .accessibilityElement()
            .accessibilityLabel(isStart ? language.text("截取起点", "Trim start") : language.text("截取终点", "Trim end"))
            .accessibilityValue(String(format: "%.0f", seconds))
            .accessibilityAdjustableAction { direction in
                onTrimBoundary?(seconds + (direction == .increment ? 1 : -1), isStart)
            }
    }
}

private struct BrowserEmptyView: View {
    let language: AppLanguage
    let category: TeslaClipCategory
    let hasDrive: Bool
    let isSearching: Bool
    let suggestedCategory: TeslaClipCategory?
    let onClearSearch: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: isSearching ? "magnifyingglass" : (hasDrive ? "video.slash" : "externaldrive.badge.questionmark"))
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(AppPalette.textSecondary)
                .frame(width: 64, height: 64)
                .background(AppPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(AppPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if isSearching {
                Button(language.text("清除搜索", "Clear Search"), action: onClearSearch)
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 3)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if isSearching { return language.text("没有匹配的录像", "No matching recordings") }
        if !hasDrive { return language.text("连接录像来源", "Connect a recording source") }
        return language.text("此分类暂无录像", "No recordings in \(category.title(for: language))")
    }

    private var detail: String {
        if isSearching { return language.text("试试其他日期、地点或事件关键词。", "Try a different date, location, or event keyword.") }
        if !hasDrive { return language.text("插入 TeslaCam U 盘，或选择本地 TeslaCam 文件夹。", "Insert a TeslaCam USB drive or choose a local TeslaCam folder.") }
        if let suggestedCategory {
            return language.text("\(suggestedCategory.title(for: language))中有录像可查看。", "Recordings are available in \(suggestedCategory.title(for: language)).")
        }
        return language.text("当前来源没有可播放录像，请检查文件夹。", "No playable recordings were found in this source.")
    }

}

private struct LoadingStateView: View {
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 13) {
            ProgressView().controlSize(.large).tint(AppPalette.accent)
            Text(language.text("正在载入录像", "Loading recordings")).font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlayerLoadingView: View {
    let clip: TeslaClip?
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle().stroke(AppPalette.border, lineWidth: 6)
                ProgressView().controlSize(.large).tint(AppPalette.accent)
            }
            .frame(width: 64, height: 64)
            Text(language.text("正在载入视频", "Loading video")).font(.headline)
            if let clip {
                Text(clip.displayTitle)
                    .font(.caption.monospacedDigit()).foregroundStyle(AppPalette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlayerEmptyView: View {
    let language: AppLanguage
    let hasDrive: Bool
    let suggestedCategory: TeslaClipCategory?
    let errorMessage: String?
    let needsAccess: Bool
    let onChooseFolder: () -> Void
    let onSelectCategory: (TeslaClipCategory) -> Void
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(AppPalette.surface)
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 32)).foregroundStyle(AppPalette.textSecondary)
            }
            .frame(width: 82, height: 72)
            Text(title)
                .font(.title3.weight(.bold))
            if suggestedCategory == nil {
                Text(detail)
                    .font(.subheadline).foregroundStyle(AppPalette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button {
                if let suggestedCategory {
                    onSelectCategory(suggestedCategory)
                } else {
                    onChooseFolder()
                }
            } label: {
                Text(actionTitle)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .buttonStyle(PrimaryButtonStyle())
            Link(AppUpdater.repositoryURL.absoluteString, destination: AppUpdater.repositoryURL)
                .font(.callout)
                .foregroundStyle(AppPalette.accent)
                .help(language.text("打开 RoadReel 开源项目", "Open the RoadReel repository"))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if errorMessage != nil {
            return needsAccess ? language.text("允许访问录像", "Allow access to recordings") : language.text("无法读取录像", "Could not read recordings")
        }
        if suggestedCategory != nil {
            return language.text("选择一段录像", "Choose a recording")
        }
        return hasDrive
            ? language.text("此来源暂无录像", "No recordings in this source")
            : language.text("打开 TeslaCam 录像", "Open your TeslaCam recordings")
    }

    private var detail: String {
        if let errorMessage { return errorMessage }
        return hasDrive
            ? language.text("请选择其他 TeslaCam 文件夹，或检查当前来源。", "Choose another TeslaCam folder or check the current source.")
            : language.text("连接 U 盘，或选择 Mac 上的 TeslaCam 文件夹。", "Connect a USB drive or choose a TeslaCam folder on your Mac.")
    }

    private var actionTitle: String {
        if needsAccess { return language.text("允许访问 TeslaCam…", "Allow TeslaCam Access…") }
        if let suggestedCategory { return language.text("查看\(suggestedCategory.title(for: language))", "View \(suggestedCategory.title(for: language))") }
        return language.text("选择 TeslaCam 目录…", "Choose TeslaCam Folder…")
    }
}

// Delegate bezels, focus, pressed and disabled states to the macOS controls.
private struct RailActionButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.bordered)
            .controlSize(.regular)
    }
}

private struct QuietButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .font(.system(size: 12))
            .buttonStyle(.bordered)
            .controlSize(.large)
    }
}

private struct PrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

private struct HeaderButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.bordered)
            .controlSize(.large)
    }
}

private struct ImmersiveControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.white.opacity(configuration.isPressed ? 0.27 : 0.13),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PlayButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

private final class PlayerSurfaceView: NSView {
    private let playerLayer = AVPlayerLayer()
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = playerLayer
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct MacVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.player = player
        return view
    }
    func updateNSView(_ view: PlayerSurfaceView, context: Context) {
        if view.player !== player { view.player = player }
    }
    static func dismantleNSView(_ view: PlayerSurfaceView, coordinator: ()) { view.player = nil }
}

#Preview { ContentView() }
