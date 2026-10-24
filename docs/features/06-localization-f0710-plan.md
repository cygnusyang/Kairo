# F-0710 断言改造执行计划

> 依据：[06-localization-cases.md](./06-localization-cases.md)、[06-localization-assertions.md](./06-localization-assertions.md)、[06-localization.md](./06-localization.md) §8。
> **名称已与已提交源码对齐**（`ViolationReason` / `KairoErrorCode` / `ZoomPreset` / `ZoomIndicator` / `DateFieldAvailability`），对不上的 3 处单列于 §7。
> 本文只定「哪条断言改成什么、依赖谁先落地」，**不含测试文件改动**。Tests/ 按 target 分属 G2/G3/G4，F-0710 开工前不动一行。

## 0. 边界与口径

- 改造总量 **165 条** = 86 条需跟译（改断言对象）+ 79 条输入常量抽取（断言不变）。剩余 162 条「中文只在失败提示」不动。
- 三条目标写法，不允许出现第四种：① 断**码/枚举**（错误、通知、缩放档位）；② 断**键 + 占位符**（界面文案要保留文本契约时）；③ 断**结构值**（日期改 ISO 或日期分量，数值改 Double）。
- 计划里的 case 名（如 `.finishNotAfterStart`）是**建议名**，落地以 G2 实际实现为准；名字不同不算计划失效，语义必须等价。
- 依赖列含义：该条在依赖项合入前改了会锁死未定格式或编译不过，必须等。

## 1. 总览

| target | 需跟译 | 常量抽取 | 合计 | 归属 | 主依赖 |
|---|---|---|---|---|---|
| AppTests | 50 | 40 | 90 | G4 | F-0705（需 G4 暴露 noticeKey） / F-0705（需 G4 暴露 alertKey） |
| KairoPresentationTests | 17 | 2 | 19 | G2 | F-0704 / F-0712 |
| KairoCoreTests | 8 | 28 | 36 | G2 | F-0703 / F-0702 |
| InterfaceTests | 9 | 9 | 18 | G3 | F-0707 / F-0708 |
| KairoUpdaterTests | 2 | 0 | 2 | G2 | F-0703（已交付 UpdaterErrorCode） / F-0703 |
| **合计** | **86** | **79** | **165** | — | — |

## 2. 逐文件改造计划

### 2.1 AppTests（归属 G4）

**AppTests/Sprint8DateFieldRenderTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :307 | `label == "11 月 6 日，星期五，今天，已选中，不可选"` | 见 §3 | F-0712 |
| :316 | `outside.hasPrefix("10 月 26 日，星期一")` | 见 §3 | F-0712 |
| :317 | `outside.contains("不在本月")` | outside.status == .outsideMonth | F-0712 |
| :319 | `Display.monthTitle(date(2026, 11, 6), calendar: calendar) == "2026 年 11 月"` | 见 §3 | F-0712 |
| :320 | `Display.weekdaySymbols(calendar: calendar) == ["一", "二", "三", "四", "五", "六", "日…` | 见 §3 | F-0712 |
| :420 | `short == "2026-11-06 – 2026-11-09 · 3 天"` | 见 §3 | F-0712 |
| :421 | `long == "2026-11-06 – 2026-11-12 · 6 天"` | 见 §3 | F-0712 |

**AppTests/FormatUpgradeTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :94 | `store.notice?.contains("已升级") != true` | noticeKey != "alert.upgraded_to" | F-0705（需 G4 暴露 noticeKey） |
| :149 | `store.exportProject.metadata.title == "旧版项目"` | 抽为文件顶部常量，断言不变 | — |
| :152 | `store.notice?.contains("已升级") != true` | noticeKey != "alert.upgraded_to" | F-0705（需 G4 暴露 noticeKey） |
| :169 | `store.notice == "已升级到 v\(KairoFile.currentFormatVersion)"` | noticeKey == "alert.upgraded_to" && noticeArgs.count == 1 | F-0705（需 G4 暴露 noticeKey） |
| :176 | `store.notice?.contains("已升级") != true` | noticeKey != "alert.upgraded_to" | F-0705（需 G4 暴露 noticeKey） |
| :246 | `store.notice?.contains("已升级") != true` | noticeKey != "alert.upgraded_to" | F-0705（需 G4 暴露 noticeKey） |
| :280 | `store.notice == "已升级到 v\(KairoFile.currentFormatVersion)"` | noticeKey == "alert.upgraded_to" && noticeArgs.count == 1 | F-0705（需 G4 暴露 noticeKey） |
| :325 | `store.notice?.contains("已升级") != true` | noticeKey != "alert.upgraded_to" | F-0705（需 G4 暴露 noticeKey） |
| :326 | `store.exportProject.metadata.title == "第三个项目"` | 抽为文件顶部常量，断言不变 | — |
| :346 | `store.notice?.contains("已升级") != true` | noticeKey != "alert.upgraded_to" | F-0705（需 G4 暴露 noticeKey） |
| :385 | `notice.contains("已升级到 v\(KairoFile.currentFormatVersion)")` | noticeKey == "alert.upgraded_to" && noticeArgs.count == 1 | F-0705（需 G4 暴露 noticeKey） |
| :386 | `notice.contains("已按群组处理")` | noticeKey == "alert.notice.combined" && noticeArgs.count == 2 | F-0705（需 G4 暴露 noticeKey） |

