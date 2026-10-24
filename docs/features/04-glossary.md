# 四、Kairo 术语表（OmniPlan 手册 ch.1000 词汇 → Kairo 定名）

> 来源：OmniPlan 4 macOS 版内置简体中文参考手册，章节 1000 词汇（`1000_glossary.html`），并补入跨章节常用项目管理术语（相关性类型、时限、重要路径、挣值分析、前导时间等）。
> 用途：Kairo 全项目术语一致性基准（doc-style 规则「同一事物同一术语」）。**OmniPlan 术语 → Kairo 定名 → 英文/代码标识符 → 英文界面文案** 四列表为唯一权威；Kairo 定名与既有规格文档（01/02/03）保持一致。
> 说明：Kairo 定名中「任务管理」语义沿用 OmniPlan（资源/投入/基线等），「平台语义」按 AI 时代定位重定名（见备注）。
> 「英文界面文案」列是界面显示用的英文（v0.9.0 起英文为源语言），以 `Apps/macos/Resources/Localizable.xcstrings` 为准；「英文 / 代码标识符」列仍是代码标识符。

## 一、核心任务语义

| OmniPlan 术语 | Kairo 定名 | 英文 / 代码标识符 | 英文界面文案 | 备注 |
| --- | --- | --- | --- | --- |
| 任务（task） | 任务 | Task / `TaskItem` | Task | 模型已用 `TaskItem`（Sources/Kairo/Model/TaskItem.swift） |
| 群组（group） | 群组 | Group / `kind == .group` | Group | 大纲中可嵌套任务集合；Kairo 定名「群组」，不用「组」 |
| 里程碑（milestone） | 里程碑 | Milestone / `kind == .milestone` | Milestone | 零时长、零投入的标记点 |
| 父项 / 子项（parent / child） | 父任务 / 子任务 | Parent / Child / `parentID` | Parent / Child task | 层级树由 `parentID` 表达 |
| 吊床（hammock） | 吊床任务 | Hammock | Hammock task | 时长随前后约束伸缩的弹性任务；见 01 文档 F-14-08 |
| 相关性（dependency） | 相关性 | Dependency / `TaskDependency` | Dependency | 任务间从属关系；显式类型 FS/SS/FF/SF |
| 先决条件（prerequisite） | 先决条件 | Prerequisite | Prerequisite | OmniPlan 大纲「先决条件」栏即相关性的一种呈现 |
| 前导时间（lead time） | 前导时间 | Lead time / `leadTime` | Lead time | 相关性上允许的重叠量，可为正/负/百分比 |
| 时限（constraint） | 时限 | Constraint | Constraint | 对任务开始/结束日期施加的约束（见 02 文档 F-13-07） |
| 重要路径（critical path） | 重要路径 | Critical path / `criticalPath` | Critical path | 决定项目总时长的相关任务链；沿用 OmniPlan「重要路径」定名 |
| 宽延（slack / float） | 宽延 | Slack / `freeSlack`、`totalSlack` | Slack | 任务可推迟而不拖累后续/项目的余量；自由宽延=自由浮动，总宽延=总浮动 |
| 违例（violation） | 违例 | Violation | Violation | 阻碍项目正常完成的问题（超负荷、时限冲突等） |
| 基线日程安排（baseline） | 基线 | Baseline | Baseline | 特定时点的计划快照；与实际日程相对 |
| 实际日程安排（actual schedule） | 实际日程 | Actual | Actual schedule | 反映真实完成情况；未设基线前与基线相同 |
| 差异（variance） | 差异 | Variance / `variance` | Variance | 实际与基线相差的时间量（开始/结束差异） |
| 进度差异 / 成本差异（schedule/cost variance） | 进度差异 / 成本差异 | SV / CV（EVM） | Schedule variance / Cost variance | 挣值指标；见 F-33-08 |

## 二、时间与工作量

