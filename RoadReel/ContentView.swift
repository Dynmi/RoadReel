import SwiftUI
import AVFoundation
import AppKit

private enum AppPalette {
    static let window = Color(red: 0.035, green: 0.038, blue: 0.045)
    static let sidebar = Color(red: 0.055, green: 0.058, blue: 0.068)
    static let browser = Color(red: 0.043, green: 0.046, blue: 0.054)
    static let surface = Color.white.opacity(0.055)
    static let surfaceRaised = Color.white.opacity(0.085)
    static let border = Color.white.opacity(0.09)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.38)
    static let accent = Color(red: 0.94, green: 0.18, blue: 0.22)
    static let accentSoft = Color(red: 0.94, green: 0.18, blue: 0.22).opacity(0.16)
    static let event = Color(red: 1.0, green: 0.57, blue: 0.16)
}

struct ContentView: View {
    let language: AppLanguage
    let onChangeLanguage: (AppLanguage) -> Void

    @StateObject private var viewModel = TeslaCamViewModel()
    @State private var searchText = ""
    @State private var clipPendingDeletion: TeslaClip?
    @State private var selectedCamera: TeslaCamera = .front
    @State private var isFullScreen = false
    @State private var newestFirst = true

    init(
        language: AppLanguage = .simplifiedChinese,
        onChangeLanguage: @escaping (AppLanguage) -> Void = { _ in }
    ) {
        self.language = language
        self.onChangeLanguage = onChangeLanguage
    }

