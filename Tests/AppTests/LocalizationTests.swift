import Foundation
import Testing
@testable import KairoMacApp

/// 多语言基础契约（v0.9.0 · F-0705 / F-0706 / F-0712）。
///
/// 只锁「结构与数据」：键存在且两侧非空、占位符一致、取词有英文兜底、语言选择可持久化、
/// 格式化随注入 Locale 变化。具体译文措辞不在断言范围（A-04 走键-文案对照表 diff）。
@Suite("多语言基础（F-0705 / F-0706 / F-0712）")
struct LocalizationTests {
    // MARK: - 取词

    /// 未命中 Catalog 时返回调用点英文，不把裸键显示给用户（设计 §D.5）。
    @Test func lookupFallsBackToEnglishInsteadOfBareKey() {
        let fallback = "Missing key fallback"
        let value = I18n.t("nonexistent.key.for.test", fallback)
        #expect(value == fallback)
        #expect(!value.contains("nonexistent.key.for.test"))
    }

    /// 位置参数按出现顺序代入，与语序无关。
    @Test func lookupSubstitutesPositionalArguments() {
        let value = I18n.t("nonexistent.key.with.args", "%1$@ · %2$ld", "Custom", 12)
        #expect(value == "Custom · 12")
    }

    // MARK: - Catalog 数据（A-07 / G-05 / G-06）

    /// Catalog 位于仓库内：由测试文件路径回推仓库根。
    private func catalog() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
        let url = root.appendingPathComponent("Apps/macos/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(object?["strings"] as? [String: Any])
    }

    private func value(_ entry: Any, language: String) -> String? {
        guard let entry = entry as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any],
              let unit = localizations[language] as? [String: Any],
              let stringUnit = unit["stringUnit"] as? [String: Any] else {
            return nil
        }
        return stringUnit["value"] as? String
    }

    /// 两侧零缺键：每个键在 en 与 zh-Hans 都有非空译文。
    @Test func catalogHasNoMissingTranslations() throws {
        let strings = try catalog()
        #expect(!strings.isEmpty)
        for (key, entry) in strings {
            let en = value(entry, language: "en")
            let zh = value(entry, language: "zh-Hans")
            #expect(en?.isEmpty == false, "en 译文缺失：\(key)")
            #expect(zh?.isEmpty == false, "zh-Hans 译文缺失：\(key)")
        }
    }

    /// 占位符一致：两侧同位置同类型，避免语序错位。
    @Test func catalogPlaceholdersMatchOnBothSides() throws {
        let pattern = #/%(?:(\d+)\$)?[-+ #0]*[0-9.*]*(?:hh|h|ll|l|q|L|z|t|j)?([@dDuUxXoOfFeEgGcsSip])/#
        for (key, entry) in try catalog() {
            let en = try #require(value(entry, language: "en"))
            let zh = try #require(value(entry, language: "zh-Hans"))
            let enTokens = en.matches(of: pattern).map { "\($0.1 ?? ""):\($0.2)" }.sorted()
            let zhTokens = zh.matches(of: pattern).map { "\($0.1 ?? ""):\($0.2)" }.sorted()
            #expect(enTokens == zhTokens, "占位符不一致：\(key)")
        }
    }

    // MARK: - 日期与单位（F-0712）

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth)) ?? Date()
    }

    /// 完整日期随注入 Locale 变化。
    @Test func displayDateFollowsLocale() {
        let date = day(2026, 11, 6)
        #expect(Display.date(date, locale: Locale(identifier: "zh_CN")) == "2026/11/6")
        #expect(Display.date(date, locale: Locale(identifier: "en_US")) == "11/6/2026")
        #expect(!Display.date(date, locale: Locale(identifier: "en_US")).contains("年"))
    }

    /// 契约格式：`isoDate` 与语言无关，两语言字节一致。
    @Test func isoDateIsLocaleIndependentContractFormat() {
        let date = day(2026, 11, 6)
        #expect(Display.isoDate(date) == "2026-11-06")
        #expect(Display.isoDateFormatter.locale.identifier == "en_US_POSIX")
        #expect(Display.isoDateFormatter.dateFormat == "yyyy-MM-dd")
        #expect(Display.isoDate(nil) == Display.placeholder)
    }

    /// 月标题与星期表头按语言本地化，首周日仍由 calendar 决定。
    @Test func monthTitleAndWeekdaySymbolsFollowLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        #expect(Display.monthTitle(day(2026, 11, 6), calendar: calendar, locale: Locale(identifier: "zh_CN")) == "2026年11月")
        #expect(Display.monthTitle(day(2026, 11, 6), calendar: calendar, locale: Locale(identifier: "en_US")) == "November 2026")
        #expect(Display.weekdaySymbols(calendar: calendar, locale: Locale(identifier: "zh_CN")) == ["一", "二", "三", "四", "五", "六", "日"])
        #expect(Display.weekdaySymbols(calendar: calendar, locale: Locale(identifier: "en_US")) == ["M", "T", "W", "T", "F", "S", "S"])
    }

    /// 时长用本地化单位：英文侧不出现中文单位，中文侧不带空格。
    @Test func durationUsesLocalizedUnits() {
        #expect(Display.duration(3, locale: Locale(identifier: "en_US")) == "3 days")
        #expect(Display.duration(1.5, locale: Locale(identifier: "en_US")) == "1.5 days")
        #expect(Display.duration(3, locale: Locale(identifier: "zh_CN")) == "3天")
        #expect(Display.duration(1.5, locale: Locale(identifier: "zh_CN")) == "1.5天")
        #expect(Display.duration(nil) == Display.placeholder)
        #expect(Display.duration(.nan) == Display.placeholder)
    }

    /// 甘特预览与提示条时刻同属展示格式。
    @Test func previewDateAndClockFollowLocale() {
        #expect(Display.shortMonthDay(day(2026, 11, 6), locale: Locale(identifier: "zh_CN")) == "11月6日")
        #expect(Display.shortMonthDay(day(2026, 11, 6), locale: Locale(identifier: "en_US")) == "Nov 6")
        #expect(!Display.time(day(2026, 11, 6), locale: Locale(identifier: "en_US")).isEmpty)
    }
}