| OmniPlan 术语 | Kairo 定名 | 英文 / 代码标识符 | 英文界面文案 | 备注 |
| --- | --- | --- | --- | --- |
| 投入（effort） | 投入 | Effort / `effort` | Effort | 考虑所有资源的工作总量；与持续时间相对 |
| 持续时间（duration） | 持续时间 | Duration / `duration` | Duration | 实际经过的工作时间 |
| 已用时间（elapsed time） | 已用时间 | Elapsed / `elapsedTime` | Elapsed time | 按日历实算，与工作时数无关 |
| 间隔（interval） | 排程间隔 | Interval / `schedulePrecision` | Interval | 任务安排精度（分/时/日）；见 F-11-03 |
| T 日（T day） | T 日（未定日期模式） | T-day / `dateMode == .tentative` | T-day | 未定开始日期的相对时间表示 |
| 工作时数（working hours） | 工作时数 | Working hours / `WorkCalendar` | Working hours | 每周可投入的时间块；见 02 文档 F-16-08 |
| 非工作时数（non-working time） | 非工作时段 | Non-working / `WorkCalendar.exceptions` | Non-working time | 自定义例外；见 F-16-09 |
| 财务年（fiscal year） | 财务年 | Fiscal year | Fiscal year | 仅影响日期标头季度显示 |

## 三、资源与分配

| OmniPlan 术语 | Kairo 定名 | 英文 / 代码标识符 | 英文界面文案 | 备注 |
| --- | --- | --- | --- | --- |
| 资源（resource） | 资源 | Resource / `Resource` | Resource | 完成任务所需的人与物 |
| 人员（person） | 人员 | Person / `ResourceType.person` | Person | 单位按百分比（可投入量） |
| 设备（equipment） | 设备 | Equipment / `ResourceType.equipment` | Equipment | 可复用资产（会议室等） |
| 素材（material） | 素材 | Material / `ResourceType.material` | Material | 消耗性资源，无每小时成本 |
| 单位（units） | 单位 | Units / `units` | Units | 资源可用量（百分比或素材数量） |
| 分配（assignment） | 分配 | Assignment / `resourceAssignments` | Assignment | 资源分配给任务，按投入百分比表达 |
| 效率（efficiency） | 效率 | Efficiency / `efficiency` | Efficiency | 单位时间内可完成工作的比例 |
| 资源负荷（resource load） | 资源负荷 | Load / `resourceLoad` | Resource load | 各时点执行的投入量；超 100% 即超负荷 |
| 分级（leveling） | 分级（重排） | Leveling / `leveling` | Leveling | 自动重排以消除超负荷；Kairo 由 AI 建议替代 |
| 发布 / 订阅（publish / subscribe） | 发布 / 订阅 | Publish / Subscribe | Publish / Subscribe | 跨项目共享资源负荷信息（Pro） |
| 每次使用成本 / 每小时成本 | 次用成本 / 时成本 | Cost/use、Cost/hour | Cost per use / Cost per hour | 资源计费维度；见 F-20-04 |

## 四、视图与界面

| OmniPlan 术语 | Kairo 定名 | 英文 / 代码标识符 | 英文界面文案 | 备注 |
| --- | --- | --- | --- | --- |
| 甘特图（Gantt chart） | 甘特图 | Gantt / `ganttChart` | Gantt chart | 时间顺序条形图 |
| 甘特视图（Gantt view） | 甘特视图 | Gantt view / `ViewMode.gantt` | Gantt view | 大纲 + 甘特图组合窗口 |
| 项目大纲视图（project outline view） | 项目大纲视图 | Outline view / `ViewMode.outline` | Outline view | 全窗口任务大纲 |
| 网络视图（network view） | 网络视图 | Network view / `ViewMode.network` | Network view | 相关性节点网络 |
| 资源视图（resource view） | 资源视图 | Resource view / `ViewMode.resource` | Resource view | 资源列表 + 资源时间线 |
| 资源时间线（resource timeline） | 资源时间线 | Timeline / `resourceTimeline` | Resource timeline | 各资源分配任务的时间线 |
| 检查器（inspector） | 检查器 | Inspector / `InspectorPane` | Inspector | 右侧属性面板；见 02 文档 |
| 项（item） | 项 / 行 | Item / `row` | Row | 大纲中的一行 |
| 自定义栏（column） | 自定义栏 | Column / `column` | Column | 大纲可自定义显示栏位 |
| 过滤器（filter） | 过滤器 | Filter / `AIFilter` | Filter | 条件筛选任务；Kairo 已有 AI 过滤器 |
| 仪表盘（dashboard） | 项目组合 | Portfolio / `PortfolioConfig` | Portfolio | 多项目并列视图；Kairo 定名「组合」 |
| 违例窗口（violations window） | 违例面板 | Violations / `ViolationsPanel` | Violations panel | 问题列表 |
| 更新面板（update sheet） | 更新面板 | UpdateSheet / `UpdateSheet` | Update sheet | OTA 更新的状态与错误面板；错误按 `KairoUpdater` 的错误码翻译 |

