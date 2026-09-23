import SwiftUI

@main
struct RoadReelApp: App {
    @AppStorage(AppLanguage.storageKey) private var storedLanguage = ""

    var body: some Scene {
        WindowGroup {
            if let language = AppLanguage(rawValue: storedLanguage) {
                ContentView(
                    language: language,
                    onChangeLanguage: setLanguage
                )
                .id(language.rawValue)
            } else {
                LanguageSelectionView(onSelect: setLanguage)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }

    private func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
        storedLanguage = language.rawValue
    }
}