**AppTests/WorkspaceStoreTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :94 | `store.exportProject.metadata.title == "未保存标题"` | 抽为文件顶部常量，断言不变 | — |
| :99 | `store.exportProject.metadata.title == "未保存标题"` | 抽为文件顶部常量，断言不变 | — |
| :125 | `Set(commands.map(\.group)) == Set(["文件", "编辑", "大纲", "任务", "视图", "查找"])` | Set(commands.map(\.groupID)) == Set([.file, .edit, .outline, .task, .view, .find]) | F-0705 |
| :196 | `CommandPalette.matching("甘特", in: commands).map(\.id) == ["view.outline"]` | CommandPalette.matching(t("command.view.gantt.title"), in: commands).map(\.id) == ["view.outline"] | F-0705 |
| :197 | `CommandPalette.matching("任务视图", in: commands).map(\.id) == ["view.plan"]` | CommandPalette.matching(t("command.view.plan.title"), in: commands).map(\.id) == ["view.plan"] | F-0705 |
| :199 | `CommandPalette.matching("不存在的命令", in: commands).isEmpty` | CommandPalette.matching("no-such-command", in: commands).isEmpty（输入改英文不存在串，语义不变） | — |
| :224 | `try task(store, "发布 v1.0").parentID == review.id` | 抽为文件顶部常量，断言不变 | — |
| :225 | `try row(store, "发布 v1.0").depth == 1` | 抽为文件顶部常量，断言不变 | — |
| :247 | `try task(store, "实现搜索后端").parentID == groupID` | 抽为文件顶部常量，断言不变 | — |
| :274 | `try !row(store, "新群组").isExpanded` | 抽为文件顶部常量，断言不变 | — |
| :285 | `try row(store, "新群组").isExpanded` | 抽为文件顶部常量，断言不变 | — |
| :293 | `try !row(store, "新群组").isExpanded` | 抽为文件顶部常量，断言不变 | — |
| :299 | `try !row(store, "新群组").isExpanded` | 抽为文件顶部常量，断言不变 | — |
| :337 | `created.title == "新任务"` | 抽为文件顶部常量，断言不变 | — |
| :352 | `created.title == "新任务"` | 抽为文件顶部常量，断言不变 | — |
| :353 | `try row(store, "新任务").depth == 1` | 抽为文件顶部常量，断言不变 | — |
| :387 | `try task(store, "实现搜索后端").kind == .group` | 抽为文件顶部常量，断言不变 | — |
| :388 | `try row(store, "实现搜索后端").kind == .group` | 抽为文件顶部常量，断言不变 | — |
| :418 | `try row(store, "实现搜索后端").progress == 0.25` | 抽为文件顶部常量，断言不变 | — |
| :440 | `try task(store, "实现搜索后端").dependencies.isEmpty` | 抽为文件顶部常量，断言不变 | — |
| :471 | `try task(store, "第二次改名").title == "第二次改名"` | 抽为文件顶部常量，断言不变 | — |
| :477 | `try task(store, "第二次改名").title == "第二次改名"` | 抽为文件顶部常量，断言不变 | — |
| :508 | `store.snapshot.statusBar.selectionSummary == "Code Review 搜索模块"` | 抽为文件顶部常量，断言不变 | — |
| :532 | `store.notice == "任务已删除"` | noticeKey == "alert.task_deleted" | F-0705（需 G4 暴露 noticeKey） |
| :579 | `store.exportProject.metadata.title == "未保存标题"` | 抽为文件顶部常量，断言不变 | — |
| :583 | `store.exportProject.metadata.title == "未保存标题"` | 抽为文件顶部常量，断言不变 | — |
| :593 | `store.exportProject.metadata.title == "另一个项目"` | 抽为文件顶部常量，断言不变 | — |
| :625 | `store.exportProject.metadata.title == "载入期间编辑"` | 抽为文件顶部常量，断言不变 | — |
| :651 | `store.notice?.contains("正在载入") == true` | noticeKey == "alert.loading_in_progress" | F-0705（需 G4 暴露 noticeKey） |
| :660 | `store.exportProject.metadata.title == "第一个项目"` | 抽为文件顶部常量，断言不变 | — |
| :706 | `reloaded.exportProject.metadata.title == "面板打开后修改"` | 抽为文件顶部常量，断言不变 | — |
| :737 | `store.viewState.filterText == "发布"` | 抽为文件顶部常量，断言不变 | — |
| :744 | `store.viewState.filterText == "发布"` | 抽为文件顶部常量，断言不变 | — |
| :929 | `store.alertMessage?.contains("可能被折叠或筛选隐藏") == true` | alertKey == "error.dependency.predecessor_hidden" | F-0705（需 G4 暴露 alertKey） |
| :937 | `store.alertMessage?.contains("可能被折叠或筛选隐藏") == true` | alertKey == "error.dependency.predecessor_hidden" | F-0705（需 G4 暴露 alertKey） |
| :981 | `store.alertMessage?.contains("环") == true` | alertKey == "error.dependency.cycle" | F-0705（需 G4 暴露 alertKey） |
| :990 | `store.alertMessage?.contains("找不到") == true` | alertKey == "error.task.not_found" | F-0705（需 G4 暴露 alertKey） |
| :993 | `store.alertMessage?.contains("自身") == true` | alertKey == "error.dependency.self" | F-0705（需 G4 暴露 alertKey） |
| :1014 | `store.exportProject.metadata.title == "未命名项目"` | 抽为文件顶部常量，断言不变 | — |
| :1036 | `store.exportProject.metadata.title == "外部标题"` | 抽为文件顶部常量，断言不变 | — |
| :1037 | `store.notice?.hasPrefix("已载入外部更新") == true` | noticeKey == "alert.external_update_loaded" | F-0705（需 G4 暴露 noticeKey） |
| :1187 | `try command(commands, "view.outlineColumn.start").title == "显示/隐藏开始列"` | command.id == "view.outlineColumn.start"（标题由键存在测试覆盖） | F-0705 |