## 五、平台 / 协作 / 报告

| OmniPlan 术语 | Kairo 定名 | 英文 / 代码标识符 | 英文界面文案 | 备注 |
| --- | --- | --- | --- | --- |
| 模板（template） | 模板 | Template / `template` | Template | 新项目/报告底稿；Kairo 报告模板=提示词模板 |
| 发布（publish，项目级） | 发布 | Publish | Publish | 把本地更改推到共享库；Kairo 等价「保存即同步」 |
| 刷新（refresh） | 刷新 | Refresh | Refresh | 拉取远端更改 |
| 更改跟踪（change tracking） | 版本历史 | Change tracking / `ChangeRecord` | Version history | Kairo 内置字段级历史替代侧边栏审阅 |
| 复原到服务器副本（revert to server copy） | 复原到已存版本 | Revert / `revert()` | Revert | 放弃本地更改 |
| 挣值分析（earned value analysis） | 挣值分析 | EVM / `earnedValue` | Earned value analysis | PV/EV/AC/CPI/SPI 等指标体系 |
| 完工估算 / 完工预算 | 完工估算 / 完工预算 | EAC / BAC | EAC / BAC | EVM 预报指标 |
| Monte Carlo 模拟 | Monte Carlo 模拟 | Monte Carlo | Monte Carlo simulation | 概率化完工估计；Kairo 由 AI 概率表述替代 |
| 工作分解结构（WBS） | 工作分解结构 | WBS | Work breakdown structure | 任务树状分解 |
| 导入 / 导出（import / export） | 导入 / 导出 | Import / Export | Import / Export | 跨格式读写；Kairo 带保真报告 |
| 服务器帐户（server account） | 文件源 | Source / `FileSource` | File source | Kairo 无服务器概念，收敛为文件/文件夹源 |
| 云同步（cloud sync） | 文件同步 | Sync / 委托云盘 | File sync | Kairo 本地优先，同步交给现有云盘 |
| 自动化（automation） | AI 操作 / 集成 | Automation / `Integration` | AI actions / Integrations | Kairo 用 AI 自然语言操作替代脚本引擎 |

## 六、与代码现状的对应（Sources/Kairo）

| 现有标识符 | 语义 | 对应术语条目 |
| --- | --- | --- |
| `TaskItem` | 任务/群组/里程碑实体（`kind` 区分） | 任务 / 群组 / 里程碑 |
| `Project` | 项目根对象（Codable，单文件） | 项目（隐含术语，OmniPlan「文稿/项目」） |
| `progress: Double` | 任务完成百分比 | 完成百分比（% complete） |
| `dependencies: [UUID]`（现）→ `TaskDependency`（规约） | 任务相关性 | 相关性 |
| `parentID` | 层级父引用 | 父任务 / 子任务 |
| `Resource` / `resourceAssignments` | 资源与分配 | 资源 / 分配 |
| `AIFilter` | AI 驱动的任务过滤 | 过滤器 |
| `ProjectSettings`（规约） | 方向/精度/日历等项目级设置 | 间隔 / 排程间隔 |
| `Baseline`（规约，见 F-14-16） | 基线快照 | 基线 |
| `WorkCalendar`（规约） | 工作时数日历 | 工作时数 |

**使用规则**：
1. Kairo 定名为唯一对外与文档用词；代码标识符遵循 Swift 命名（`TaskItem` 等）。
2. 平台语义（仪表盘→组合、服务器→文件源、自动化→AI 操作）有意偏离 OmniPlan，因 Kairo 定位「AI 时代的本地优先任务管理」，不照搬文件时代术语。
3. 本表与 01/02/03 规格文档互引；发现术语冲突时以本表为准并回改对应文档。
