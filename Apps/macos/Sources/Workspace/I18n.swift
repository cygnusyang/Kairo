import Foundation

/// 视图层唯一取词入口（F-0705 / 设计 §D.1 / §D.5）。
///
/// 语义键 + 英文兜底：`.app` 内命中编译后的 String Catalog；`swift run` / `swift test`
/// 没有 `.lproj`（实测 E1/E2），此时退回调用点写的英文，任何情况下都不会把裸键显示给用户。
enum I18n {
    /// 当前生效语言的资源包；无对应 `.lproj` 时回退 `Bundle.main`（英文兜底）。
    static let bundle: Bundle = resolveBundle()

    /// 取词：未命中时返回调用点写的英文兜底。
    static func t(_ key: String, _ en: String, bundle: Bundle = I18n.bundle) -> String {
        bundle.localizedString(forKey: key, value: en, table: nil)
    }

    /// 位置参数取词：占位符一律 `%1$ld` / `%2$@`，避免中英语序差异导致错位。
    static func t(_ key: String, _ en: String, _ args: CVarArg...) -> String {
        String(format: t(key, en), arguments: args)
    }

    /// 生效语言决定的 Locale（日期、数字与复数分类共用）。
    static var locale: Locale { AppLanguage.current.locale }

    private static func resolveBundle() -> Bundle {
        guard let code = AppLanguage.current.bundleCode,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

/// 界面语言（F-0706）：三档，持久化后重启生效。
///
/// 不用 `AppleLanguages` 覆写：那需要改进程级偏好且命中时机不确定；这里直接按
/// 语言选 `.lproj` 资源包（`I18n.bundle`），行为在 `.app` 与裸跑下一致。
enum AppLanguage: String, CaseIterable, Sendable {
    /// 跟随系统；系统语言不受支持时回退英文（`CFBundleDevelopmentRegion`）。
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    /// 偏好键。
    static let defaultsKey = "KairoLanguage"

    /// 持久化的用户选择；缺失或取值非法（含被手工改成 `fr`）一律按 `.system` 处理。
    static func stored(in defaults: UserDefaults = .standard) -> AppLanguage {
        guard let raw = defaults.string(forKey: defaultsKey) else { return .system }
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// 写入用户选择（重启后生效）。
    static func store(_ language: AppLanguage, in defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: defaultsKey)
    }

    /// 持久化的用户选择（生产入口）。
    static var selected: AppLanguage {
        get { stored() }
        set { store(newValue) }
    }

    /// 生效语言：`.system` 取系统首选语言中第一个受支持的语言，判不出时回退英文。
    static func current(in defaults: UserDefaults = .standard) -> AppLanguage {
        let choice = stored(in: defaults)
        switch choice {
        case .system:
            return supported(from: Locale.preferredLanguages.first) ?? .english
        case .english, .simplifiedChinese:
            return choice
        }
    }

    /// 生效语言（生产入口）。
    static var current: AppLanguage { current(in: .standard) }

    /// `.lproj` 目录名；`.system` 由 `current` 解析后不会走到这里。
    var bundleCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }

    /// 该语言决定的 Locale；`.system` 用系统当前 Locale（日期与数字随系统地区）。
    var locale: Locale {
        switch self {
        case .system: return Locale.current
        case .english: return Locale(identifier: "en_US")
        case .simplifiedChinese: return Locale(identifier: "zh_CN")
        }
    }

    /// BCP-47 标识 → 受支持语言；识别不了（nil / 空 / 非法）返回 nil。
    static func supported(from identifier: String?) -> AppLanguage? {
        guard let identifier, !identifier.isEmpty,
              let language = Locale(identifier: identifier).language.languageCode else {
            return nil
        }
        switch language.identifier {
        case "zh": return .simplifiedChinese
        case "en": return .english
        default: return nil
        }
    }
}