**AppTests/Sprint8TaskDateActionTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :144 | `store.alertMessage == "结束日期必须晚于开始日期"` | alertKey == "alert.finish_after_start" | F-0705（需 G4 暴露 alertKey） |
| :157 | `store.alertMessage == "结束日期必须晚于开始日期"` | alertKey == "alert.finish_after_start" | F-0705（需 G4 暴露 alertKey） |
| :197 | `store.alertMessage == "排期已变化，请重新选择结束日期"` | alertKey == "alert.schedule_changed" | F-0705（需 G4 暴露 alertKey） |
| :214 | `store.alertMessage == "结束日期必须晚于开始日期"` | alertKey == "alert.finish_after_start" | F-0705（需 G4 暴露 alertKey） |

**AppTests/Sprint8DateAcceptanceTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :243 | `store.alertMessage == "结束日期必须晚于开始日期"` | alertKey == "alert.finish_after_start" | F-0705（需 G4 暴露 alertKey） |
| :252 | `store.alertMessage == "结束日期必须晚于开始日期"` | alertKey == "alert.finish_after_start" | F-0705（需 G4 暴露 alertKey） |
| :531 | `DateQuickAction.allCases.map(\.title) == ["今天", "下周一", "+1 周"]` | 抽为文件顶部常量，断言不变 | — |
| :589 | `store.alertMessage == "排期已变化，请重新选择结束日期"` | alertKey == "alert.schedule_changed" | F-0705（需 G4 暴露 alertKey） |

**AppTests/DayWidthControlTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :44 | `store.snapshot.statusBar.zoomLabel == "自定义"` | store.snapshot.statusBar.zoom.preset == .custom | F-0704 |

