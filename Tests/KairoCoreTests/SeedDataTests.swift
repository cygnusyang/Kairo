import Foundation
import Testing
@testable import KairoCore

/// 演示数据契约：应用首启动依赖这份数据，时间线必须锚定到当前日期附近。
struct SeedDataTests {
    @Test func demoProjectSeedsTenTasks() {
        #expect(SeedData.makeProject().tasks.count == 10)
    }

    @Test func demoProjectAnchorsTimelineNearToday() throws {
        let project = SeedData.makeProject()
        let start = try #require(project.metadata.projectStart)
        let end = try #require(project.metadata.projectEnd)

        #expect(end > start)
        // 排期引擎在无项目起点时从 1970 纪元起算（D-002）。
        #expect(start.timeIntervalSince1970 > 1_000_000_000)
        #expect(abs(start.timeIntervalSinceNow) < 7 * 86_400)
    }
}

// MARK: - F-D7 按语言生成示例（Core 侧接口，G4 按界面语言接线）

private func containsCJK(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
}

extension SeedDataTests {
    /// 默认语言保持中文：v0.8.5 调用点（`makeProject()`）零破坏。
    @Test func defaultLanguageStaysSimplifiedChinese() throws {
        let project = SeedData.makeProject()
        let zh = SeedData.makeProject(language: .zhHans)

        #expect(project.tasks.map(\.title) == zh.tasks.map(\.title))
        #expect(project.tasks.contains { containsCJK($0.title) })
    }

    /// 英文模板：文案里不得残留中文，但结构与中文模板逐项一致（数量 / 类型 / 优先级 / 状态 / 依赖数）。
    @Test func englishSeedHasNoChineseAndSameStructure() {
        let zh = SeedData.makeProject(language: .zhHans)
        let en = SeedData.makeProject(language: .en)

        #expect(en.tasks.count == zh.tasks.count)
        #expect(en.tasks.map(\.kind) == zh.tasks.map(\.kind))
        #expect(en.tasks.map(\.priority) == zh.tasks.map(\.priority))
        #expect(en.tasks.map(\.status) == zh.tasks.map(\.status))
        #expect(en.tasks.map { $0.dependencies.count } == zh.tasks.map { $0.dependencies.count })
        #expect(en.tasks.map(\.tags.count) == zh.tasks.map(\.tags.count))

        for task in en.tasks {
            #expect(!containsCJK(task.title), "英文模板标题含中文：\(task.title)")
            #expect(!containsCJK(task.notes), "英文模板备注含中文：\(task.notes)")
            for tag in task.tags {
                #expect(!containsCJK(tag), "英文模板标签含中文：\(tag)")
            }
        }
        #expect(en.tasks.contains { $0.title == "Build search backend" })
    }

    /// 两语言的时间线锚定口径一致（同一天内生成，起止偏移相同）。
    @Test func bothLanguagesAnchorTimelineIdentically() throws {
        let zh = SeedData.makeProject(language: .zhHans)
        let en = SeedData.makeProject(language: .en)
        let zhStart = try #require(zh.metadata.projectStart)
        let enStart = try #require(en.metadata.projectStart)
        let zhEnd = try #require(zh.metadata.projectEnd)
        let enEnd = try #require(en.metadata.projectEnd)

        #expect(abs(zhStart.timeIntervalSince(enStart)) < 5 * 60)
        #expect(abs(zhEnd.timeIntervalSince(enEnd)) < 5 * 60)
    }
}
