import Foundation
import Testing
import KairoCore
import KairoCommands
import KairoPresentation
@testable import KairoMacApp

// F-14-10 Store 路由：setTaskStart 写意图起点 / setTaskFinish 折算持续时间、
// 非法结束日期拒绝（无撤销点、无数据变更）、一次编辑一步撤销、与画布拖拽互不合并。

@MainActor
@Suite("F-14-10 任务起止日期动作")
struct Sprint8TaskDateActionTests {
    private func makeStore() -> WorkspaceStore {
        let suite = "kairo.f1410.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return WorkspaceStore(defaults: defaults, seedsDemoData: true)
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        guard let date = Calendar.current.date(from: components) else {
            fatalError("测试日期构造失败：\(year)-\(month)-\(day)")
        }
        return date
    }

    private func task(_ store: WorkspaceStore, _ title: String) throws -> TaskItem {
        try #require(store.exportProject.tasks.first { $0.title == title })
    }

    private func task(_ store: WorkspaceStore, _ id: UUID) throws -> TaskItem {
        try #require(store.exportProject.tasks.first { $0.id == id })
    }

    private func row(_ store: WorkspaceStore, _ id: UUID) throws -> PlanRow {
        try #require(store.snapshot.outline.rows.first { $0.id == id })
    }

    /// 演示数据中无前置、无显式 startDate 的任务：排期起点 = 项目开始日。
    private func plainTask(_ store: WorkspaceStore) throws -> TaskItem {
        let candidate = try task(store, "整理用户反馈")
        #expect(candidate.dependencies.isEmpty)
        #expect(candidate.startDate == nil)
        return candidate
    }

    // MARK: - setTaskStart

    @Test func setTaskStartWritesIntentDate() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let target = makeDate(2025, 11, 2)

        store.dispatch(.setTaskStart(original.id, target))