**AppTests/SaveAsTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :64 | `saveAs.title == "另存为…"` | saveAs.id == "file.saveAs" | F-0705 |
| :65 | `saveAs.group == "文件"` | saveAs.groupID == .file | F-0705 |
| :67 | `saveAs.aliases.contains("保存副本")` | saveAs.aliases.isEmpty == false && saveAs.id == "file.saveAs"（不再比对文案） | F-0705 |
| :69 | `CommandPalette.matching("另存为", in: commands).contains { $0.id == "file.saveAs" }` | CommandPalette.matching(t("command.file.saveAs.title"), in: commands).contains { $0.id == "file.saveAs" } | F-0705 |
| :70 | `CommandPalette.matching("保存副本", in: commands).contains { $0.id == "file.saveAs"…` | CommandPalette.matching(t("command.file.saveAs.alias.saveCopy"), in: commands).contains { $0.id == "file.saveAs" } | F-0705 |
| :108 | `SaveFilenameSuggestion.suggest(currentURL: nil, title: "季度/") == "季度.kairo"` | 抽为文件顶部常量，断言不变 | — |
| :109 | `SaveFilenameSuggestion.suggest(currentURL: nil, title: "季度 - ") == "季度.kairo"` | 抽为文件顶部常量，断言不变 | — |
| :133 | `fromTitle == String(repeating: "计", count: 64) + ".kairo"` | 抽常量 Fixture.longCJKTitle（64×"计"），断言不变 | — |
| :140 | `fromURL == String(repeating: "计", count: 64) + ".kairo"` | 抽常量 Fixture.longCJKTitle，断言不变 | — |
| :177 | `store.suggestedSaveFilename == "未命名项目.kairo"` | suggestedSaveFilename == t("file.defaultProjectName") + ".kairo" | F-0705 |
| :180 | `store.suggestedSaveFilename == "路线 - 图.kairo"` | 抽常量 Fixture.projectTitle，断言不变 | — |
| :184 | `store.suggestedSaveFilename == "已有.kairo"` | 抽常量 Fixture.existingProjectTitle，断言不变 | — |
| :209 | `reopened.metadata.title == "格式版本检查"` | 抽为文件顶部常量，断言不变 | — |
| :270 | `try KairoFile.load(from: newURL).metadata.title == "另存后再修改"` | 抽为文件顶部常量，断言不变 | — |
| :294 | `store.notice?.hasPrefix("已载入外部更新") != true` | noticeKey != "alert.external_update_loaded" | F-0705（需 G4 暴露 noticeKey） |
| :297 | `try KairoFile.load(from: originalURL).metadata.title == "旧文件被外部改写"` | 抽为文件顶部常量，断言不变 | — |
| :318 | `try KairoFile.load(from: newURL).metadata.title == "面板打开期间的编辑"` | 抽为文件顶部常量，断言不变 | — |
| :344 | `store.exportProject.metadata.title == "面板中修改"` | 抽为文件顶部常量，断言不变 | — |
| :399 | `try KairoFile.load(from: newURL).metadata.title == "取消后直接保存"` | 抽为文件顶部常量，断言不变 | — |

**AppTests/DayWidthUxAcceptanceTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :143 | `WorkspacePresenter.zoomDetail(dayWidth: 1e16).hasSuffix("点/天")` | 见 §3 | F-0712 |

### 2.2 KairoPresentationTests（归属 G2）

**KairoPresentationTests/DayWidthAcceptanceTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :662 | `custom.zoomLabel == "自定义"` | custom.zoom.preset == .custom | F-0704 |
| :663 | `custom.zoomDetail == "20 点/天"` | 见 §3 | F-0712 |
| :666 | `fractional.zoomLabel == "自定义"` | fractional.zoom.preset == .custom | F-0704 |
| :667 | `fractional.zoomDetail == "12.5 点/天"` | 见 §3 | F-0712 |
| :675 | `preset.zoomLabel == "日"` | preset.zoom.preset == .day | F-0704 |
| :692 | `fit.zoomLabel == "适合项目"` | fit.zoom.preset == .fit | F-0704 |

**KairoPresentationTests/PresenterTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :131 | `snapshot.outline.filterSummary?.contains("筛选") == true` | snapshot.outline.filterSummary == .active（枚举，非摘要串） | F-0704 |
| :392 | `project.title == "演示项目"` | 抽为文件顶部常量，断言不变 | — |
| :423 | `inspector.groups[0].items[0].name == "相关性环"` | 抽为文件顶部常量，断言不变 | — |
| :483 | `snapshot.statusBar.zoomLabel == "日"` | snapshot.statusBar.zoom.preset == .day | F-0704 |

