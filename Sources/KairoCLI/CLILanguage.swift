import Foundation

/// CLI 人类输出的语言（F-0707 · 设计 §6）。
///
/// 阶段一只交付两种语言：`en` 与 `zh-Hans`。解析按 BCP-47 的语言子标签判定：
/// `en` / `en-US` → `.en`；`zh` / `zh-Hans` / `zh-CN` / `zh-Hans-CN` → `.zhHans`。
/// 繁体（`zh-Hant` / `zh-TW` / `zh-HK` / `zh-MO`）与其它语言一律「不支持」。
///
/// 两种失败路径的处理不同，这是刻意的：
/// - `--lang` 值非法 → 用法错误、退出码 2（G-01，用户当场可见并改正）；
/// - `KAIRO_LANG` 值非法 → 静默回退系统语言（G-02，CI 里一个杂散环境变量
///   不该让命令行工具整体不可用）。
enum CLILanguage: String, CaseIterable, Sendable {
    case en
    case zhHans = "zh-Hans"

    /// 允许值，用法错误的提示里逐字列出。
    static let allowedValues = CLILanguage.allCases.map(\.rawValue)

    /// 解析 BCP-47 标签；不支持的取值或非法格式（如下划线 `zh_CN`）返回 nil。
    static func parse(_ raw: String) -> CLILanguage? {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return nil }
        // 下划线不是 BCP-47 分隔符，`zh_CN` 必须判非法（G-01），故不做事先归一化。
        let subtags = tag.split(separator: "-", omittingEmptySubsequences: false).map { $0.lowercased() }
        guard subtags.allSatisfy({ !$0.isEmpty }) else { return nil }
        switch subtags[0] {
        case "en":
            return .en
        case "zh":
            // 只交付简体：显式繁体脚本与台港澳地区不冒充 zh-Hans。
            let traditional: Set<String> = ["hant", "tw", "hk", "mo"]
            return subtags.dropFirst().contains(where: traditional.contains) ? nil : .zhHans
        default:
            return nil
        }
    }

    /// 环境变量 > 系统语言 > `zh-Hans` 兜底。
    ///
    /// 兜底选中文而不是英文，是为了不破坏既有中文脚本（设计 §6）：英文用户显式传
    /// `--lang en` 或设 `KAIRO_LANG=en`；系统语言不可判定时按既有行为出中文。
    static func fromEnvironmentOrSystem(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> CLILanguage {
        if let raw = environment[environmentVariable], let language = parse(raw) {
            return language
        }
        if let preferred = preferredLanguages.first, let language = parse(preferred) {
            return language
        }
        return .zhHans
    }

    /// 环境变量名（`--lang` 之外的等价入口）。
    static let environmentVariable = "KAIRO_LANG"

    /// 当前语言（未显式传 `--lang` 时）。
    static var current: CLILanguage { fromEnvironmentOrSystem() }

    /// 本语言的文案表。
    var strings: CLIStrings { CLIStrings(language: self) }
}
