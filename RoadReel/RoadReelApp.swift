import SwiftUI

@main
struct RoadReelApp: App {
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = AppLanguage.english.rawValue
    @StateObject private var updater = AppUpdater()

    var body: some Scene {
        WindowGroup {
            ContentView(
                language: AppLanguage(rawValue: storedLanguage) ?? .english,
                onChangeLanguage: setLanguage
            )
            .environmentObject(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(appLanguage.text("检查更新…", "Check for Updates…")) {
                    updater.checkForUpdates()
                }
                .disabled(updater.isInstalling)
                Link(appLanguage.text("RoadReel 开源项目", "RoadReel on GitHub"), destination: AppUpdater.repositoryURL)
            }
        }
    }

    private var appLanguage: AppLanguage { AppLanguage(rawValue: storedLanguage) ?? .english }

    private func setLanguage(_ language: AppLanguage) {
        storedLanguage = language.rawValue
    }
}