**KairoPresentationTests/DayWidthTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :338 | `custom.zoomLabel == "自定义"` | custom.zoom.preset == .custom | F-0704 |
| :339 | `custom.zoomDetail == "20 点/天"` | 见 §3 | F-0712 |
| :342 | `fractional.zoomLabel == "自定义"` | fractional.zoom.preset == .custom | F-0704 |
| :343 | `fractional.zoomDetail == "12.5 点/天"` | 见 §3 | F-0712 |
| :346 | `preset.zoomLabel == "日"` | preset.zoom.preset == .day | F-0704 |
| :347 | `preset.zoomDetail == "32 点/天"` | 见 §3 | F-0712 |
| :352 | `fit.zoomLabel == "适合项目"` | fit.zoom.preset == .fit | F-0704 |
| :353 | `fit.zoomDetail?.hasSuffix("点/天") == true` | 见 §3 | F-0712 |
| :362 | `statusBar.zoomLabel == "自定义"` | statusBar.zoom.preset == .custom | F-0704 |

### 2.3 KairoCoreTests（归属 G2）

**KairoCoreTests/GanttLayoutTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :184 | `upper.map(\.label) == ["11月", "12月"]` | 见 §3 | F-0702 |
| :200 | `lower.map(\.label) == ["11月", "12月"]` | 见 §3 | F-0702 |
| :204 | `upper.map(\.label) == ["2026年"]` | 见 §3 | F-0702 |

**KairoCoreTests/TaskPatchTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :55 | `task.title == "新标题"` | 抽为文件顶部常量，断言不变 | — |
| :56 | `task.notes == "备注"` | 抽为文件顶部常量，断言不变 | — |
| :58 | `task.tags == ["设计"]` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/FormatMigrationTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :139 | `decoded.project.metadata.title == "当前格式"` | 抽为文件顶部常量，断言不变 | — |
| :174 | `decoded.project.metadata.title == "端到端 v2 v3"` | 抽为文件顶部常量，断言不变 | — |
| :297 | `reason.contains("合成迁移拒绝继续")` | migrationError == .migrationFailed（按实际枚举，见 §7） | F-0703 |
| :321 | `reason.contains("合成迁移拒绝继续")` | migrationError == .migrationFailed（按实际枚举，见 §7） | F-0703 |
| :343 | `reason.contains("解码")` | migrationError == .migrationFailed（解码失败归此码，待确认） | F-0703 |

**KairoCoreTests/ProjectStateTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :17 | `state.metadata.title == "快照项目"` | 抽为文件顶部常量，断言不变 | — |
| :32 | `state.metadata.title == "原项目"` | 抽为文件顶部常量，断言不变 | — |
| :47 | `project.metadata.title == "原项目"` | 抽为文件顶部常量，断言不变 | — |
| :59 | `project.metadata.title == "空"` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/SessionCacheTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :127 | `try session.listTasks().map(\.title) == ["原任务"]` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/OutlineTreeTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :57 | `tree.rows.map(\.task.title) == ["组", "顶层任务"]` | 抽为文件顶部常量，断言不变 | — |
| :68 | `tree.rows.map(\.task.title) == ["组", "A", "B", "顶层任务"]` | 抽为文件顶部常量，断言不变 | — |
| :157 | `tree.rows.map(\.task.title) == ["组", "B"]` | 抽为文件顶部常量，断言不变 | — |
| :196 | `tree.rows.map(\.task.title) == ["孤儿"]` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/ProjectDirectionTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :21 | `decoded.title == "旧文件"` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/OutlineMovingTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :30 | `updated.map(\.title) == ["组", "其他", "子", "孙"]` | 抽为文件顶部常量，断言不变 | — |
| :41 | `updated.map(\.title) == ["组", "子", "孙", "其他"]` | 抽为文件顶部常量，断言不变 | — |
| :51 | `updated.map(\.title) == ["子", "孙", "组", "其他"]` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/DeepLinkTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :23 | `link.target == .taskTitle("验收")` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/ResourceStatusTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :95 | `loaded.resources.first?.name == "测试机"` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/KairoFileTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :20 | `loaded.metadata.title == "示例项目"` | 抽为文件顶部常量，断言不变 | — |
| :100 | `loaded.metadata.title == "磁盘往返"` | 抽为文件顶部常量，断言不变 | — |
| :115 | `decoded.project.metadata.title == "当前版本"` | 抽为文件顶部常量，断言不变 | — |
| :142 | `reopened.project.metadata.title == "旧项目"` | 抽为文件顶部常量，断言不变 | — |