        let updated = try task(store, original.id)
        #expect(updated.startDate == target)
        #expect(updated.durationDays == original.durationDays, "改开始不改持续时间")
    }

    @Test func setTaskStartWithNilClearsIntentDate() throws {
        let store = makeStore()
        let backend = try #require(store.exportProject.tasks.first { $0.startDate != nil })

        store.dispatch(.setTaskStart(backend.id, nil))

        #expect(try task(store, backend.id).startDate == nil)
    }

    /// AC-S8-01：归一只在 Store，绕过日历弹层传入带时分秒的值也落库为当天零点（M-6）。
    @Test func setTaskStartNormalizesToStartOfDay() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let lateNight = makeDate(2025, 11, 2, hour: 23).addingTimeInterval(30 * 60)

        store.dispatch(.setTaskStart(original.id, lateNight))

        #expect(try task(store, original.id).startDate == makeDate(2025, 11, 2))
    }

    @Test func setTaskStartDoesNotTouchDueDate() throws {
        let store = makeStore()
        let original = try plainTask(store)

        store.dispatch(.setTaskStart(original.id, makeDate(2025, 11, 2)))

        #expect(try task(store, original.id).dueDate == original.dueDate)
    }

    /// 群组由 UI 禁用编辑，Store 侧保持可写（与既有 setDueDate / setDuration 一致）。
    @Test func setTaskStartOnGroupIsNotBlockedByStore() throws {
        let store = makeStore()
        store.dispatch(.createTask(parentID: nil, kind: .group))
        let groupID = try #require(store.selection)
        let target = makeDate(2025, 11, 2)

        store.dispatch(.setTaskStart(groupID, target))

        #expect(try task(store, groupID).startDate == target)
        #expect(store.alertMessage == nil)
    }

    // MARK: - setTaskFinish

    @Test func setTaskFinishRewritesDurationAndKeepsStartDate() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        let start = try #require(backend.startDate)
        let startOfDay = ScheduleDateMath.startOfDay(start)
        let finish = try #require(Calendar.current.date(byAdding: .day, value: 5, to: startOfDay))

        store.dispatch(.setTaskFinish(backend.id, finish: finish, start: start))

        let updated = try task(store, backend.id)
        #expect(updated.durationDays == 5)
        #expect(updated.startDate == backend.startDate, "结束只折算持续时间，不动开始意图")
    }

    @Test func setTaskFinishMakesScheduledFinishMatchSelectedDay() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let scheduledStart = try #require(try row(store, original.id).scheduledStart)
        let finish = try #require(Calendar.current.date(byAdding: .day, value: 5, to: scheduledStart))

        store.dispatch(.setTaskFinish(original.id, finish: finish, start: scheduledStart))

        #expect(try row(store, original.id).scheduledFinish == finish)
    }

    @Test func setTaskFinishRejectsFinishEqualToStart() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let scheduledStart = try #require(try row(store, original.id).scheduledStart)
        let originalDuration = original.durationDays

        store.dispatch(.setTaskFinish(original.id, finish: scheduledStart, start: scheduledStart))

        #expect(store.alertMessage == I18n.t("alert.finish_after_start", "The finish date must be later than the start date"))
        #expect(try task(store, original.id).durationDays == originalDuration)
    }

    @Test func setTaskFinishRejectsFinishEarlierThanStart() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let scheduledStart = try #require(try row(store, original.id).scheduledStart)
        let earlier = try #require(Calendar.current.date(byAdding: .day, value: -2, to: scheduledStart))
        let originalDuration = original.durationDays

        store.dispatch(.setTaskFinish(original.id, finish: earlier, start: scheduledStart))

        #expect(store.alertMessage == I18n.t("alert.finish_after_start", "The finish date must be later than the start date"))
        #expect(try task(store, original.id).durationDays == originalDuration)
    }

    /// 非法路径在 update 之前返回：不产生撤销点，一次 undo 应撤掉上一笔合法改动。
    @Test func rejectedFinishDoesNotPushUndoPoint() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let originalStartDate = original.startDate
        let scheduledStart = try #require(try row(store, original.id).scheduledStart)
        let target = makeDate(2025, 11, 2)

        store.dispatch(.setTaskStart(original.id, target))
        #expect(try task(store, original.id).startDate == target)

        store.dispatch(.setTaskFinish(original.id, finish: scheduledStart, start: scheduledStart))
        #expect(store.alertMessage != nil)

        store.dispatch(.undo)
        #expect(try task(store, original.id).startDate == originalStartDate)
    }

    /// H-2：渲染快照到点击之间排期变化 → 传入的旧起点被拒绝，不写库、不产生撤销点。
    @Test func staleStartIsRejectedWithoutUndoPoint() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let staleStart = try #require(try row(store, original.id).scheduledStart)

        // 制造排期变化：项目开始日整体后移一周（等价于撤销/画布拖拽/外部合并造成的起点位移）。
        let shifted = try #require(Calendar.current.date(byAdding: .day, value: 7, to: staleStart))
        store.dispatch(.setProjectStart(shifted))
        let currentStart = try #require(try row(store, original.id).scheduledStart)
        #expect(ScheduleDateMath.dayOffset(from: staleStart, to: currentStart) == 7)

        let durationBefore = try task(store, original.id).durationDays
        let depthBefore = store.undoDepthForTesting
        let finish = try #require(Calendar.current.date(byAdding: .day, value: 5, to: staleStart))

        store.dispatch(.setTaskFinish(original.id, finish: finish, start: staleStart))

        #expect(store.alertMessage == I18n.t("alert.schedule_changed", "The schedule changed; pick the finish date again"))
        #expect(try task(store, original.id).durationDays == durationBefore, "陈旧起点不得折算落库")
        #expect(store.undoDepthForTesting == depthBefore, "拒绝路径不产生撤销点")

        // 撤销回退的是项目开始日，证明被拒绝的「结束」没有多插一步。
        store.dispatch(.undo)
        let restoredStart = try #require(try row(store, original.id).scheduledStart)
        #expect(ScheduleDateMath.dayOffset(from: staleStart, to: restoredStart) == 0)
    }

    @Test func rejectedFinishLeavesNoDraftOrNotice() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let scheduledStart = try #require(try row(store, original.id).scheduledStart)

        store.dispatch(.setTaskFinish(original.id, finish: scheduledStart, start: scheduledStart))

        #expect(store.alertMessage == I18n.t("alert.finish_after_start", "The finish date must be later than the start date"))
        #expect(store.notice == nil)
    }

    // MARK: - 撤销粒度

    /// AC-S8-09 a：单笔编辑恰好一步撤销。
    @Test func singleTaskStartEditIsOneUndoStep() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let target = makeDate(2025, 11, 2)
        let depthBefore = store.undoDepthForTesting

        store.dispatch(.setTaskStart(original.id, target))
        #expect(try task(store, original.id).startDate == target)
        #expect(store.undoDepthForTesting == depthBefore + 1)

        store.dispatch(.undo)
        #expect(try task(store, original.id).startDate == original.startDate)
        #expect(store.undoDepthForTesting == depthBefore)
    }

    /// 既有 pushUndo 合并规则：同字段 500ms 内两笔只占一步撤销（不是两笔各一步）。
    @Test func sameFieldEditsWithin500msMergeIntoOneStep() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let first = makeDate(2025, 11, 2)
        let second = makeDate(2025, 11, 9)
        let depthBefore = store.undoDepthForTesting

        store.dispatch(.setTaskStart(original.id, first))
        store.dispatch(.setTaskStart(original.id, second))
        #expect(try task(store, original.id).startDate == second)
        #expect(store.undoDepthForTesting == depthBefore + 1)

        store.dispatch(.undo)
        #expect(try task(store, original.id).startDate == original.startDate)
    }

    @Test func taskStartAndFinishEditsAreSeparateUndoSteps() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let target = makeDate(2025, 11, 2)

        store.dispatch(.setTaskStart(original.id, target))
        let scheduledStart = try #require(try row(store, original.id).scheduledStart)
        let finish = try #require(Calendar.current.date(byAdding: .day, value: 4, to: scheduledStart))
        store.dispatch(.setTaskFinish(original.id, finish: finish, start: scheduledStart))

        store.dispatch(.undo)
        #expect(try task(store, original.id).startDate == target, "第一步撤销只回退结束")
        #expect(try task(store, original.id).durationDays == original.durationDays)

        store.dispatch(.undo)
        #expect(try task(store, original.id).startDate == original.startDate, "第二步撤销回退开始")
    }

    @Test func taskStartEditDoesNotMergeWithCanvasMove() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let target = makeDate(2025, 11, 2)
        let canvasTarget = makeDate(2025, 12, 1)

        store.dispatch(.setTaskStart(original.id, target))
        store.dispatch(.canvasEditSchedule(original.id, startDate: canvasTarget, durationDays: nil))
        #expect(try task(store, original.id).startDate == canvasTarget)

        store.dispatch(.undo)
        #expect(try task(store, original.id).startDate == target, "检查器编辑与画布拖拽各自一步")
    }

    // MARK: - 快照透出

    @Test func inspectorSnapshotCarriesStartDate() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")

        store.dispatch(.select(backend.id))

        guard case .task(let inspector) = store.snapshot.inspector.content else {
            Issue.record("选中任务后检查器应显示任务页")
            return
        }
        #expect(inspector.startDate == backend.startDate)
    }

    @Test func inspectorSnapshotCarriesNilStartDateForGroup() throws {
        let store = makeStore()
        store.dispatch(.createTask(parentID: nil, kind: .group))
        let groupID = try #require(store.selection)
        store.dispatch(.createTask(parentID: groupID, kind: .task))
        store.dispatch(.select(groupID))

        guard case .task(let inspector) = store.snapshot.inspector.content else {
            Issue.record("选中群组后检查器应显示任务页")
            return
        }
        #expect(inspector.kind == .group)
        #expect(inspector.startDate == nil)
    }

    // MARK: - F-14-19 大纲日期列与检查器同源

    /// 大纲日期单元格与检查器日期行 dispatch 同一动作、同一合并键：
    /// - 大纲：`OutlineTable.swift:179`（开始）/ `:191-195`（结束，起点取同快照行的 `scheduledStart`）
    /// - 检查器：`InspectorView.swift:260` / `:276`
    ///
    /// 因此 `task-start-*` 与 `task-finish-*` 是两个合并键 ⇒ 各占一步撤销，一次 undo 只回滚
    /// 最近一笔；且结束以上一帧快照的起点折算不会命中「排期已变化」二次校验（设计 R2）。
    @Test func outlineDateCellCommitSharesInspectorActionAndUndoKeys() throws {
        let store = makeStore()
        let original = try plainTask(store)
        let depthBefore = store.undoDepthForTesting
        let target = makeDate(2025, 11, 2)

        // ① 大纲「开始」单元格提交（与检查器同一动作 `.setTaskStart`）。
        store.dispatch(.setTaskStart(original.id, target))
        #expect(try task(store, original.id).startDate == target)
        #expect(store.undoDepthForTesting == depthBefore + 1)

        // ② 大纲「结束」单元格提交：起点按接线取同一快照行（`row.scheduledStart`）。
        let scheduledStart = try #require(try row(store, original.id).scheduledStart)
        let finish = try #require(Calendar.current.date(byAdding: .day, value: 4, to: scheduledStart))
        store.dispatch(.setTaskFinish(original.id, finish: finish, start: scheduledStart))
        #expect(store.alertMessage == nil, "快照起点与 Store 判定同源，不应命中陈旧起点拦截")
        #expect(try row(store, original.id).scheduledFinish == finish)
        #expect(store.undoDepthForTesting == depthBefore + 2)

        // ③ 一次 undo 只回滚「结束」（开始/结束是两个合并键）。
        store.dispatch(.undo)
        #expect(try task(store, original.id).durationDays == original.durationDays)
        #expect(try task(store, original.id).startDate == target, "回滚结束不影响开始意图")
        #expect(store.undoDepthForTesting == depthBefore + 1)

        // ④ 再 undo 回滚「开始」。
        store.dispatch(.undo)
        #expect(try task(store, original.id).startDate == original.startDate)
        #expect(store.undoDepthForTesting == depthBefore)
    }

    /// 大纲开始列提供「清除」（`allowsClear: true`，设计 §2）：清除同样是一次编辑、一步撤销。
    @Test func outlineStartClearIsOneUndoStepRestoringIntentDate() throws {
        let store = makeStore()
        let backend = try task(store, "实现搜索后端")
        let originalStartDate = try #require(backend.startDate)
        let depthBefore = store.undoDepthForTesting

        store.dispatch(.setTaskStart(backend.id, nil))
        #expect(try task(store, backend.id).startDate == nil)
        #expect(store.undoDepthForTesting == depthBefore + 1)

        store.dispatch(.undo)
        #expect(try task(store, backend.id).startDate == originalStartDate)
        #expect(store.undoDepthForTesting == depthBefore)
    }
}