    var body: some View {
        HStack(spacing: 0) {
            if !isFullScreen {
                sidebar.frame(width: 224)
                separator
                clipBrowser.frame(width: 352)
                separator
            }
            playerPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .background(AppPalette.window)
        .frame(minWidth: 1120, minHeight: 720)
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.24), value: isFullScreen)
        .onAppear {
            viewModel.setLanguage(language)
            viewModel.bootstrap()
            isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) == true
        }
        .onChange(of: language) { _, newLanguage in viewModel.setLanguage(newLanguage) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onDisappear { viewModel.shutdown() }
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
                "“\(clip.displayTitle)” and its \(videoCount) video files will be moved to Trash and can be restored until Trash is emptied."
            ))
        }
    }

    private func t(_ chinese: String, _ english: String) -> String {
        language.text(chinese, english)
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.075)).frame(width: 1)
    }

    private var selectedDrive: TeslaDrive? {
        viewModel.availableDrives.first { $0.id == viewModel.selectedDriveID }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("RoadReel")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Text(t("录像中心 · 1.0", "Recording Center · 1.0"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppPalette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 4)
                Menu {
                    Picker(t("界面语言", "Interface Language"), selection: Binding(
                        get: { language },
                        set: { onChangeLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(language.shortName)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.textSecondary)
                    .padding(.horizontal, 7).frame(height: 28)
                    .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help(t("切换语言", "Change language"))
            }
            .padding(.bottom, 22)

            driveCard

            Text(t("录像库", "LIBRARY"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppPalette.textTertiary)
                .textCase(.uppercase)
                .padding(.top, 24)
                .padding(.bottom, 8)

            VStack(spacing: 5) {
                ForEach(TeslaClipCategory.allCases) { category in
                    categoryButton(category)
                }
            }

            Spacer(minLength: 16)
            statusCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(AppPalette.sidebar)
    }

    private var driveCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(selectedDrive == nil ? Color.gray.opacity(0.25) : Color.green.opacity(0.16))
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedDrive == nil ? AppPalette.textSecondary : .green)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(t("录像来源", "SOURCE")).font(.caption2).foregroundStyle(AppPalette.textTertiary)
                    Text(selectedDrive?.displayName ?? t("未连接", "Not Connected"))
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Spacer(minLength: 4)

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
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if let capacity = driveCapacityText {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text(capacity).font(.caption2).foregroundStyle(AppPalette.textSecondary)
                }
            }

            HStack(spacing: 8) {
                Button { viewModel.pickDriveManually() } label: {
                    Label(t("打开", "Open"), systemImage: "folder").frame(maxWidth: .infinity)
                }
                Button {
                    viewModel.refreshDrives()
                    viewModel.loadSelectedDrive()
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 20)
                }
                .help(t("重新扫描录像", "Rescan recordings"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.border, lineWidth: 1)
        }
    }

    private func categoryButton(_ category: TeslaClipCategory) -> some View {
        let selected = viewModel.selectedCategory == category
        return Button {
            searchText = ""
            selectedCamera = .front
            viewModel.selectCategory(category)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? .white : categoryColor(category))
                    .frame(width: 27, height: 27)
                    .background(
                        selected ? AppPalette.accent : categoryColor(category).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                Text(category.title(for: language)).font(.subheadline.weight(selected ? .semibold : .medium))
                Spacer()
                Text("\(viewModel.clips(for: category).count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(selected ? .white.opacity(0.78) : AppPalette.textTertiary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.white.opacity(selected ? 0.11 : 0.045), in: Capsule())
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(selected ? AppPalette.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? AppPalette.accent.opacity(0.28) : Color.clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusCard: some View {
        if viewModel.isLoading || viewModel.isDeleting || viewModel.isExporting || viewModel.statusMessage != nil {
            HStack(alignment: .top, spacing: 9) {
                if viewModel.isLoading || viewModel.isDeleting || viewModel.isExporting {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Text(viewModel.statusMessage ?? t("正在处理…", "Working…"))
                    .font(.caption2).foregroundStyle(AppPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var driveCapacityText: String? {
        guard let selectedDrive,
              let values = try? selectedDrive.teslaCamURL.resourceValues(
                forKeys: [
                    .volumeAvailableCapacityForImportantUsageKey,
                    .volumeAvailableCapacityKey,
                    .volumeTotalCapacityKey
                ]
              ) else { return nil }
        let importantCapacity = values.volumeAvailableCapacityForImportantUsage ?? 0
        let basicCapacity = Int64(values.volumeAvailableCapacity ?? 0)
        let available = importantCapacity > 0 ? importantCapacity : basicCapacity
        guard available > 0 else { return t("容量信息不可用", "Capacity unavailable") }
        let availableText = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
        if let total = values.volumeTotalCapacity {
            let totalText = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
            return t("\(availableText) 可用 · 共 \(totalText)", "\(availableText) free · \(totalText) total")
        }
        return t("\(availableText) 可用", "\(availableText) free")
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
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.selectedCategory.title(for: language)).font(.title3.weight(.bold))
                    Text(t("\(filteredClips.count) 条录像", "\(filteredClips.count) recordings"))
                        .font(.caption).foregroundStyle(AppPalette.textTertiary)
                }
                Spacer()

                Menu {
                    Button { newestFirst = true } label: {
                        Label(t("最新优先", "Newest First"), systemImage: newestFirst ? "checkmark" : "arrow.down")
                    }
                    Button { newestFirst = false } label: {
                        Label(t("最早优先", "Oldest First"), systemImage: newestFirst ? "arrow.up" : "checkmark")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton).help(t("更改排序", "Change sort order"))

                Button { requestDeleteSelectedClip() } label: {
                    Image(systemName: "trash").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(viewModel.selectedClipID == nil ? AppPalette.textTertiary : AppPalette.textSecondary)
                .disabled(viewModel.selectedClipID == nil || viewModel.isDeleting || viewModel.isExporting)
                .help(t("将所选录像移到废纸篓", "Move the selected recording to Trash"))
            }
            .padding(.horizontal, 16).padding(.top, 17).padding(.bottom, 13)

            searchField.padding(.horizontal, 14).padding(.bottom, 12)
            Rectangle().fill(AppPalette.border).frame(height: 1)

            Group {
                if viewModel.isLoading && filteredClips.isEmpty {
                    LoadingStateView(language: language)
                } else if filteredClips.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? t("没有录像", "No Recordings") : t("未找到录像", "No Results"),
                        systemImage: searchText.isEmpty ? "video.slash" : "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? t("此分类中还没有可播放内容", "There are no playable recordings in this category")
                            : t("请尝试其他日期、地点或事件关键词", "Try another date, location, or event keyword"))
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7, pinnedViews: [.sectionHeaders]) {
                            ForEach(clipGroups) { group in
                                Section {
                                    ForEach(group.clips) { clip in clipButton(clip) }
                                } header: {
                                    ClipDayHeader(date: group.date, count: group.clips.count, language: language)
                                }
                            }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 18)
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
            TextField(t("搜索日期、地点或事件", "Search date, location, or event"), text: $searchText)
                .textFieldStyle(.plain).font(.subheadline)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppPalette.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11).frame(height: 34)
        .background(AppPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(AppPalette.border, lineWidth: 1)
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
            if let clip = viewModel.activeClip { playerHeader(clip) } else { emptyPlayerHeader }
            Rectangle().fill(AppPalette.border).frame(height: 1)
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
                    VStack(spacing: 12) {
                        VideoWorkspace(
                            session: session,
                            selectedCamera: $selectedCamera,
                            isExporting: viewModel.isExporting,
                            language: language,
                            onToggleFullScreen: toggleFullScreenPlayback,
                            onExport: { camera, mode in viewModel.export(camera: camera, mode: mode) }
                        )
                        .id(session.id)
                        ControlDeck(viewModel: viewModel, session: session, language: language)
                    }
                    .padding(14)
                    .task(id: session.id) {
                        if session.player(for: selectedCamera) == nil {
                            selectedCamera = TeslaCamera.displayOrder.first(where: { session.player(for: $0) != nil }) ?? .front
                        }
                    }
                } else {
                    PlayerEmptyView(language: language, onChooseFolder: viewModel.pickDriveManually)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppPalette.window)
    }

    private var emptyPlayerHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t("播放器", "PLAYER")).font(.headline)
                Text(t("从录像列表中选择一个项目", "Select a recording from the list"))
                    .font(.caption).foregroundStyle(AppPalette.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).frame(height: 67).background(AppPalette.window)
    }

    private func playerHeader(_ clip: TeslaClip) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(clip.displayTitle).font(.system(.headline, design: .monospaced).weight(.bold))
                HStack(spacing: 7) {
                    if let event = clip.event {
                        MetaChip(text: event.reasonTitle(for: language), systemImage: "exclamationmark.triangle.fill", color: AppPalette.event)
                    }
                    if let location = clip.event?.locationText {
                        MetaChip(text: location, systemImage: "mappin", color: .cyan)
                    }
                    MetaChip(text: clip.displaySubtitle(for: language), systemImage: "camera.fill", color: .gray)
                    MetaChip(
                        text: t("USB 文件不含车辆遥测", "Vehicle telemetry not included on USB"),
                        systemImage: "gauge.with.dots.needle.33percent",
                        color: .gray
                    )
                }
            }
            Spacer(minLength: 12)

            if viewModel.isExporting {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(t("正在导出", "Exporting")).font(.caption).foregroundStyle(AppPalette.textSecondary)
                }
            }

            Button { viewModel.revealActiveClip() } label: {
                Image(systemName: "folder").frame(width: 30, height: 30)
            }
            .buttonStyle(HeaderButtonStyle()).help(t("在 Finder 中显示", "Show in Finder"))

            Menu {
                Section("\(selectedCamera.title(for: language))") {
                    Button { viewModel.export(camera: selectedCamera, mode: .aroundCurrent(radius: 30)) } label: {
                        Label(t("导出当前位置前后 30 秒…", "Export ±30 Seconds…"), systemImage: "scissors")
                    }
                    Button { viewModel.export(camera: selectedCamera, mode: .full) } label: {
                        Label(t("导出完整视角…", "Export Full Camera…"), systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label(t("导出", "Export"), systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 10).frame(height: 32)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .background(AppPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(viewModel.session == nil || viewModel.isExporting)

            Button { toggleFullScreenPlayback() } label: {
                Image(systemName: isFullScreen ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(HeaderButtonStyle())
            .keyboardShortcut("f", modifiers: [.command, .control])
            .help(isFullScreen ? t("退出全屏", "Exit Full Screen") : t("全屏播放", "Play Full Screen"))
        }
        .padding(.horizontal, 18).frame(height: 67).background(AppPalette.window)
    }

    private func categoryColor(_ category: TeslaClipCategory) -> Color {
        switch category {
        case .recent: return .cyan
        case .saved: return .blue
        case .sentry: return AppPalette.event
        }
    }

    private func toggleFullScreenPlayback() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        isFullScreen = !window.styleMask.contains(.fullScreen)
        window.toggleFullScreen(nil)
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
            Text(title).font(.caption.weight(.bold)).foregroundStyle(AppPalette.textSecondary)
            Spacer()
            Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(AppPalette.textTertiary)
        }
        .padding(.horizontal, 6).padding(.top, 12).padding(.bottom, 5)
        .background(AppPalette.browser.opacity(0.96))
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
        HStack(spacing: 11) {
            ZStack(alignment: .bottomLeading) {
                ClipThumbnail(clip: clip)
                LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
                Text(language.text("\(clip.cameraSegments.count) 视角", "\(clip.cameraSegments.count) cams"))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 6).padding(.vertical, 4)
            }
            .frame(width: 108, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(timeText).font(.subheadline.weight(.bold).monospacedDigit())
                    Spacer(minLength: 2)
                    if clip.event != nil { Circle().fill(AppPalette.event).frame(width: 6, height: 6) }
                }
                if let event = clip.event {
                    Text(event.reasonTitle(for: language)).font(.caption.weight(.semibold)).foregroundStyle(AppPalette.event).lineLimit(1)
                } else {
                    Text(clip.category.title(for: language)).font(.caption.weight(.medium)).foregroundStyle(.cyan)
                }
                HStack(spacing: 4) {
                    if let location = clip.event?.locationText {
                        Image(systemName: "mappin")
                        Text(location).lineLimit(1)
                        Text("·")
                    }
                    Text(clip.displaySubtitle(for: language)).lineLimit(1)
                }
                .font(.caption2).foregroundStyle(AppPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? AppPalette.accent : AppPalette.textTertiary.opacity(isHovering ? 1 : 0))
        }
        .padding(9)
        .background(
            isSelected ? AppPalette.accentSoft : (isHovering ? AppPalette.surface : Color.clear),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? AppPalette.accent.opacity(0.38) : Color.clear, lineWidth: 1)
        }
        .contentShape(Rectangle()).onHover { isHovering = $0 }
    }

    private var timeText: String {
        guard let date = clip.displayDate else { return clip.displayTitle }
        return Self.formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct ClipThumbnail: View {
    let clip: TeslaClip
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.045)
            if let image {
                Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Image(systemName: "video.fill").font(.title3).foregroundStyle(AppPalette.textTertiary)
            }
        }
        .clipped()
        .task(id: clip.id) {
            image = nil
            guard let data = await ThumbnailService.shared.imageData(for: clip), !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { image = NSImage(data: data) }
        }
    }
}

private struct MetaChip: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color == .gray ? AppPalette.textSecondary : color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(color == .gray ? 0.08 : 0.12), in: Capsule())
            .lineLimit(1)
    }
}