**KairoCoreTests/KairoCoreTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :135 | `text.contains("筛选")` | summary.reasons.contains(.filtered) | F-0703 |
| :136 | `text.contains("逾期")` | summary.reasons.contains(.overdue) | F-0703 |
| :157 | `overdue.first?.title == "逾期任务"` | 抽为文件顶部常量，断言不变 | — |
| :161 | `dueToday.first?.title == "今日任务"` | 抽为文件顶部常量，断言不变 | — |
| :168 | `done.first?.title == "完成任务"` | 抽为文件顶部常量，断言不变 | — |
| :180 | `result.first?.title == "支付网关"` | 抽为文件顶部常量，断言不变 | — |

### 2.4 InterfaceTests（归属 G3）

**InterfaceTests/CLITests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :16 | `try o.operand(0, name: "标题") == "标题"` | 抽为文件顶部常量，断言不变 | — |
| :143 | `project.metadata.title == "演示项目"` | 抽为文件顶部常量，断言不变 | — |
| :153 | `try #require(project.tasks.first { $0.title == "后端" }).kind == .milestone` | 抽为文件顶部常量，断言不变 | — |
| :208 | `task.tags == ["后端", "搜索"]` | 抽为文件顶部常量，断言不变 | — |
| :340 | `json.contains("\"title\":\"接口设计\"")` | 抽为文件顶部常量，断言不变 | — |
| :347 | `item.title == "接口设计"` | 抽为文件顶部常量，断言不变 | — |
| :350 | `item.tags == ["设计"]` | 抽为文件顶部常量，断言不变 | — |
| :468 | `project.resources.first?.name == "李工"` | 抽为文件顶部常量，断言不变 | — |
| :549 | `!saveOutput.contains("已从 v")` | JSON 输出格式版本字段：saveJSON["formatVersion"] 存在且 upgradedFrom 为 nil | F-0707 |
| :555 | `openOutput.contains("源格式版本：v\(KairoFile.currentFormatVersion)（当前 v\(KairoFile.c…` | openJSON["formatVersion"] == KairoFile.currentFormatVersion && openJSON["upgradedFrom"] == 1 | F-0707 |
| :556 | `!openOutput.contains("保存后升级")` | openJSON["formatVersion"] 与 upgradedFrom 各自断言（不再匹配「保存后升级」文案） | F-0707 |
| :573 | `CLIRouter.formatVersionLine(written: current, upgradedFrom: nil) == "格式版本：v\(cu…` | CLIRouter.formatVersion(written: current, upgradedFrom: nil) == (current, nil)（结构化，不拼串） | F-0707 |

**InterfaceTests/InterfaceTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :135 | `response.objectValue?["error"]?.objectValue?["message"]?.stringValue?.contains(…` | response["error"]["code"].intValue == -32601 | F-0708 |
| :196 | `resources.first?.objectValue?["name"]?.stringValue == "李工"` | 抽为文件顶部常量，断言不变 | — |
| :373 | `detail.contains("负责人：dev-coder-core")` | taskJSON["assignee"] == "dev-coder-core"（--json 字段） | F-0707 |

**InterfaceTests/TaskHookTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :102 | `result.stderr.contains("已回写")` | exitCode == 0 && stderrJSON["updated"] == 1 | F-0707 |
| :115 | `result.stderr.contains("匹配 2 个")` | stderrJSON["matched"] == 2 && stderrJSON["updated"] == 0 | F-0707 |
| :127 | `result.stderr.contains("匹配 0 个")` | stderrJSON["matched"] == 0 | F-0707 |

### 2.5 KairoUpdaterTests（归属 G2）

**KairoUpdaterTests/UpdaterManagerTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :150 | `message.contains("最低版本")` | errorCode == .minimumVersionUnmet | F-0703（已交付 UpdaterErrorCode） |

**KairoUpdaterTests/InstallerTests.swift**

| 位置 | 现行断言 | 目标断言 | 依赖 |
|---|---|---|---|
| :70 | `decoded.message.contains("自动启动失败")` | errorCode == .autoLaunchFailed | F-0703 |

## 3. 日期 / 单位 16 条专节（最后改）

