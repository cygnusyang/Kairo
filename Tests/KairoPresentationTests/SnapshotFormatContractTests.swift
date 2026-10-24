import Foundation
import Testing
import KairoCore
@testable import KairoPresentation

// F-0704 附带契约：快照里不得出现随 Locale 变的数字/文案。
//
// 旧实现用 Double.formatted() 拼前置延隔（1.5 / 1,5 随系统 Locale 变），该字符串进快照
// 并被 AppTests 逐字断言——属契约格式，必须钉死；缩放读数同理只在快照里放数值。

struct SnapshotFormatContractTests {
    @Test func contractDecimalUsesFixedPointRegardlessOfLocale() {
        // 定点输出：整数值不带小数位，非整数保留 1 位，小数点恒为 "."（非 Locale 相关）。
        #expect(WorkspacePresenter.contractDecimal(1.5) == "1.5")
        #expect(WorkspacePresenter.contractDecimal(2) == "2")
        #expect(WorkspacePresenter.contractDecimal(12.25) == "12.3")
        #expect(WorkspacePresenter.contractDecimal(-1.5) == "-1.5")
        #expect(!WorkspacePresenter.contractDecimal(1.5).contains(","))
    }

    @Test func predecessorsTextRendersLagWithoutLocaleSeparator() {
        let predecessorID = UUID()
        let dependencies = [
            TaskDependency(predecessorID: predecessorID, type: .fs, lagDays: 1.5),
            TaskDependency(predecessorID: UUID(), type: .ss, lagDays: 2)
        ]
        let text = WorkspacePresenter.predecessorsText(
            dependencies,
            outlineNumberByID: [predecessorID: "1"]
        )

        #expect(text.hasPrefix("1:fs+1.5"))
        #expect(text.contains("ss+2"))
        #expect(!text.contains(",5"), "延隔小数位不得随 Locale 变成逗号：\(text)")
    }

    @Test func renderableDayWidthRejectsValuesThatCannotBeRendered() {
        #expect(WorkspacePresenter.renderableDayWidth(12.5) == 12.5)
        #expect(WorkspacePresenter.renderableDayWidth(20) == 20)
        #expect(WorkspacePresenter.renderableDayWidth(.nan) == nil)
        #expect(WorkspacePresenter.renderableDayWidth(.infinity) == nil)
        #expect(WorkspacePresenter.renderableDayWidth(-.infinity) == nil)
        #expect(WorkspacePresenter.renderableDayWidth(1e16) == nil)
    }

    /// 同一输入、不同 Locale 两次成快照：语言无关部分必须逐位相等（C-01 的口径）。
    ///
    /// 已知且**有意**的例外是甘特刻度标签：F-0702 起按注入 Locale 本地化，
    /// 标签文本随语言变（布局契约的历史形态，视图需要它），故只比较结构化部分。
    @Test func snapshotIsLanguageNeutralOutsideGanttTickLabels() {
        let projectStart = makeDate(2025, 1, 1)
        let tasks = [TaskItem(title: "任务 A", startDate: projectStart, durationDays: 2)]
        let state = makeState(tasks, projectStart: projectStart)
        let now = makeDate(2025, 1, 3)
        let schedule = makeSchedule(tasks, projectStart: projectStart, now: now)
        var viewState = WorkspaceViewState()
        viewState.filterText = "任务"

        let en = makeSnapshot(
            state: state, schedule: schedule, viewState: viewState,
            locale: Locale(identifier: "en_US"), now: now
        )
        let zh = makeSnapshot(
            state: state, schedule: schedule, viewState: viewState,
            locale: Locale(identifier: "zh_CN"), now: now
        )

        #expect(en.outline == zh.outline)
        #expect(en.inspector == zh.inspector)
        #expect(en.statusBar == zh.statusBar)
        #expect(en.gantt.bars == zh.gantt.bars)
        #expect(en.gantt.windowStart == zh.gantt.windowStart)
    }
}
