# 327 条中文断言分类清单（F-0713）

> 归属：v0.9.0 / F-0713。基线：tag `v0.8.5`（08dc6ce）的 `Tests/`，与方案 [06-localization.md](./06-localization.md) §1 的 327 条同口径（行口径：含 `#expect` 且含中文字符的行）。
> 用途：F-0710 测试改造的工作底稿——每行给出「改不改、怎么改」，改造时逐条勾销。

## 0. 分类口径

方案 §8 的顺序是「能断言语义就不断言措辞；确实要测文案的，改为键存在 + 占位符一致」。落到 327 条上按下列**优先级**判定（先命中先归类）：

1. **中文只在失败提示里**（`#expect(expr, "…中文…")` 的第二参数）→ `应改语义`。断言对象与语言无关，中文只是给开发者看的诊断文本，不属于产品文案。
2. **中文是测试输入**（任务标题、备注、项目名、筛选项、人员名等用户数据）→ `应改语义`。方案 §2 已把用户数据列为非目标，断言比的是结构值，改造只需抽常量，不需跟译。
3. **期望值是日期/单位串**（`2026 年 11 月`、`3 天`、`12 点/天`）→ `需跟译`。必须变成「注入 Locale 后断言对应语言」或「契约输出改断 ISO」。
4. **其余期望值是界面文案**（`zoomLabel`、通知、错误文本、菜单名）→ `需跟译`。改为按语言取词，或断错误码 + 占位符个数。

三类之和必须 = 327，见 §6 自校验。

## 1. 应用层（KairoMacApp / WorkspaceStore）（187 条）