**顺序约束**：G4 先落 F-0712（`Display` 走 `setLocalizedDateFormatFromTemplate`、四个拼接函数换本地化 API）与 F-0702（核心日期注入 Locale），**断言之后改**。反序的代价：断言先按某一版格式写死，格式再调整时要改两遍，且第二遍分不清是格式回归还是断言过时。

| 位置 | 现行断言 | 目标断言（en） | 目标断言（zh） | 依赖 |
|---|---|---|---|---|
| Sprint8DateFieldRenderTests.swift:307 | `label == "11 月 6 日，星期五，今天，已选中，不可选"` | 拆结构：dayNumber==6 && isToday && isSelected && !isSelectable；另加一条 equals … | 保留原串为 zh 基线 | F-0712 |
| Sprint8DateFieldRenderTests.swift:316 | `outside.hasPrefix("10 月 26 日，星期一")` | hasPrefix("Oct 26") 或 dayNumber==26 | 保留 zh 基线 | F-0712 |
| Sprint8DateFieldRenderTests.swift:319 | `monthTitle(...) == "2026 年 11 月"` | "November 2026" | "2026 年 11 月"（v0.8.5 基线） | F-0712 |
| Sprint8DateFieldRenderTests.swift:320 | `weekdaySymbols == ["一"…"日"]` | ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"] | 原数组（v0.8.5 基线） | F-0712 |
| Sprint8DateFieldRenderTests.swift:420 | `short == "2026-11-06 – 2026-11-09 · 3 天"` | startISO=="2026-11-06" && endISO=="2026-11-09" && durationDays==3 | 原串或「3 天」按语言取词 | F-0712 |
| Sprint8DateFieldRenderTests.swift:421 | `long == "2026-11-06 – 2026-11-12 · 6 天"` | 同上，durationDays==6 | 同上 | F-0712 |
| DayWidthUxAcceptanceTests.swift:143 | `zoomDetail(dayWidth: 1e16).hasSuffix("点/天")` | 返回值 == 1e16（Double），不判单位后缀 | 若要文本用 t("unit.pointsPerDay", 1e16) | F-0704 |
| DayWidthAcceptanceTests.swift:663 | `custom.zoomDetail == "20 点/天"` | dayWidthPoints == 20.0 | 保留 t("unit.pointsPerDay") 断言 | F-0704 |
| DayWidthAcceptanceTests.swift:667 | `fractional.zoomDetail == "12.5 点/天"` | dayWidthPoints == 12.5 | 同上 | F-0704 |
| DayWidthTests.swift:339 | `custom.zoomDetail == "20 点/天"` | dayWidthPoints == 20.0 | 同上 | F-0704 |
| DayWidthTests.swift:343 | `fractional.zoomDetail == "12.5 点/天"` | dayWidthPoints == 12.5 | 同上 | F-0704 |
| DayWidthTests.swift:347 | `preset.zoomDetail == "32 点/天"` | dayWidthPoints == 32.0 | 同上 | F-0704 |
| DayWidthTests.swift:353 | `fit.zoomDetail?.hasSuffix("点/天") == true` | dayWidthPoints != nil | 同上 | F-0704 |
| GanttLayoutTests.swift:184 | `upper.map(\.label) == ["11月", "12月"]` | ["Nov","Dec"]（注入 en_US） | ["11月","12月"]（注入 zh_CN） | F-0702 |
| GanttLayoutTests.swift:200 | `lower.map(\.label) == ["11月", "12月"]` | 同上 | 同上 | F-0702 |
| GanttLayoutTests.swift:204 | `upper.map(\.label) == ["2026年"]` | ["2026"]（en 不带「年」） | ["2026年"] | F-0702 |

> `DayWidthUxAcceptanceTests:143` 与其余 15 条不同源：它测 D-011 的 ±∞/超 Int 路径，归 F-0704 数值化，不依赖 F-0712；批次仍放 B3，避免同文件二次改动。

## 4. 执行批次

