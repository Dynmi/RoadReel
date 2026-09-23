import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese: return "中文"
        case .english: return "English"
        }
    }

    var shortName: String {
        switch self {
        case .simplifiedChinese: return "中文"
        case .english: return "EN"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    func text(_ chinese: String, _ english: String) -> String {
        self == .simplifiedChinese ? chinese : english
    }
}

struct LanguageSelectionView: View {
    let onSelect: (AppLanguage) -> Void

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.038, blue: 0.045).ignoresSafeArea()
            VStack(spacing: 28) {
                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .frame(width: 82, height: 82)
                .shadow(color: .red.opacity(0.28), radius: 24, y: 10)

                VStack(spacing: 8) {
                    Text("RoadReel")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("选择语言  ·  Choose your language")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }

                HStack(spacing: 14) {
                    languageButton(.simplifiedChinese, subtitle: "简体中文")
                    languageButton(.english, subtitle: "English")
                }
            }
            .padding(44)
        }
        .foregroundStyle(.white)
        .frame(minWidth: 680, minHeight: 460)
        .preferredColorScheme(.dark)
    }

    private func languageButton(_ language: AppLanguage, subtitle: String) -> some View {
        Button { onSelect(language) } label: {
            VStack(spacing: 10) {
                Image(systemName: language == .simplifiedChinese ? "character.book.closed.fill" : "textformat")
                    .font(.system(size: 24, weight: .semibold))
                Text(language.displayName).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            .frame(width: 176, height: 112)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
