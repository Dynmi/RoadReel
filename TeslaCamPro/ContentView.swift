import SwiftUI
import AVKit
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = TeslaCamViewModel()
    @State private var isScrubbing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                Divider().overlay(Color.white.opacity(0.1))
                clipList
                Divider().overlay(Color.white.opacity(0.1))
                playerPanel
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            viewModel.bootstrap()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TeslaCam Pro")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("行车记录仪")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            Divider().overlay(Color.white.opacity(0.1))

            Text("视频来源")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            Picker("Drive", selection: $viewModel.selectedDriveID) {
                ForEach(viewModel.availableDrives) { drive in
                    Text(drive.displayName).tag(Optional(drive.id))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.selectedDriveID) { _, _ in
                viewModel.loadSelectedDrive()
            }

            Button {
                viewModel.pickDriveManually()
            } label: {
                Label("选择TeslaCam目录", systemImage: "externaldrive.badge.plus")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.refreshDrives()
            } label: {
                Label("刷新U盘", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Divider().overlay(Color.white.opacity(0.1))

            ForEach(TeslaClipCategory.allCases) { category in
                Button {
                    viewModel.selectedCategory = category
                } label: {
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text("\(viewModel.clips(for: category).count)")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(viewModel.selectedCategory == category ? Color.white.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(20)
        .frame(width: 250)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
    }

    private var clipList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.selectedCategory.title)
                .font(.title3.weight(.semibold))

            if viewModel.isLoading {
                ProgressView("正在扫描TeslaCam视频…")
                    .tint(.white)
            }

            List(viewModel.clips(for: viewModel.selectedCategory), selection: $viewModel.selectedClipID) { clip in
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.displayTitle)
                        .font(.headline)
                    Text(clip.displaySubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.vertical, 6)
                .listRowBackground(viewModel.selectedClipID == clip.id ? Color.white.opacity(0.12) : Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onChange(of: viewModel.selectedClipID) { _, _ in
                viewModel.activateSelectedClip()
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(Color(red: 0.05, green: 0.05, blue: 0.07))
    }

    private var playerPanel: some View {
        VStack(spacing: 12) {
            if let session = viewModel.session {
                VideoGridView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                controls
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("请插入包含 TeslaCam 的U盘并选择视频")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .background(Color.black)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(
                get: { viewModel.currentTime },
                set: { value in
                    viewModel.currentTime = value
                    isScrubbing = true
                }
            ), in: 0...max(viewModel.duration, 0.1), onEditingChanged: { editing in
                if !editing && isScrubbing {
                    viewModel.seekAll(to: viewModel.currentTime)
                    isScrubbing = false
                }
            })
            .tint(.red)

            HStack {
                Text(viewModel.timeText(viewModel.currentTime))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    viewModel.seekRelative(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                }
                .buttonStyle(.bordered)

                Button {
                    viewModel.togglePlayPause()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .frame(minWidth: 40)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    viewModel.seekRelative(by: 10)
                } label: {
                    Image(systemName: "goforward.10")
                }
                .buttonStyle(.bordered)

                Spacer()
                Text(viewModel.timeText(viewModel.duration))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

private struct VideoGridView: View {
    let session: TeslaPlaybackSession

    var body: some View {
        VStack(spacing: 8) {
            if let front = session.player(for: .front) {
                VideoPlayer(player: front)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 8) {
                cameraTile(for: .leftRepeater)
                cameraTile(for: .rear)
                cameraTile(for: .rightRepeater)
            }
            .frame(height: 170)
        }
    }

    @ViewBuilder
    private func cameraTile(for camera: TeslaCamera) -> some View {
        if let player = session.player(for: camera) {
            VideoPlayer(player: player)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                Text(camera.title)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

#Preview {
    ContentView()
}