| 批次 | 内容 | 前置 | 条数 | 验收命令 |
|---|---|---|---|---|
| **B0** | 输入常量抽取（断言表达式不动）：79 条数据类 + 5 条「分类为需跟译、动作同为抽常量」的行 | 无依赖；但需等归属 coder 释放文件 | 84 | `swift test --disable-sandbox --filter <Target>` |
| **B1** | 错误码 / 通知码 / 快照枚举 / 迁移码 / 更新器错误码 | F-0703、F-0704 合入 | 55 | `swift test --disable-sandbox --filter KairoCoreTests`；`--filter KairoPresentationTests`；`--filter AppTests` |
| **B2** | CLI `--json` 字段与 MCP `error.code` | F-0707、F-0708 合入 | 9 | `swift test --disable-sandbox --filter InterfaceTests` |
| **B3** | 日期/单位 16 条 + 视图键断言 | F-0712、F-0705 合入 | 17 | `swift test --disable-sandbox`（全量）+ 双 Locale 复跑 |

> B0 的 84 = 79 条输入数据（`Fixture.*` 常量）+ 5 条行内中文实为数据派生的断言（`SaveAsTests:133/140/180/184` 的长标题与项目名、`WorkspaceStoreTests:199` 的不存在命令串）。这 5 条在清单里仍计入「需跟译」以保持 86/241 账实一致，但动作与 B0 相同。B3 的 17 = §3 的 16 条日期/单位 + `Sprint8DateFieldRenderTests:317`（`outside.status == .outsideMonth`）。

批次之间不并行改同一文件；B1 完成后先跑一次全量，确认没把「文案断言」改成「恒真断言」——尤其 `noticeCode != .formatUpgraded` 这类否定式，必须另配一条肯定式用例，否则改完永远绿。

## 5. 最终验收（F-0710 出口）

1. `swift test --disable-sandbox` 全绿；`grep -rn '#expect' Tests --include=*.swift | grep '[一-龥]'` 的命中只允许是「失败提示」与「输入常量定义行」，不允许出现在比较表达式右值。
2. 双 Locale 复跑：`LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 swift test --disable-sandbox` 与默认环境通过数相同。
3. `bash tools/i18n-lint.sh --require-catalog --lproj-dir <lproj>` exit 0——确认测试改造没引入新的硬编码中文。
4. 逐条勾销本文 165 行：行首加 `[x]`，不删行，保留改造轨迹供审查。

## 6. 风险与前置

| 风险 | 影响 | 处置 |
|---|---|---|
| G2 的 case 名与本文建议名不同 | 21 条断言需改名 | 以语义等价为准，落地时同步回写本文 |
| F-0704 未把 `zoomDetail` 改成数值型 | 8 条单位断言无法落地 | 先确认 F-0704 交付形态；若保留字符串，改为「按语言取词 + 键存在」 |
| 常量抽取误触 `AppPerformanceTests` 的 1000 任务构造 | 性能基线漂移 | 该文件只有失败提示含中文，B0 不碰 |
| 否定式断言改名后恒真 | 掩盖回归 | B1 每条否定式配一条肯定式对照 |
| 与 coder 抢同一测试文件 | 冲突/覆盖 | 按 2.x 的归属列，等对应 coder 提交后再进该文件 |

## 7. 与源码对不上的 3 处（待裁定）

| # | 计划假设 | 源码实际 | 处置建议 |
|---|---|---|---|
| 1 | `alertCode` / `noticeCode` 两个枚举 | **不存在**。`WorkspaceStore` 仍是 `@Published var alertMessage: String?` 与 `private(set) var notice: String?`，取词在调用点内联 `I18n.t("alert.finish_after_start", "The finish date…")` | 26 条断言已改为 `alertKey == "alert.finish_after_start"` 形态，**前提是 G4 暴露 `alertKey` / `noticeKey`**（或 `lastAlert: (key, args)`）。不暴露则只剩两种差解：断 `I18n.t(key)` 与实现同源（恒真）、断非空（等于没断）。请裁定是否要 G4 加这两个可观测字段 |
| 2 | `migrationError == .syntheticMigrationRejected` / `.decodeFailed` | `KairoErrorCode` 只有 `storage_migration_failed` 一个码 | 3 条按 `.migrationFailed` 断；若要区分「合成迁移拒绝」与「解码失败」，需扩码（建议 `storage_migration_decode_failed`），否则只能断文本（不推荐） |
| 3 | `errorCode == .autoLaunchFailed` | `UpdaterErrorCode` 无此 case，最接近的是 `.scriptLaunchFailed`（`updater_script_launch_failed`） | 请 core 确认 `InstallerTests:70`「自动启动失败」实际走哪个码；确认前该条标 `updater_*`，不猜 |

> 三项都不阻塞 B0（84 条常量抽取）与 B2（接口层 9 条）；只影响 B1 中 26 条 alert/notice 断言的最终形态。