private struct VideoWorkspace: View {
    let session: TeslaPlaybackSession
    @Binding var selectedCamera: TeslaCamera
    let isExporting: Bool
    let language: AppLanguage
    let onToggleFullScreen: () -> Void
    let onExport: (TeslaCamera, TeslaExportMode) -> Void

    private var availableCameras: [TeslaCamera] {
        TeslaCamera.displayOrder.filter { session.player(for: $0) != nil }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let player = session.player(for: selectedCamera) {
                CameraTile(
                    camera: selectedCamera,
                    player: player,
                    selected: true,
                    prominent: true,
                    isExporting: isExporting,
                    language: language,
                    onSelect: {},
                    onToggleFullScreen: onToggleFullScreen,
                    onExport: { onExport(selectedCamera, $0) }
                )
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 8) {
                HStack {
                    Text(language.text("摄像头", "CAMERAS")).font(.caption.weight(.bold))
                    Text(language.text("点击画面切换主视角", "Click a view to make it primary"))
                        .font(.caption2).foregroundStyle(AppPalette.textTertiary)
                    Spacer()
                    Text(language.text("\(availableCameras.count) 个可用", "\(availableCameras.count) available"))
                        .font(.caption2.monospacedDigit()).foregroundStyle(AppPalette.textTertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(availableCameras, id: \.self) { camera in
                            if let player = session.player(for: camera) {
                                CameraTile(
                                    camera: camera,
                                    player: player,
                                    selected: camera == selectedCamera,
                                    prominent: false,
                                    isExporting: isExporting,
                                    language: language,
                                    onSelect: { selectedCamera = camera },
                                    onToggleFullScreen: {},
                                    onExport: { onExport(camera, $0) }
                                )
                                .frame(width: 142, height: 80)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppPalette.border, lineWidth: 1)
            }
        }
    }
}

private struct CameraTile: View {
    let camera: TeslaCamera
    let player: AVPlayer
    let selected: Bool
    let prominent: Bool
    let isExporting: Bool
    let language: AppLanguage
    let onSelect: () -> Void
    let onToggleFullScreen: () -> Void
    let onExport: (TeslaExportMode) -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            MacVideoPlayer(player: player).background(Color.black)
            LinearGradient(
                colors: [.black.opacity(prominent ? 0.55 : 0.7), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .allowsHitTesting(false)

            HStack(spacing: 6) {
                Image(systemName: camera.systemImage)
                Text(camera.title(for: language))
                if prominent { Text(language.text("主画面", "PRIMARY")).foregroundStyle(.white.opacity(0.55)) }
            }
            .font(prominent ? .caption.weight(.bold) : .caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.black.opacity(0.52), in: Capsule())
            .padding(prominent ? 12 : 7)
            .allowsHitTesting(false)

            if !prominent, selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(AppPalette.accent).padding(7)
                    .frame(maxWidth: .infinity, alignment: .topTrailing).allowsHitTesting(false)
            }

            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture(count: 2) { if prominent { onToggleFullScreen() } }
                .onTapGesture { onSelect() }
                .contextMenu {
                    if !selected {
                        Button { onSelect() } label: {
                            Label(language.text("设为主画面", "Make Primary"), systemImage: "rectangle.inset.filled")
                        }
                        Divider()
                    }
                    Button { onExport(.aroundCurrent(radius: 30)) } label: {
                        Label(language.text("导出当前位置前后 30 秒…", "Export ±30 Seconds…"), systemImage: "scissors")
                    }
                    .disabled(isExporting)
                    Button { onExport(.full) } label: {
                        Label(language.text("导出完整当前视角…", "Export Full Camera…"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: prominent ? 14 : 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: prominent ? 14 : 9, style: .continuous)
                .stroke(
                    selected ? AppPalette.accent.opacity(prominent ? 0.5 : 0.9) : Color.white.opacity(isHovering ? 0.35 : 0.08),
                    lineWidth: selected ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(prominent ? 0.32 : 0), radius: 18, y: 8)
        .scaleEffect(!prominent && isHovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .onHover { isHovering = $0 }
        .help(prominent
            ? language.text("双击全屏，右键导出当前视角", "Double-click for full screen; right-click to export")
            : language.text("单击切换主视角，右键导出", "Click to make primary; right-click to export"))
    }
}

private struct ControlDeck: View {
    @ObservedObject var viewModel: TeslaCamViewModel
    let session: TeslaPlaybackSession
    let language: AppLanguage
    private let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(viewModel.timeText(viewModel.safeCurrentTime)).foregroundStyle(.white)
                Spacer()
                if !session.segmentMarkers.isEmpty {
                    Label(language.text(
                        "\(session.segmentMarkers.count + 1) 段连续录像",
                        "\(session.segmentMarkers.count + 1) continuous segments"
                    ), systemImage: "square.stack.3d.up.fill")
                        .font(.caption2).foregroundStyle(AppPalette.textTertiary)
                }
                Spacer()
                Text("−\(viewModel.timeText(max(0, viewModel.safeDuration - viewModel.safeCurrentTime)))")
                    .foregroundStyle(AppPalette.textSecondary)
            }
            .font(.caption.weight(.semibold).monospacedDigit())

            EventTimeline(
                value: Binding(
                    get: { viewModel.safeCurrentTime },
                    set: { viewModel.updateScrubbing(to: $0) }
                ),
                maximumValue: max(viewModel.safeDuration, 0.1),
                eventMarker: viewModel.eventMarkerTime,
                segmentMarkers: session.segmentMarkers,
                onEditingChanged: { editing in
                    if editing { viewModel.beginScrubbing() } else { viewModel.endScrubbing() }
                }
            )

            HStack(spacing: 9) {
                Button { viewModel.selectAdjacentClip(offset: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(PlayerControlButtonStyle()).disabled(!viewModel.canSelectPreviousClip)
                    .keyboardShortcut(.upArrow, modifiers: [.command]).help(language.text("上一条录像", "Previous recording"))
                Button { viewModel.seekToAdjacentSegment(forward: false) } label: { Image(systemName: "backward.end.fill") }
                    .buttonStyle(PlayerControlButtonStyle()).disabled(session.segmentMarkers.isEmpty).help(language.text("上一段", "Previous segment"))
                Button { viewModel.seekRelative(by: -10) } label: { Image(systemName: "gobackward.10") }
                    .buttonStyle(PlayerControlButtonStyle()).keyboardShortcut(.leftArrow, modifiers: []).help(language.text("后退 10 秒", "Back 10 seconds"))
                Button { viewModel.togglePlayPause() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold)).offset(x: viewModel.isPlaying ? 0 : 1)
                }
                .buttonStyle(PlayButtonStyle()).keyboardShortcut(.space, modifiers: [])
                Button { viewModel.seekRelative(by: 10) } label: { Image(systemName: "goforward.10") }
                    .buttonStyle(PlayerControlButtonStyle()).keyboardShortcut(.rightArrow, modifiers: []).help(language.text("前进 10 秒", "Forward 10 seconds"))
                Button { viewModel.seekToAdjacentSegment(forward: true) } label: { Image(systemName: "forward.end.fill") }
                    .buttonStyle(PlayerControlButtonStyle()).disabled(session.segmentMarkers.isEmpty).help(language.text("下一段", "Next segment"))
                Button { viewModel.selectAdjacentClip(offset: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(PlayerControlButtonStyle()).disabled(!viewModel.canSelectNextClip)
                    .keyboardShortcut(.downArrow, modifiers: [.command]).help(language.text("下一条录像", "Next recording"))

                Spacer()
                if let marker = viewModel.eventMarkerTime {
                    Button { viewModel.seekToEvent() } label: {
                        Label(language.text("事件 \(viewModel.timeText(marker))", "Event \(viewModel.timeText(marker))"), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold).monospacedDigit())
                    }
                    .buttonStyle(EventButtonStyle()).help(language.text("跳转到事件发生位置", "Jump to the event"))
                }
                Spacer()

                Button { viewModel.toggleMute() } label: {
                    Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(PlayerControlButtonStyle()).keyboardShortcut("m", modifiers: [])
                .help(viewModel.isMuted ? language.text("打开声音", "Unmute") : language.text("静音", "Mute"))

                Menu {
                    ForEach(rates, id: \.self) { rate in
                        Button { viewModel.setPlaybackRate(rate) } label: {
                            if viewModel.playbackRate == rate {
                                Label(rateText(rate), systemImage: "checkmark")
                            } else {
                                Text(rateText(rate))
                            }
                        }
                    }
                } label: {
                    Text(rateText(viewModel.playbackRate))
                        .font(.caption.weight(.bold).monospacedDigit()).frame(minWidth: 40, minHeight: 30)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .background(AppPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help(language.text("播放速度", "Playback speed"))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(AppPalette.border, lineWidth: 1)
        }
    }

    private func rateText(_ rate: Float) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(String(format: "%.2g", rate))×"
    }
}

private struct EventTimeline: View {
    @Binding var value: Double
    let maximumValue: Double
    let eventMarker: Double?
    let segmentMarkers: [Double]
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            Slider(value: $value, in: 0...maximumValue, onEditingChanged: onEditingChanged)
                .tint(AppPalette.accent)
            GeometryReader { geometry in
                let usableWidth = max(0, geometry.size.width - 18)
                ForEach(Array(segmentMarkers.enumerated()), id: \.offset) { _, marker in
                    if marker.isFinite, marker > 0, marker < maximumValue {
                        let x = 9 + usableWidth * min(1, max(0, marker / maximumValue))
                        Capsule().fill(Color.white.opacity(0.28)).frame(width: 2, height: 8)
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
        }
        .frame(height: 22)
    }
}

private struct LoadingStateView: View {
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 13) {
            ProgressView().controlSize(.large).tint(.white)
            Text(language.text("正在整理录像库", "Organizing Library")).font(.headline)
            Text(language.text("正在读取日期、事件和缩略图…", "Reading dates, events, and thumbnails…"))
                .font(.caption).foregroundStyle(AppPalette.textTertiary)
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
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
                ProgressView().controlSize(.large).tint(AppPalette.accent)
            }
            .frame(width: 64, height: 64)
            Text(language.text("正在准备多视角播放", "Preparing Multi-Camera Playback")).font(.headline)
            Text(clip?.displayTitle ?? language.text("正在连接视频轨道…", "Connecting video tracks…"))
                .font(.caption.monospacedDigit()).foregroundStyle(AppPalette.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlayerEmptyView: View {
    let language: AppLanguage
    let onChooseFolder: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(AppPalette.surface)
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 32)).foregroundStyle(AppPalette.textSecondary)
            }
            .frame(width: 82, height: 72)
            Text(language.text("选择一条录像开始查看", "Select a Recording to Begin")).font(.title3.weight(.bold))
            Text(language.text(
                "支持六视角同步、事件定位、片段导出与安全删除",
                "Six synchronized cameras, event markers, clip export, and safe deletion"
            ))
                .font(.subheadline).foregroundStyle(AppPalette.textTertiary)
            Button(language.text("选择 TeslaCam 目录", "Choose TeslaCam Folder"), action: onChooseFolder)
                .buttonStyle(.borderedProminent).tint(AppPalette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppPalette.textSecondary)
            .background(
                configuration.isPressed ? Color.white.opacity(0.13) : AppPalette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

private struct PlayerControlButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white.opacity(0.82) : AppPalette.textTertiary)
            .frame(width: 31, height: 31)
            .background(
                configuration.isPressed ? Color.white.opacity(0.14) : AppPalette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

private struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white).frame(width: 43, height: 35)
            .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: AppPalette.accent.opacity(0.25), radius: 8, y: 3)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

private struct EventButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppPalette.event).padding(.horizontal, 10).frame(height: 30)
            .background(AppPalette.event.opacity(configuration.isPressed ? 0.2 : 0.11), in: Capsule())
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