| # | 位置 | 用例 | 断言（摘要） | 分类 | 理由 |
|---|---|---|---|---|---|
| 1 | AppTests/AppPerformanceTests.swift:95 | thousandTaskActionsMeetBudget | `selectMS < 1000` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 2 | AppTests/AppPerformanceTests.swift:100 | thousandTaskActionsMeetBudget | `collapseMS < 1000` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 3 | AppTests/AppPerformanceTests.swift:105 | thousandTaskActionsMeetBudget | `zoomMS < 1000` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 4 | AppTests/AppPerformanceTests.swift:115 | scheduleRecomputeMeetsBudget | `elapsed < 1000` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 5 | AppTests/Sprint8DateFieldRenderTests.swift:223 | finishCalendarDisablesDaysAtOrBeforeStart | `!style.isSelectable` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 6 | AppTests/Sprint8DateFieldRenderTests.swift:307 | dayLabelsDescribeTodaySelectionAndBounds | `label == "11 月 6 日，星期五，今天，已选中，不可选"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 7 | AppTests/Sprint8DateFieldRenderTests.swift:316 | dayLabelsDescribeTodaySelectionAndBounds | `outside.hasPrefix("10 月 26 日，星期一")` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 8 | AppTests/Sprint8DateFieldRenderTests.swift:317 | dayLabelsDescribeTodaySelectionAndBounds | `outside.contains("不在本月")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 9 | AppTests/Sprint8DateFieldRenderTests.swift:319 | dayLabelsDescribeTodaySelectionAndBounds | `Display.monthTitle(date(2026, 11, 6), calendar: calendar) == "2026 年 11 月"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 10 | AppTests/Sprint8DateFieldRenderTests.swift:320 | dayLabelsDescribeTodaySelectionAndBounds | `Display.weekdaySymbols(calendar: calendar) == ["一", "二", "三", "四", "五", "六", "日"]` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 11 | AppTests/Sprint8DateFieldRenderTests.swift:420 | popoverPreviewFollowsCandidateDay | `short == "2026-11-06 – 2026-11-09 · 3 天"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 12 | AppTests/Sprint8DateFieldRenderTests.swift:421 | popoverPreviewFollowsCandidateDay | `long == "2026-11-06 – 2026-11-12 · 6 天"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 13 | AppTests/FormatUpgradeTests.swift:94 | fr_kairo_fmt_1_current_version_is_not_flagged | `store.notice?.contains("已升级") != true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 14 | AppTests/FormatUpgradeTests.swift:149 | fr_kairo_fmt_2_old_version_is_flagged_on_open | `store.exportProject.metadata.title == "旧版项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 15 | AppTests/FormatUpgradeTests.swift:152 | fr_kairo_fmt_2_old_version_is_flagged_on_open | `store.notice?.contains("已升级") != true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 16 | AppTests/FormatUpgradeTests.swift:169 | fr_kairo_fmt_5_save_after_upgrade_announces_once | `store.notice == "已升级到 v\(KairoFile.currentFormatVersion)"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 17 | AppTests/FormatUpgradeTests.swift:176 | fr_kairo_fmt_5_save_after_upgrade_announces_once | `store.notice?.contains("已升级") != true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 18 | AppTests/FormatUpgradeTests.swift:246 | fr_kairo_fmt_5_cancel_save_as_keeps_upgrade_flag | `store.notice?.contains("已升级") != true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 19 | AppTests/FormatUpgradeTests.swift:280 | fr_kairo_fmt_5_save_and_open_keeps_upgrade_notice | `store.notice == "已升级到 v\(KairoFile.currentFormatVersion)"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 20 | AppTests/FormatUpgradeTests.swift:325 | fr_kairo_fmt_5_save_and_open_load_failure_clears_pending_notice | `store.notice?.contains("已升级") != true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 21 | AppTests/FormatUpgradeTests.swift:326 | fr_kairo_fmt_5_save_and_open_load_failure_clears_pending_notice | `store.exportProject.metadata.title == "第三个项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 22 | AppTests/FormatUpgradeTests.swift:346 | fr_kairo_fmt_5_save_and_open_without_upgrade_has_no_upgrade_notice | `store.notice?.contains("已升级") != true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 23 | AppTests/FormatUpgradeTests.swift:385 | fr_kairo_fmt_5_save_and_open_merges_upgrade_notice_and_warning | `notice.contains("已升级到 v\(KairoFile.currentFormatVersion)")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 24 | AppTests/FormatUpgradeTests.swift:386 | fr_kairo_fmt_5_save_and_open_merges_upgrade_notice_and_warning | `notice.contains("已按群组处理")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 25 | AppTests/WorkspaceStoreTests.swift:94 | loadExampleConfirmsWhenDirty | `store.exportProject.metadata.title == "未保存标题"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 26 | AppTests/WorkspaceStoreTests.swift:99 | loadExampleConfirmsWhenDirty | `store.exportProject.metadata.title == "未保存标题"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 27 | AppTests/WorkspaceStoreTests.swift:125 | catalogIsSingleSourceForMenuAndPalette | `Set(commands.map(\.group)) == Set(["文件", "编辑", "大纲", "任务", "视图", "查找"])` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 28 | AppTests/WorkspaceStoreTests.swift:196 | paletteCommandOpensPaletteAndFiltersByAlias | `CommandPalette.matching("甘特", in: commands).map(\.id) == ["view.outline"]` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 29 | AppTests/WorkspaceStoreTests.swift:197 | paletteCommandOpensPaletteAndFiltersByAlias | `CommandPalette.matching("任务视图", in: commands).map(\.id) == ["view.plan"]` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 30 | AppTests/WorkspaceStoreTests.swift:199 | paletteCommandOpensPaletteAndFiltersByAlias | `CommandPalette.matching("不存在的命令", in: commands).isEmpty` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 31 | AppTests/WorkspaceStoreTests.swift:224 | indentAndOutdentMoveTaskThroughSession | `try task(store, "发布 v1.0").parentID == review.id` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 32 | AppTests/WorkspaceStoreTests.swift:225 | indentAndOutdentMoveTaskThroughSession | `try row(store, "发布 v1.0").depth == 1` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 33 | AppTests/WorkspaceStoreTests.swift:247 | dropTargetAppendsToGroupAndInsertsAfterSibling | `try task(store, "实现搜索后端").parentID == groupID` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 34 | AppTests/WorkspaceStoreTests.swift:274 | dropHoverAutoExpandsCollapsedGroup | `try !row(store, "新群组").isExpanded` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 35 | AppTests/WorkspaceStoreTests.swift:285 | dropHoverAutoExpandsCollapsedGroup | `try row(store, "新群组").isExpanded` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 36 | AppTests/WorkspaceStoreTests.swift:293 | dropExitCancelsPendingExpand | `try !row(store, "新群组").isExpanded` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 37 | AppTests/WorkspaceStoreTests.swift:299 | dropExitCancelsPendingExpand | `try !row(store, "新群组").isExpanded` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 38 | AppTests/WorkspaceStoreTests.swift:337 | createSiblingInsertsAfterSelectionAndSelectsIt | `created.title == "新任务"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 39 | AppTests/WorkspaceStoreTests.swift:352 | createTaskUsesExplicitParentAndSelectsIt | `created.title == "新任务"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 40 | AppTests/WorkspaceStoreTests.swift:353 | createTaskUsesExplicitParentAndSelectsIt | `try row(store, "新任务").depth == 1` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 41 | AppTests/WorkspaceStoreTests.swift:387 | addingChildPromotesParentAndDeleteCascades | `try task(store, "实现搜索后端").kind == .group` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 42 | AppTests/WorkspaceStoreTests.swift:388 | addingChildPromotesParentAndDeleteCascades | `try row(store, "实现搜索后端").kind == .group` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 43 | AppTests/WorkspaceStoreTests.swift:418 | progressAndStatusRefreshSnapshot | `try row(store, "实现搜索后端").progress == 0.25` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 44 | AppTests/WorkspaceStoreTests.swift:440 | dependencyCycleIsRejectedWithAlert | `try task(store, "实现搜索后端").dependencies.isEmpty` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 45 | AppTests/WorkspaceStoreTests.swift:471 | consecutiveRenamesMergeIntoOneUndoStep | `try task(store, "第二次改名").title == "第二次改名"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 46 | AppTests/WorkspaceStoreTests.swift:477 | consecutiveRenamesMergeIntoOneUndoStep | `try task(store, "第二次改名").title == "第二次改名"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 47 | AppTests/WorkspaceStoreTests.swift:508 | inspectorLockKeepsFrozenTaskWhileSelectionMoves | `store.snapshot.statusBar.selectionSummary == "Code Review 搜索模块"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 48 | AppTests/WorkspaceStoreTests.swift:532 | revealMissingTaskClearsSelectionAndNotifies | `store.notice == "任务已删除"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 49 | AppTests/WorkspaceStoreTests.swift:579 | dirtyOpenWaitsForUserChoice | `store.exportProject.metadata.title == "未保存标题"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 50 | AppTests/WorkspaceStoreTests.swift:583 | dirtyOpenWaitsForUserChoice | `store.exportProject.metadata.title == "未保存标题"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 51 | AppTests/WorkspaceStoreTests.swift:593 | dirtyOpenWaitsForUserChoice | `store.exportProject.metadata.title == "另一个项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 52 | AppTests/WorkspaceStoreTests.swift:625 | editsDuringAsyncOpenArePreserved | `store.exportProject.metadata.title == "载入期间编辑"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 53 | AppTests/WorkspaceStoreTests.swift:651 | openWhileLoadingIsReportedInsteadOfSilentlyDropped | `store.notice?.contains("正在载入") == true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 54 | AppTests/WorkspaceStoreTests.swift:660 | openWhileLoadingIsReportedInsteadOfSilentlyDropped | `store.exportProject.metadata.title == "第一个项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 55 | AppTests/WorkspaceStoreTests.swift:706 | exportDuringEditFallsBackToDirectSave | `reloaded.exportProject.metadata.title == "面板打开后修改"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 56 | AppTests/WorkspaceStoreTests.swift:737 | selectingElsewhereRestoresTemporarilySuspendedFilter | `store.viewState.filterText == "发布"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 57 | AppTests/WorkspaceStoreTests.swift:744 | selectingElsewhereRestoresTemporarilySuspendedFilter | `store.viewState.filterText == "发布"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 58 | AppTests/WorkspaceStoreTests.swift:929 | predecessorColumnReportsHiddenOrUnknownNumber | `store.alertMessage?.contains("可能被折叠或筛选隐藏") == true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 59 | AppTests/WorkspaceStoreTests.swift:937 | predecessorColumnReportsHiddenOrUnknownNumber | `store.alertMessage?.contains("可能被折叠或筛选隐藏") == true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 60 | AppTests/WorkspaceStoreTests.swift:981 | predecessorColumnRejectsCycleAndUnknownID | `store.alertMessage?.contains("环") == true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 61 | AppTests/WorkspaceStoreTests.swift:990 | predecessorColumnRejectsCycleAndUnknownID | `store.alertMessage?.contains("找不到") == true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 62 | AppTests/WorkspaceStoreTests.swift:993 | predecessorColumnRejectsCycleAndUnknownID | `store.alertMessage?.contains("自身") == true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 63 | AppTests/WorkspaceStoreTests.swift:1014 | externalChangeWithUnsavedEditsShowsBanner | `store.exportProject.metadata.title == "未命名项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 64 | AppTests/WorkspaceStoreTests.swift:1036 | externalChangeWithoutLocalEditsReloadsAutomatically | `store.exportProject.metadata.title == "外部标题"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 65 | AppTests/WorkspaceStoreTests.swift:1037 | externalChangeWithoutLocalEditsReloadsAutomatically | `store.notice?.hasPrefix("已载入外部更新") == true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 66 | AppTests/WorkspaceStoreTests.swift:1077 | setOutlineColumnWidthClampsToPerColumnRange | `store.viewState.outlineColumnWidths["start"] == 320` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 67 | AppTests/WorkspaceStoreTests.swift:1103 | setOutlineColumnWidthNilOrNonFiniteClearsOverride | `store.viewState.outlineColumnWidths["start"] == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 68 | AppTests/WorkspaceStoreTests.swift:1107 | setOutlineColumnWidthNilOrNonFiniteClearsOverride | `store.viewState.outlineColumnWidths["finish"] == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 69 | AppTests/WorkspaceStoreTests.swift:1111 | setOutlineColumnWidthNilOrNonFiniteClearsOverride | `store.viewState.outlineColumnWidths["duration"] == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 70 | AppTests/WorkspaceStoreTests.swift:1122 | outlineColumnActionsDoNotPushUndoPoints | `store.undoDepthForTesting == depthBefore` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 71 | AppTests/WorkspaceStoreTests.swift:1126 | outlineColumnActionsDoNotPushUndoPoints | `store.undoDepthForTesting == depthBefore` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 72 | AppTests/WorkspaceStoreTests.swift:1129 | outlineColumnActionsDoNotPushUndoPoints | `store.undoDepthForTesting == depthBefore` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 73 | AppTests/WorkspaceStoreTests.swift:1130 | outlineColumnActionsDoNotPushUndoPoints | `store.hasUnsavedChanges == dirtyBefore` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 74 | AppTests/WorkspaceStoreTests.swift:1137 | setOutlineColumnWidthRejectsFlexibleTitleColumn | `store.viewState.outlineColumnWidths["title"] == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 75 | AppTests/WorkspaceStoreTests.swift:1148 | toggleOutlineColumnFlipsHiddenAndRejectsFixedColumns | `store.viewState.hiddenOutlineColumns.isEmpty` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 76 | AppTests/WorkspaceStoreTests.swift:1160 | toggleOutlineColumnFlipsHiddenAndRejectsFixedColumns | `store.viewState.hiddenOutlineColumns == ["progress"]` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 77 | AppTests/WorkspaceStoreTests.swift:1166 | snapshotColumnsFollowHiddenPreferences | `store.viewState.outlineWidth == 600` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 78 | AppTests/WorkspaceStoreTests.swift:1172 | snapshotColumnsFollowHiddenPreferences | `store.snapshot.outline.columns.contains(.finish)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 79 | AppTests/WorkspaceStoreTests.swift:1173 | snapshotColumnsFollowHiddenPreferences | `store.snapshot.outline.columns.contains(.number)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 80 | AppTests/WorkspaceStoreTests.swift:1176 | snapshotColumnsFollowHiddenPreferences | `store.snapshot.outline.columns.contains(.number)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 81 | AppTests/WorkspaceStoreTests.swift:1179 | snapshotColumnsFollowHiddenPreferences | `store.snapshot.outline.columns.contains(.start)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 82 | AppTests/WorkspaceStoreTests.swift:1187 | outlineColumnCommandsToggleFromCatalog | `try command(commands, "view.outlineColumn.start").title == "显示/隐藏开始列"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 83 | AppTests/WorkspaceStoreTests.swift:1188 | outlineColumnCommandsToggleFromCatalog | `!commands.contains { $0.id == "view.outlineColumn.number" }` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 84 | AppTests/WorkspaceStoreTests.swift:1189 | outlineColumnCommandsToggleFromCatalog | `!commands.contains { $0.id == "view.outlineColumn.title" }` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 85 | AppTests/WorkspaceStoreTests.swift:1240 | corruptedOutlineColumnWidthsFallBackWithoutTouchingOtherPreferences | `store.viewState.outlineColumnWidths.isEmpty` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 86 | AppTests/OutlineAlignmentTests.swift:54 | outlineRowsListHeightMatchesTimelinePitch | `measured == expected` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 87 | AppTests/DayWidthPerformanceTests.swift:73 | makeFixture | `store.snapshot.outline.rows.count == 1000` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 88 | AppTests/Sprint8TaskDateActionTests.swift:64 | setTaskStartWritesIntentDate | `updated.durationDays == original.durationDays` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 89 | AppTests/Sprint8TaskDateActionTests.swift:122 | setTaskFinishRewritesDurationAndKeepsStartDate | `updated.startDate == backend.startDate` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 90 | AppTests/Sprint8TaskDateActionTests.swift:144 | setTaskFinishRejectsFinishEqualToStart | `store.alertMessage == "结束日期必须晚于开始日期"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 91 | AppTests/Sprint8TaskDateActionTests.swift:157 | setTaskFinishRejectsFinishEarlierThanStart | `store.alertMessage == "结束日期必须晚于开始日期"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 92 | AppTests/Sprint8TaskDateActionTests.swift:197 | staleStartIsRejectedWithoutUndoPoint | `store.alertMessage == "排期已变化，请重新选择结束日期"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 93 | AppTests/Sprint8TaskDateActionTests.swift:198 | staleStartIsRejectedWithoutUndoPoint | `try task(store, original.id).durationDays == durationBefore` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 94 | AppTests/Sprint8TaskDateActionTests.swift:199 | staleStartIsRejectedWithoutUndoPoint | `store.undoDepthForTesting == depthBefore` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 95 | AppTests/Sprint8TaskDateActionTests.swift:214 | rejectedFinishLeavesNoDraftOrNotice | `store.alertMessage == "结束日期必须晚于开始日期"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 96 | AppTests/Sprint8TaskDateActionTests.swift:264 | taskStartAndFinishEditsAreSeparateUndoSteps | `try task(store, original.id).startDate == target` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 97 | AppTests/Sprint8TaskDateActionTests.swift:268 | taskStartAndFinishEditsAreSeparateUndoSteps | `try task(store, original.id).startDate == original.startDate` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 98 | AppTests/Sprint8TaskDateActionTests.swift:282 | taskStartEditDoesNotMergeWithCanvasMove | `try task(store, original.id).startDate == target` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 99 | AppTests/Sprint8TaskDateActionTests.swift:338 | outlineDateCellCommitSharesInspectorActionAndUndoKeys | `store.alertMessage == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 100 | AppTests/Sprint8TaskDateActionTests.swift:345 | outlineDateCellCommitSharesInspectorActionAndUndoKeys | `try task(store, original.id).startDate == target` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 101 | AppTests/Sprint7DebtTests.swift:59 | dayWidthCommitReusesScheduleCache | `afterOpen >= 1` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 102 | AppTests/Sprint7DebtTests.swift:71 | dayWidthCommitReusesScheduleCache | `session.scheduleComputeCount == afterOpen + 1` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 103 | AppTests/Sprint7DebtTests.swift:94 | missingSingleFieldKeepsOtherPreferences | `store.viewState.inspectorTab == .inspector` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 104 | AppTests/Sprint7DebtTests.swift:110 | corruptedFieldTypeDegradesGracefully | `store.viewState.outlineWidth == 600` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 105 | AppTests/HorizontalPanContextTests.swift:83 | applyScrollDispatchesWholeDayPan | `movedDays == 3` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 106 | AppTests/Sprint8DateAcceptanceTests.swift:123 | startEditWritesStartDateAtStartOfDay | `try task(store, a).durationDays == 3` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 107 | AppTests/Sprint8DateAcceptanceTests.swift:125 | startEditWritesStartDateAtStartOfDay | `try taskInspector(store).startDate == localDay(2026, 11, 6)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 108 | AppTests/Sprint8DateAcceptanceTests.swift:141 | startDateWithTimeComponentSchedulesAtStartOfDay | `try row(store, a).scheduledStart == localDay(2026, 11, 6)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 109 | AppTests/Sprint8DateAcceptanceTests.swift:161 | futureStartDateMovesScheduledStartAndGanttBar | `abs(beforeA.x) < 0.001` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 110 | AppTests/Sprint8DateAcceptanceTests.swift:169 | futureStartDateMovesScheduledStartAndGanttBar | `try row(store, a).scheduledFinish == localDay(2026, 11, 9)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 111 | AppTests/Sprint8DateAcceptanceTests.swift:170 | futureStartDateMovesScheduledStartAndGanttBar | `try row(store, b).scheduledStart == localDay(2026, 11, 9)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 112 | AppTests/Sprint8DateAcceptanceTests.swift:173 | futureStartDateMovesScheduledStartAndGanttBar | `store.snapshot.gantt.dayWidth == dayWidth` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 113 | AppTests/Sprint8DateAcceptanceTests.swift:175 | futureStartDateMovesScheduledStartAndGanttBar | `abs((afterA.x - beforeA.x) - 4 * dayWidth) < 0.001` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 114 | AppTests/Sprint8DateAcceptanceTests.swift:176 | futureStartDateMovesScheduledStartAndGanttBar | `abs(afterA.width - beforeA.width) < 0.001` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 115 | AppTests/Sprint8DateAcceptanceTests.swift:187 | startDateEarlierThanAnchorDoesNotPullScheduleBack | `try task(store, a).startDate == localDay(2026, 10, 20)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 116 | AppTests/Sprint8DateAcceptanceTests.swift:188 | startDateEarlierThanAnchorDoesNotPullScheduleBack | `try row(store, a).scheduledStart == localDay(2026, 11, 2)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 117 | AppTests/Sprint8DateAcceptanceTests.swift:189 | startDateEarlierThanAnchorDoesNotPullScheduleBack | `try row(store, b).scheduledStart == localDay(2026, 11, 5)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 118 | AppTests/Sprint8DateAcceptanceTests.swift:191 | startDateEarlierThanAnchorDoesNotPullScheduleBack | `abs(after.x - before.x) < 0.001` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 119 | AppTests/Sprint8DateAcceptanceTests.swift:225 | finishCalendarDisablesDaysBeforeMinimumFinish | `disabled.contains(S8Fixture.day(2026, 11, 6, in: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 120 | AppTests/Sprint8DateAcceptanceTests.swift:226 | finishCalendarDisablesDaysBeforeMinimumFinish | `disabled.contains(S8Fixture.day(2026, 11, 5, in: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 121 | AppTests/Sprint8DateAcceptanceTests.swift:227 | finishCalendarDisablesDaysBeforeMinimumFinish | `enabled.contains(minimum)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 122 | AppTests/Sprint8DateAcceptanceTests.swift:228 | finishCalendarDisablesDaysBeforeMinimumFinish | `disabled.allSatisfy { $0 <= start }` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 123 | AppTests/Sprint8DateAcceptanceTests.swift:230 | finishCalendarDisablesDaysBeforeMinimumFinish | `!disabled.isEmpty && !enabled.isEmpty` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 124 | AppTests/Sprint8DateAcceptanceTests.swift:243 | finishNotAfterStartIsRejectedWithoutUndo | `store.alertMessage == "结束日期必须晚于开始日期"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 125 | AppTests/Sprint8DateAcceptanceTests.swift:246 | finishNotAfterStartIsRejectedWithoutUndo | `store.notice == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 126 | AppTests/Sprint8DateAcceptanceTests.swift:252 | finishNotAfterStartIsRejectedWithoutUndo | `store.alertMessage == "结束日期必须晚于开始日期"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 127 | AppTests/Sprint8DateAcceptanceTests.swift:274 | finishEditRewritesDurationOnlyAndScheduledFinishMatches | `updated.durationDays == 6` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 128 | AppTests/Sprint8DateAcceptanceTests.swift:278 | finishEditRewritesDurationOnlyAndScheduledFinishMatches | `try row(store, a).scheduledFinish == localDay(2026, 11, 12)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 129 | AppTests/Sprint8DateAcceptanceTests.swift:323 | calendarGridMarksAdjacentMonthDaysAndWeekends | `grid.days.filter { grid.isInMonth($0) }.count == 30` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 130 | AppTests/Sprint8DateAcceptanceTests.swift:324 | calendarGridMarksAdjacentMonthDaysAndWeekends | `outside.count == 12` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 131 | AppTests/Sprint8DateAcceptanceTests.swift:327 | calendarGridMarksAdjacentMonthDaysAndWeekends | `outside.contains(S8Fixture.day(2026, 10, 31, in: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 132 | AppTests/Sprint8DateAcceptanceTests.swift:329 | calendarGridMarksAdjacentMonthDaysAndWeekends | `grid.isWeekend(S8Fixture.day(2026, 11, 7, in: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 133 | AppTests/Sprint8DateAcceptanceTests.swift:330 | calendarGridMarksAdjacentMonthDaysAndWeekends | `grid.isWeekend(S8Fixture.day(2026, 11, 8, in: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 134 | AppTests/Sprint8DateAcceptanceTests.swift:331 | calendarGridMarksAdjacentMonthDaysAndWeekends | `!grid.isWeekend(S8Fixture.day(2026, 11, 6, in: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 135 | AppTests/Sprint8DateAcceptanceTests.swift:345 | calendarGridMonthNavigationCrossesYearBoundary | `december.days.first == S8Fixture.day(2026, 11, 30, in: calendar)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 136 | AppTests/Sprint8DateAcceptanceTests.swift:355 | calendarGridMonthNavigationCrossesYearBoundary | `january.month(offsetBy: -2).days == november.days` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 137 | AppTests/Sprint8DateAcceptanceTests.swift:381 | eachDateEditIsOneUndoStep | `try row(store, a).scheduledStart == localDay(2026, 11, 2)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 138 | AppTests/Sprint8DateAcceptanceTests.swift:396 | sameFieldEditsWithin500msMergeIntoOneStep | `elapsed < 0.5` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 139 | AppTests/Sprint8DateAcceptanceTests.swift:399 | sameFieldEditsWithin500msMergeIntoOneStep | `try task(store, a).startDate == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 140 | AppTests/Sprint8DateAcceptanceTests.swift:411 | crossFieldEditsDoNotMerge | `try task(store, a).durationDays == 3` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 141 | AppTests/Sprint8DateAcceptanceTests.swift:415 | crossFieldEditsDoNotMerge | `try task(store, a).startDate == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 142 | AppTests/Sprint8DateAcceptanceTests.swift:426 | inspectorEditDoesNotMergeWithCanvasMove | `try task(store, a).startDate == localDay(2026, 11, 6)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 143 | AppTests/Sprint8DateAcceptanceTests.swift:447 | dueDateEditStillWritesDueDateOnly | `try row(store, a).scheduledFinish == scheduledFinish` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 144 | AppTests/Sprint8DateAcceptanceTests.swift:492 | taskStartEditWithoutProjectAnchorShiftsTimeline | `try row(store, id).scheduledStart != nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 145 | AppTests/Sprint8DateAcceptanceTests.swift:499 | taskStartEditWithoutProjectAnchorShiftsTimeline | `store.snapshot.gantt.projectStartDerived` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 146 | AppTests/Sprint8DateAcceptanceTests.swift:509 | finishEditDoesNotBlockOnViolations | `violationsBefore > 0` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 147 | AppTests/Sprint8DateAcceptanceTests.swift:515 | finishEditDoesNotBlockOnViolations | `store.alertMessage == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 148 | AppTests/Sprint8DateAcceptanceTests.swift:516 | finishEditDoesNotBlockOnViolations | `try task(store, a).durationDays == 6` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 149 | AppTests/Sprint8DateAcceptanceTests.swift:531 | calendarQuickActionOrderMatchesRuling | `DateQuickAction.allCases.map(\.title) == ["今天", "下周一", "+1 周"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 150 | AppTests/Sprint8DateAcceptanceTests.swift:578 | staleStartFinishIsRejectedWithoutUndo | `staleStart == localDay(2026, 11, 2)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 151 | AppTests/Sprint8DateAcceptanceTests.swift:589 | staleStartFinishIsRejectedWithoutUndo | `store.alertMessage == "排期已变化，请重新选择结束日期"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 152 | AppTests/Sprint8DateAcceptanceTests.swift:590 | staleStartFinishIsRejectedWithoutUndo | `try task(store, a).durationDays == duration` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 153 | AppTests/Sprint8DateAcceptanceTests.swift:591 | staleStartFinishIsRejectedWithoutUndo | `try row(store, a).scheduledFinish == scheduledFinish` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 154 | AppTests/HorizontalScrollMonitorTests.swift:67 | startingSecondMonitorTakesOverFromFirst | `!first.isRunning` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 155 | AppTests/HorizontalScrollMonitorTests.swift:127 | horizontalScrollInsideCanvasIsConsumed | `swallowed == nil` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 156 | AppTests/DayWidthControlTests.swift:44 | setCustomDayWidthStoresClampedValueAndLeavesFitMode | `store.snapshot.statusBar.zoomLabel == "自定义"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 157 | AppTests/SaveAsTests.swift:64 | fr_file_saveas_1_catalog_defines_command | `saveAs.title == "另存为…"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 158 | AppTests/SaveAsTests.swift:65 | fr_file_saveas_1_catalog_defines_command | `saveAs.group == "文件"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 159 | AppTests/SaveAsTests.swift:67 | fr_file_saveas_1_catalog_defines_command | `saveAs.aliases.contains("保存副本")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 160 | AppTests/SaveAsTests.swift:69 | fr_file_saveas_1_catalog_defines_command | `CommandPalette.matching("另存为", in: commands).contains { $0.id == "file.saveAs" }` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 161 | AppTests/SaveAsTests.swift:70 | fr_file_saveas_1_catalog_defines_command | `CommandPalette.matching("保存副本", in: commands).contains { $0.id == "file.saveAs" }` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 162 | AppTests/SaveAsTests.swift:108 | fr_file_saveas_2_trims_trailing_replacement_hyphen | `SaveFilenameSuggestion.suggest(currentURL: nil, title: "季度/") == "季度.kairo"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 163 | AppTests/SaveAsTests.swift:109 | fr_file_saveas_2_trims_trailing_replacement_hyphen | `SaveFilenameSuggestion.suggest(currentURL: nil, title: "季度 - ") == "季度.kairo"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 164 | AppTests/SaveAsTests.swift:133 | fr_file_saveas_2_caps_filename_at_200_utf8_bytes | `fromTitle == String(repeating: "计", count: 64) + ".kairo"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 165 | AppTests/SaveAsTests.swift:140 | fr_file_saveas_2_caps_filename_at_200_utf8_bytes | `fromURL == String(repeating: "计", count: 64) + ".kairo"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 166 | AppTests/SaveAsTests.swift:177 | fr_file_saveas_2_store_suggests_filename | `store.suggestedSaveFilename == "未命名项目.kairo"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 167 | AppTests/SaveAsTests.swift:180 | fr_file_saveas_2_store_suggests_filename | `store.suggestedSaveFilename == "路线 - 图.kairo"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 168 | AppTests/SaveAsTests.swift:184 | fr_file_saveas_2_store_suggests_filename | `store.suggestedSaveFilename == "已有.kairo"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 169 | AppTests/SaveAsTests.swift:209 | fr_file_saveas_2_new_file_uses_current_format_version | `reopened.metadata.title == "格式版本检查"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 170 | AppTests/SaveAsTests.swift:270 | fr_file_saveas_4_points_project_url_and_clears_dirty | `try KairoFile.load(from: newURL).metadata.title == "另存后再修改"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 171 | AppTests/SaveAsTests.swift:294 | fr_file_saveas_4_external_change_to_old_path_is_ignored | `store.notice?.hasPrefix("已载入外部更新") != true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 172 | AppTests/SaveAsTests.swift:297 | fr_file_saveas_4_external_change_to_old_path_is_ignored | `try KairoFile.load(from: originalURL).metadata.title == "旧文件被外部改写"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 173 | AppTests/SaveAsTests.swift:318 | fr_file_saveas_5_confirms_latest_edits | `try KairoFile.load(from: newURL).metadata.title == "面板打开期间的编辑"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 174 | AppTests/SaveAsTests.swift:344 | fr_file_saveas_6_cancel_preserves_state | `store.exportProject.metadata.title == "面板中修改"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 175 | AppTests/SaveAsTests.swift:399 | fr_file_saveas_6_cancel_forces_direct_write_branch | `try KairoFile.load(from: newURL).metadata.title == "取消后直接保存"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 176 | AppTests/GanttCanvasEditTests.swift:48 | moveUpdatesStartDateOnly | `updated.durationDays == original.durationDays` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 177 | AppTests/GanttCanvasEditTests.swift:61 | resizeEndUpdatesDurationOnly | `updated.startDate == original.startDate` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 178 | AppTests/GanttCanvasEditTests.swift:84 | resizeStartKeepsFinishDate | `updatedFinish == originalFinish` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 179 | AppTests/DayWidthUxAcceptanceTests.swift:58 | slidesInsideThrottleWindowCommitTrailingValueOnly | `store.viewState.customDayWidth != 45` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 180 | AppTests/DayWidthUxAcceptanceTests.swift:131 | panelRendersAtBoundaryDayWidths | `rendered.distinctColorCount > 5` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 181 | AppTests/DayWidthUxAcceptanceTests.swift:143 | zoomDetailHandlesNonFiniteValuesWithoutCrashing | `WorkspacePresenter.zoomDetail(dayWidth: 1e16).hasSuffix("点/天")` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 182 | AppTests/OutlineColumnLayoutTests.swift:65 | defaultWidthsAt360PointMatchLegacyCompression | `layout.width(of: .title) >= 120` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 183 | AppTests/OutlineColumnLayoutTests.swift:66 | defaultWidthsAt360PointMatchLegacyCompression | `abs(layout.width(of: .title) + fixed - 360) < 0.001` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 184 | AppTests/OutlineColumnLayoutTests.swift:127 | liveResizeBeatsWidthOverride | `layout.width(of: .start) == 90` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 185 | AppTests/OutlineColumnLayoutTests.swift:128 | liveResizeBeatsWidthOverride | `layout.width(of: .title) == 252` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 186 | AppTests/OutlineColumnLayoutTests.swift:140 | liveResizeAffectsOnlyItsColumnAndClampsNegative | `other.width(of: .start) == 200` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 187 | AppTests/OutlineColumnLayoutTests.swift:148 | liveResizeAffectsOnlyItsColumnAndClampsNegative | `negative.width(of: .start) == 0` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |

## 2. 呈现层（KairoPresentation）（81 条）

| # | 位置 | 用例 | 断言（摘要） | 分类 | 理由 |
|---|---|---|---|---|---|
| 1 | KairoPresentationTests/OutlineDateEditingTests.swift:146 | startColumnIsDisabledForGroupRow | `!reason.isEmpty` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 2 | KairoPresentationTests/OutlineDateEditingTests.swift:160 | finishColumnIsEnabledForScheduledTaskWithNextDayMinimum | `minimum == makeDay(2025, 10, 21)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 3 | KairoPresentationTests/OutlineDateEditingTests.swift:177 | finishMinimumDateIsNextDayMidnightForSubDayStart | `utc.startOfDay(for: minimum ?? .distantPast) == minimum` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 4 | KairoPresentationTests/OutlineDateEditingTests.swift:336 | finishCommitKeepsChosenFinishAndSnapshotStart | `commit.finish == finish` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 5 | KairoPresentationTests/OutlineDateEditingTests.swift:337 | finishCommitKeepsChosenFinishAndSnapshotStart | `commit.start == makeDay(2025, 10, 20)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 6 | KairoPresentationTests/OutlineDateEditingTests.swift:362 | nonDateColumnsAreNeverGated | `nonDateColumns.count == 8` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 7 | KairoPresentationTests/OutlineDateEditingTests.swift:384 | enabledMatchesReasonPresence | `enabled == (reason == nil)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 8 | KairoPresentationTests/OutlineDateEditingTests.swift:400 | finishMinimumDateSpansEndOfDSTDayInBerlin | `minimum == makeDay(2025, 10, 27, in: berlin)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 9 | KairoPresentationTests/OutlineDateEditingTests.swift:401 | finishMinimumDateSpansEndOfDSTDayInBerlin | `berlin.startOfDay(for: minimum ?? .distantPast) == minimum` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 10 | KairoPresentationTests/OutlineDateEditingTests.swift:443 | finishMinimumDateUsesInjectedCalendar | `inBerlin != inUTC` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 11 | KairoPresentationTests/OutlineDateEditingTests.swift:445 | finishMinimumDateUsesInjectedCalendar | `clock.hour == 0 && clock.minute == 0` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 12 | KairoPresentationTests/DayWidthAcceptanceTests.swift:337 | dayWidthGridCoversTicksBandsAndBars | `!gantt.bands.isEmpty` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 13 | KairoPresentationTests/DayWidthAcceptanceTests.swift:343 | dayWidthGridCoversTicksBandsAndBars | `abs(band.width - width) < 1e-6` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 14 | KairoPresentationTests/DayWidthAcceptanceTests.swift:354 | dayWidthGridCoversTicksBandsAndBars | `abs(bar.x - days * width) < 1e-6` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 15 | KairoPresentationTests/DayWidthAcceptanceTests.swift:410 | dayGranularityKeepsAdjacentTickSpacingEqualToDayWidth | `abs(xs[0]) < 1e-9` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 16 | KairoPresentationTests/DayWidthAcceptanceTests.swift:445 | weekGranularityKeepsAdjacentTickSpacingSevenDayWidths | `abs(span - 7) < 1e-6` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 17 | KairoPresentationTests/DayWidthAcceptanceTests.swift:471 | monthGranularityKeepsAdjacentTickSpacingWithinOneMonthSpan | `days >= 28 && days <= 31` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 18 | KairoPresentationTests/DayWidthAcceptanceTests.swift:501 | presetZoomUsesPresetDayWidthAndSelfConsistentGranularity | `gantt.dayWidth == preset.width` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 19 | KairoPresentationTests/DayWidthAcceptanceTests.swift:536 | customDayWidthOverridesFitZoomAndFitModeUsesFitWidth | `custom.usesFitZoom == false` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 20 | KairoPresentationTests/DayWidthAcceptanceTests.swift:552 | customDayWidthOverridesFitZoomAndFitModeUsesFitWidth | `fit.dayWidth > 10 && fit.dayWidth < 10.2` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 21 | KairoPresentationTests/DayWidthAcceptanceTests.swift:554 | customDayWidthOverridesFitZoomAndFitModeUsesFitWidth | `fit.tickGranularity == .week` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 22 | KairoPresentationTests/DayWidthAcceptanceTests.swift:555 | customDayWidthOverridesFitZoomAndFitModeUsesFitWidth | `fit.zoom == .week` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 23 | KairoPresentationTests/DayWidthAcceptanceTests.swift:571 | outOfRangeCustomDayWidthIsClampedAndNeverIllegal | `GanttScale.clampDayWidth(12.5) == 12.5` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 24 | KairoPresentationTests/DayWidthAcceptanceTests.swift:588 | outOfRangeCustomDayWidthIsClampedAndNeverIllegal | `gantt.dayWidth.isFinite` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 25 | KairoPresentationTests/DayWidthAcceptanceTests.swift:589 | outOfRangeCustomDayWidthIsClampedAndNeverIllegal | `gantt.dayWidth > 0` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 26 | KairoPresentationTests/DayWidthAcceptanceTests.swift:620 | tinyDayWidthKeepsTickCountsAndWindowBounded | `gantt.tickGranularity == .month` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 27 | KairoPresentationTests/DayWidthAcceptanceTests.swift:627 | tinyDayWidthKeepsTickCountsAndWindowBounded | `gantt.ticks.count <= 64` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 28 | KairoPresentationTests/DayWidthAcceptanceTests.swift:628 | tinyDayWidthKeepsTickCountsAndWindowBounded | `gantt.ticks.count <= 200` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 29 | KairoPresentationTests/DayWidthAcceptanceTests.swift:629 | tinyDayWidthKeepsTickCountsAndWindowBounded | `Double(gantt.ticks.count) <= windowDays(gantt) / 10` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 30 | KairoPresentationTests/DayWidthAcceptanceTests.swift:630 | tinyDayWidthKeepsTickCountsAndWindowBounded | `gantt.bands.isEmpty` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 31 | KairoPresentationTests/DayWidthAcceptanceTests.swift:662 | statusBarReportsZoomLabelAndActualDayWidth | `custom.zoomLabel == "自定义"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 32 | KairoPresentationTests/DayWidthAcceptanceTests.swift:663 | statusBarReportsZoomLabelAndActualDayWidth | `custom.zoomDetail == "20 点/天"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 33 | KairoPresentationTests/DayWidthAcceptanceTests.swift:666 | statusBarReportsZoomLabelAndActualDayWidth | `fractional.zoomLabel == "自定义"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 34 | KairoPresentationTests/DayWidthAcceptanceTests.swift:667 | statusBarReportsZoomLabelAndActualDayWidth | `fractional.zoomDetail == "12.5 点/天"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 35 | KairoPresentationTests/DayWidthAcceptanceTests.swift:675 | statusBarReportsZoomLabelAndActualDayWidth | `preset.zoomLabel == "日"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 36 | KairoPresentationTests/DayWidthAcceptanceTests.swift:692 | statusBarReportsZoomLabelAndActualDayWidth | `fit.zoomLabel == "适合项目"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 37 | KairoPresentationTests/DayWidthAcceptanceTests.swift:694 | statusBarReportsZoomLabelAndActualDayWidth | `abs(detail - fitGantt.dayWidth) < 0.051` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 38 | KairoPresentationTests/DayWidthAcceptanceTests.swift:717 | presetModeKeepsPresetWidthGranularityAndMatchesCoreReference | `gantt.dayWidth == preset.width` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 39 | KairoPresentationTests/DayWidthAcceptanceTests.swift:729 | presetModeKeepsPresetWidthGranularityAndMatchesCoreReference | `lower.count >= 20` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 40 | KairoPresentationTests/DayWidthAcceptanceTests.swift:744 | presetModeKeepsPresetWidthGranularityAndMatchesCoreReference | `gantt.bands.isEmpty` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 41 | KairoPresentationTests/DayWidthAcceptanceTests.swift:775 | fitModeKeepsPresetGranularityAndMatchesCoreReference | `discriminating` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 42 | KairoPresentationTests/DayWidthAcceptanceTests.swift:787 | fitModeKeepsPresetGranularityAndMatchesCoreReference | `gantt.usesFitZoom == true` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 43 | KairoPresentationTests/DayWidthAcceptanceTests.swift:788 | fitModeKeepsPresetGranularityAndMatchesCoreReference | `gantt.zoom == zoom` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 44 | KairoPresentationTests/DayWidthAcceptanceTests.swift:843 | fitModeGranularityIsInvariantToViewportWidth | `Set(granularities).count == 1` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 45 | KairoPresentationTests/DayWidthAcceptanceTests.swift:880 | customModeDerivesGranularityFromEffectiveDayWidth | `gantt.zoom == .week` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 46 | KairoPresentationTests/DayWidthAcceptanceTests.swift:893 | customModeDerivesGranularityFromEffectiveDayWidth | `granularityAt(17.99) != granularityAt(18)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 47 | KairoPresentationTests/DayWidthAcceptanceTests.swift:894 | customModeDerivesGranularityFromEffectiveDayWidth | `granularityAt(5.99) != granularityAt(6)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 48 | KairoPresentationTests/DayWidthAcceptanceTests.swift:910 | customModeWidthAndGranularityWinOverFit | `gantt.dayWidth == item.width` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 49 | KairoPresentationTests/DayWidthAcceptanceTests.swift:911 | customModeWidthAndGranularityWinOverFit | `gantt.usesFitZoom == false` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 50 | KairoPresentationTests/DayWidthAcceptanceTests.swift:916 | customModeWidthAndGranularityWinOverFit | `gantt.zoom == .week` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 51 | KairoPresentationTests/DayWidthAcceptanceTests.swift:937 | zoomKeepsPresetSemanticsWhileTickGranularityReportsEffectiveUnit | `gantt.zoom == item.preset` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 52 | KairoPresentationTests/DayWidthAcceptanceTests.swift:958 | dayWidthActionsExposeInspectablePayloads | `width == 20` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 53 | KairoPresentationTests/DayWidthAcceptanceTests.swift:965 | dayWidthActionsExposeInspectablePayloads | `delta == 1` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 54 | KairoPresentationTests/DayWidthAcceptanceTests.swift:970 | dayWidthActionsExposeInspectablePayloads | `negative == -1` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 55 | KairoPresentationTests/PresenterTests.swift:131 | filterKeepsAncestorsAndForcesExpansion | `snapshot.outline.filterSummary?.contains("筛选") == true` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 56 | KairoPresentationTests/PresenterTests.swift:392 | inspectorFallsBackWhenSelectionMissing | `project.title == "演示项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 57 | KairoPresentationTests/PresenterTests.swift:423 | violationInspectorGroupsAndListsRuleCatalog | `inspector.groups[0].items[0].name == "相关性环"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 58 | KairoPresentationTests/PresenterTests.swift:483 | statusBarZoomLabelReflectsPreference | `snapshot.statusBar.zoomLabel == "日"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 59 | KairoPresentationTests/PresenterTests.swift:548 | thousandTaskSnapshotStaysWithinBudget | `bestMilliseconds < 1000` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 60 | KairoPresentationTests/DayWidthTests.swift:216 | presetZoomKeepsItsOwnDayWidth | `gantt.tickGranularity == preset.zoom` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 61 | KairoPresentationTests/DayWidthTests.swift:338 | statusBarReportsZoomLabelAndDetail | `custom.zoomLabel == "自定义"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 62 | KairoPresentationTests/DayWidthTests.swift:339 | statusBarReportsZoomLabelAndDetail | `custom.zoomDetail == "20 点/天"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 63 | KairoPresentationTests/DayWidthTests.swift:342 | statusBarReportsZoomLabelAndDetail | `fractional.zoomLabel == "自定义"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 64 | KairoPresentationTests/DayWidthTests.swift:343 | statusBarReportsZoomLabelAndDetail | `fractional.zoomDetail == "12.5 点/天"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 65 | KairoPresentationTests/DayWidthTests.swift:346 | statusBarReportsZoomLabelAndDetail | `preset.zoomLabel == "日"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 66 | KairoPresentationTests/DayWidthTests.swift:347 | statusBarReportsZoomLabelAndDetail | `preset.zoomDetail == "32 点/天"` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 67 | KairoPresentationTests/DayWidthTests.swift:352 | statusBarReportsZoomLabelAndDetail | `fit.zoomLabel == "适合项目"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 68 | KairoPresentationTests/DayWidthTests.swift:353 | statusBarReportsZoomLabelAndDetail | `fit.zoomDetail?.hasSuffix("点/天") == true` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 69 | KairoPresentationTests/DayWidthTests.swift:362 | customDayWidthTakesPriorityInZoomLabel | `statusBar.zoomLabel == "自定义"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 70 | KairoPresentationTests/DayWidthTests.swift:391 | fitModeKeepsTheUserZoomAsTickGranularity | `gantt.dayWidth < 6` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 71 | KairoPresentationTests/DayWidthTests.swift:428 | presetAndFitOutputMatchThePreChangeBaseline | `gantt.dayWidth == legacy.dayWidth` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 72 | KairoPresentationTests/DayWidthTests.swift:454 | presetAndFitOutputMatchThePreChangeBaseline | `fit.dayWidth == legacyFit.dayWidth` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 73 | KairoPresentationTests/CalendarGridTests.swift:50 | gridAlwaysHasFortyTwoConsecutiveUniqueDays | `Set(grid.days).count == grid.days.count` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 74 | KairoPresentationTests/CalendarGridTests.swift:54 | gridAlwaysHasFortyTwoConsecutiveUniqueDays | `calendar.component(.hour, from: earlier) == 0` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 75 | KairoPresentationTests/CalendarGridTests.swift:188 | isWeekendMarksSaturdayAndSunday | `grid.isWeekend(makeDate(2025, 2, 1, calendar: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 76 | KairoPresentationTests/CalendarGridTests.swift:189 | isWeekendMarksSaturdayAndSunday | `grid.isWeekend(makeDate(2025, 2, 2, calendar: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 77 | KairoPresentationTests/CalendarGridTests.swift:190 | isWeekendMarksSaturdayAndSunday | `!grid.isWeekend(makeDate(2025, 2, 3, calendar: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 78 | KairoPresentationTests/CalendarGridTests.swift:191 | isWeekendMarksSaturdayAndSunday | `!grid.isWeekend(makeDate(2025, 2, 5, calendar: calendar))` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 79 | KairoPresentationTests/OutlineColumnPreferencesTests.swift:48 | configurableExcludesFixedColumnsInAllCasesOrder | `!configurable.contains(.number)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 80 | KairoPresentationTests/OutlineColumnPreferencesTests.swift:49 | configurableExcludesFixedColumnsInAllCasesOrder | `!configurable.contains(.title)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 81 | KairoPresentationTests/OutlineColumnPreferencesTests.swift:59 | isResizableExcludesTitleOnly | `OutlineColumnPreferences.isResizable(column)` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |

## 3. 核心层（KairoCore / KairoCommands）（38 条）

| # | 位置 | 用例 | 断言（摘要） | 分类 | 理由 |
|---|---|---|---|---|---|
| 1 | KairoCoreTests/GanttLayoutTests.swift:184 | dayZoomTicksUseTwoTiers | `upper.map(\.label) == ["11月", "12月"]` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 2 | KairoCoreTests/GanttLayoutTests.swift:200 | monthZoomTicksAtMonthStart | `lower.map(\.label) == ["11月", "12月"]` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 3 | KairoCoreTests/GanttLayoutTests.swift:204 | monthZoomTicksAtMonthStart | `upper.map(\.label) == ["2026年"]` | 需跟译 | 期望值是本地化日期串（年月日/星期/单位），随 Locale 变化 → 注入 Locale 判语言相关输出，契约输出改用 ISO |
| 4 | KairoCoreTests/TaskPatchTests.swift:55 | patchUpdatesPlainFields | `task.title == "新标题"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 5 | KairoCoreTests/TaskPatchTests.swift:56 | patchUpdatesPlainFields | `task.notes == "备注"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 6 | KairoCoreTests/TaskPatchTests.swift:58 | patchUpdatesPlainFields | `task.tags == ["设计"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 7 | KairoCoreTests/FormatMigrationTests.swift:139 | fr_kairo_fmt_1_current_version_skips_migration | `decoded.project.metadata.title == "当前格式"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 8 | KairoCoreTests/FormatMigrationTests.swift:174 | fr_kairo_fmt_2_read_migrates_end_to_end | `decoded.project.metadata.title == "端到端 v2 v3"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 9 | KairoCoreTests/FormatMigrationTests.swift:297 | fr_kairo_fmt_4_throwing_step_is_wrapped_with_from_to | `reason.contains("合成迁移拒绝继续")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 10 | KairoCoreTests/FormatMigrationTests.swift:321 | fr_kairo_fmt_4_failed_migration_writes_nothing | `reason.contains("合成迁移拒绝继续")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 11 | KairoCoreTests/FormatMigrationTests.swift:343 | fr_kairo_fmt_4_decode_failure_after_migration_is_wrapped | `reason.contains("解码")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 12 | KairoCoreTests/ProjectStateTests.swift:17 | snapshotCopiesProjectContent | `state.metadata.title == "快照项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 13 | KairoCoreTests/ProjectStateTests.swift:32 | snapshotIsIndependentOfLaterProjectMutation | `state.metadata.title == "原项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 14 | KairoCoreTests/ProjectStateTests.swift:47 | applyRestoresFullProject | `project.metadata.title == "原项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 15 | KairoCoreTests/ProjectStateTests.swift:59 | emptyStateAppliesAsEmptyProject | `project.metadata.title == "空"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 16 | KairoCoreTests/SessionCacheTests.swift:127 | restoreReplacesProjectContent | `try session.listTasks().map(\.title) == ["原任务"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 17 | KairoCoreTests/ModelTests.swift:108 | parentChildrenTreeStructure | `project.tasks.filter { $0.parentID == nil }.count == 2` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 18 | KairoCoreTests/OutlineTreeTests.swift:57 | collapsedGroupsHideChildren | `tree.rows.map(\.task.title) == ["组", "顶层任务"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 19 | KairoCoreTests/OutlineTreeTests.swift:68 | expandedGroupsShowChildrenInOrder | `tree.rows.map(\.task.title) == ["组", "A", "B", "顶层任务"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 20 | KairoCoreTests/OutlineTreeTests.swift:157 | filterShowsMatchesAndForcesAncestorsExpanded | `tree.rows.map(\.task.title) == ["组", "B"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 21 | KairoCoreTests/OutlineTreeTests.swift:196 | orphanIsTreatedAsRoot | `tree.rows.map(\.task.title) == ["孤儿"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 22 | KairoCoreTests/ProjectDirectionTests.swift:21 | legacyMetadataDecodesAsForward | `decoded.title == "旧文件"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 23 | KairoCoreTests/OutlineMovingTests.swift:30 | movesTaskIntoGroupAtStart | `updated.map(\.title) == ["组", "其他", "子", "孙"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 24 | KairoCoreTests/OutlineMovingTests.swift:41 | movesTaskIntoGroupAtEnd | `updated.map(\.title) == ["组", "子", "孙", "其他"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 25 | KairoCoreTests/OutlineMovingTests.swift:51 | movesSubtreeOutToRoot | `updated.map(\.title) == ["子", "孙", "组", "其他"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 26 | KairoCoreTests/DeepLinkTests.swift:23 | parsesPercentEncodedTitle | `link.target == .taskTitle("验收")` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 27 | KairoCoreTests/ProjectSummaryTests.swift:91 | overdueUsesPlannedFinishThenDueDateFallback | `summary.missingDueDateCount == 1` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |
| 28 | KairoCoreTests/ResourceStatusTests.swift:95 | resourcesPersistThroughKairoFileRoundTrip | `loaded.resources.first?.name == "测试机"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 29 | KairoCoreTests/KairoFileTests.swift:20 | saveLoadRoundTripPreservesTasksAndMetadata | `loaded.metadata.title == "示例项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 30 | KairoCoreTests/KairoFileTests.swift:100 | saveToURLAndLoadFromURL | `loaded.metadata.title == "磁盘往返"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 31 | KairoCoreTests/KairoFileTests.swift:115 | fr_kairo_fmt_1_read_current_file_reports_current_source_version | `decoded.project.metadata.title == "当前版本"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 32 | KairoCoreTests/KairoFileTests.swift:142 | fr_kairo_fmt_5_legacy_file_resaves_as_current_version_and_reopens | `reopened.project.metadata.title == "旧项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 33 | KairoCoreTests/KairoCoreTests.swift:135 | explanationSummarizesClauses | `text.contains("筛选")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 34 | KairoCoreTests/KairoCoreTests.swift:136 | explanationSummarizesClauses | `text.contains("逾期")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 35 | KairoCoreTests/KairoCoreTests.swift:157 | applyFiltersFixtureTasks | `overdue.first?.title == "逾期任务"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 36 | KairoCoreTests/KairoCoreTests.swift:161 | applyFiltersFixtureTasks | `dueToday.first?.title == "今日任务"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 37 | KairoCoreTests/KairoCoreTests.swift:168 | applyFiltersFixtureTasks | `done.first?.title == "完成任务"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 38 | KairoCoreTests/KairoCoreTests.swift:180 | applyAndCombinesClauses | `result.first?.title == "支付网关"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |

## 4. 接口层（CLI / MCP）（18 条）

| # | 位置 | 用例 | 断言（摘要） | 分类 | 理由 |
|---|---|---|---|---|---|
| 1 | InterfaceTests/CLITests.swift:16 | operandsAndFlagValues | `try o.operand(0, name: "标题") == "标题"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 2 | InterfaceTests/CLITests.swift:143 | projectCreateThenWBSImportPersistsTree | `project.metadata.title == "演示项目"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 3 | InterfaceTests/CLITests.swift:153 | projectCreateThenWBSImportPersistsTree | `try #require(project.tasks.first { $0.title == "后端" }).kind == .milestone` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 4 | InterfaceTests/CLITests.swift:208 | taskUpdateProgressAndStatus | `task.tags == ["后端", "搜索"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 5 | InterfaceTests/CLITests.swift:340 | taskListJSONEncodesStableFields | `json.contains("\"title\":\"接口设计\"")` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 6 | InterfaceTests/CLITests.swift:347 | taskListJSONEncodesStableFields | `item.title == "接口设计"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 7 | InterfaceTests/CLITests.swift:350 | taskListJSONEncodesStableFields | `item.tags == ["设计"]` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 8 | InterfaceTests/CLITests.swift:468 | resourceAddAndListPersist | `project.resources.first?.name == "李工"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 9 | InterfaceTests/CLITests.swift:549 | fr_kairo_fmt_6_cliProjectCommandsPrintFormatVersion | `!saveOutput.contains("已从 v")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 10 | InterfaceTests/CLITests.swift:555 | fr_kairo_fmt_6_cliProjectCommandsPrintFormatVersion | `openOutput.contains("源格式版本：v\(KairoFile.currentFormatVersion)（当前 v\(KairoFile.currentFo…` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 11 | InterfaceTests/CLITests.swift:556 | fr_kairo_fmt_6_cliProjectCommandsPrintFormatVersion | `!openOutput.contains("保存后升级")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 12 | InterfaceTests/CLITests.swift:573 | fr_kairo_fmt_6_cliFormatVersionLineRendersUpgradeSource | `CLIRouter.formatVersionLine(written: current, upgradedFrom: nil) == "格式版本：v\(current)"` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 13 | InterfaceTests/InterfaceTests.swift:135 | unknownMethodReturnsJSONRPCError | `response.objectValue?["error"]?.objectValue?["message"]?.stringValue?.contains("未知方法") …` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 14 | InterfaceTests/InterfaceTests.swift:196 | resourceAddThenListRoundTrip | `resources.first?.objectValue?["name"]?.stringValue == "李工"` | 应改语义 | 中文仅作测试输入（任务标题/备注/项目名为用户数据，不翻译）→ 断结构值，建议抽为具名常量 |
| 15 | InterfaceTests/InterfaceTests.swift:373 | usE102A1_cliTaskAddWithAssigneePersists | `detail.contains("负责人：dev-coder-core")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 16 | InterfaceTests/TaskHookTests.swift:102 | uniqueTitleWritesDone | `result.stderr.contains("已回写")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 17 | InterfaceTests/TaskHookTests.swift:115 | duplicateTitlesAreSkipped | `result.stderr.contains("匹配 2 个")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 18 | InterfaceTests/TaskHookTests.swift:127 | missingTitleIsSkipped | `result.stderr.contains("匹配 0 个")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |

## 5. 更新模块（KairoUpdater）（3 条）

| # | 位置 | 用例 | 断言（摘要） | 分类 | 理由 |
|---|---|---|---|---|---|
| 1 | KairoUpdaterTests/UpdaterManagerTests.swift:150 | belowMinimumFailsClosed | `message.contains("最低版本")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 2 | KairoUpdaterTests/InstallerTests.swift:70 | replacementScriptWaitsBacksUpReplacesAndReports | `decoded.message.contains("自动启动失败")` | 需跟译 | 期望值是界面/回执/错误文案，切语言即失效 → 改按语言取词，或断错误码 + 占位符个数 |
| 3 | KairoUpdaterTests/InstallerTests.swift:108 | launchPathMismatchFailsFast | `launched.isEmpty` | 应改语义 | 中文仅在失败提示，断言对象是数值/布尔 → 保持语义断言，不受语言影响 |

## 6. 三类计数与自校验

| target | 条数 | 需跟译 | 应改语义 | 应删 |
|---|---|---|---|---|
| AppTests | 187 | 50 | 137 | 0 |
| KairoPresentationTests | 81 | 17 | 64 | 0 |
| KairoCoreTests | 38 | 8 | 30 | 0 |
| InterfaceTests | 18 | 9 | 9 | 0 |
| KairoUpdaterTests | 3 | 2 | 1 | 0 |
| **合计** | **327** | **86** | **241** | **0** |

自校验：327 = 187（App）+ 81（Presentation）+ 38（Core）+ 18（Interface）+ 3（Updater），且 86 + 241 + 0 = 327。两个等式同时成立才算清单完整。

**关于「应删 = 0」**：不是没查，是查完之后没有一条够格删。见 §7。

## 7. 7 组「看起来重复」的断言 —— 全部保留

机械去重能看到 7 组同表达式断言（每组多 1 行，共 7 行）。逐组读过上下文，**没有一组是冗余**：它们都位于「操作前 / 操作后」两个时点，断的是「状态没有被不该发生的事改动」。删掉任一条，对应路径的静默回归就失去防线。

| 位置 | 用例 | 表达式 | 两处各自的作用 |
|---|---|---|---|
| AppTests/WorkspaceStoreTests.swift:94,99 | loadExampleConfirmsWhenDirty | `store.exportProject.metadata.title == "未保存标题"` | 载入请求挂起时标题未被改写；用户取消后标题仍未被改写 |
| AppTests/WorkspaceStoreTests.swift:293,299 | dropExitCancelsPendingExpand | `try !row(store, "新群组").isExpanded` | 拖拽前的折叠态；取消展开后仍是折叠态（证明 cancel 真生效） |
| AppTests/WorkspaceStoreTests.swift:471,477 | consecutiveRenamesMergeIntoOneUndoStep | `try task(store, "第二次改名").title == "第二次改名"` | 改名已落盘；undo 一次后回到首个名字（证明只产生一个撤销步） |
| AppTests/WorkspaceStoreTests.swift:579,583 | dirtyOpenWaitsForUserChoice | `store.exportProject.metadata.title == "未保存标题"` | 打开被拦截时文档未替换；用户选择取消后仍未替换 |
| AppTests/WorkspaceStoreTests.swift:737,744 | selectingElsewhereRestoresTemporarilySuspendedFilter | `store.viewState.filterText == "发布"` | 临时挂起前的筛选值；焦点移走后筛选值被恢复 |
| AppTests/WorkspaceStoreTests.swift:929,937 | predecessorColumnReportsHiddenOrUnknownNumber | `store.alertMessage?.contains("可能被折叠或筛选隐藏") == true` | 首次提示内容；二次操作仍给出同一归因（而不是另一条文案） |
| AppTests/Sprint8DateAcceptanceTests.swift:243,252 | finishNotAfterStartIsRejectedWithoutUndo | `store.alertMessage == "结束日期必须晚于开始日期"` | 首次非法输入被拒；第二次非法输入同样被拒（防「只校验第一次」） |

## 8. 最容易被误判为「应删」的三条（保留理由）

1. **`WorkspaceStoreTests.swift:99` `store.exportProject.metadata.title == "未保存标题"`** —— 与第 94 行逐字相同，像复制粘贴。它守的是「用户点了取消」这条分支：若 `cancelPendingLoadExample()` 误把文档替换掉，只有这一行会红。删掉它，脏文档保护只剩「挂起时没替换」一半保障。
2. **`WorkspaceStoreTests.swift:299` `try !row(store, "新群组").isExpanded`** —— 与第 293 行同时刻同状态，看似重复。它前面隔着 `scheduleDropExpand` + `cancelDropExpand` + 800ms 真实等待，断的是「延迟任务被取消后没有补做展开」。删了它，`cancelDropExpand` 就没有任何黑盒观测量。
3. **`Sprint8DateAcceptanceTests.swift:252` `store.alertMessage == "结束日期必须晚于开始日期"`** —— 同一文案第二次出现，中间只插了 `alertMessage = nil` 和第二次非法 dispatch。它证明校验不是「每会话只报一次」或「只对首次输入生效」。F-0710 应把它改成 `alertCode == .finishNotAfterStart`，**而不是删除**。

## 9. 对 F-0710 的直接结论

- 真正要动的是 86 条（需跟译），占 26%；其中 16 条是日期/单位串，集中在 `Sprint8DateFieldRenderTests`、`DayWidth*`、`GanttLayoutTests`，与 F-0712 同一批改动。
- 241 条（应改语义）里 162 条只是失败提示含中文，改造量为零——不要算进工作量。
- 剩余 79 条输入数据类：只需把 `"任务 A"` 这类字面量抽成文件顶部常量，断言表达式可逐字不动。

