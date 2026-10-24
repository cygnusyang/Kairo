# 更新日志

所有显著改动记录于此。格式参照 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；
版本号遵循语义化版本。发布版本另见 [GitHub Releases](https://github.com/cygnusyang/Kairo/releases)。

## [Unreleased] — v0.9.0 多语言（阶段一，开发中）

<!-- 发版时把本节标题改为「## v0.9.0 — YYYY-MM-DD」：tools/release.sh 与 tools/release_notes.sh 按「## vX.Y.Z」抽取发布说明。 -->
> 本节随 `feature/i18n-v0.9.0` 归集；发版前逐条核对是否已合入，未合入的条目移出或改写。

### 新增

- **界面双语（英文 / 简体中文）**：英文为源语言，简体中文为译文。语言按系统语言协商，包内 `CFBundleLocalizations` 声明 `en` 与 `zh-Hans`；启动时确定，切换系统语言后重启应用生效。（F-0705）
- **打包期编译 String Catalog（F-0700 主路径 B）**：`.xcstrings` 只作源文件——SwiftPM 的 `.process` 资源只原样拷贝、不编译，生成的 resource bundle 也没有 `Info.plist`，因此运行期只认 `.app` 内的 `.lproj`。`tools/i18n-compile.sh` 用 `xcrun xcstringstool compile` 编出 `en` / `zh-Hans`（Catalog 文件名必须是 `Localizable.xcstrings`——表名由文件名决定，运行期只读 `Localizable` 表），`tools/build.sh` 在 `codesign` **之前**把它们拷进 `Contents/Resources/`；缺 Catalog 或任一语言目录直接失败，不再产出单语包。（F-0709）
- **CLI 语言策略**：`--lang <bcp47>` 与 `KAIRO_LANG`，优先级 命令行 > 环境变量 > 系统语言；**系统语言不可判定时回退简体中文**，保证既有中文脚本不被破坏（英文用户显式钉死语言即可）。`--lang` 取值非法按用法错误退出 2；`--json` 输出与语言无关，两种语言下字节一致。（F-0707）
- **多语言 CI 门禁（`tools/i18n-lint.sh`）**：三项检查——白名单外新增硬编码中文字符串字面量（注释内中文不计）、`KairoCore` / `KairoCommands` / `KairoPresentation` 出现 `Bundle.module`、两份 `.lproj` 的键集合与占位符不一致。白名单 `tools/i18n-whitelist.txt` 入库作为迁移基线，`tools/i18n-lint-selftest.sh`（28 例）守住门禁自身，发版前置校验里 `--fail-if-whitelist-nonempty` 断言白名单清零。**没有任何跳过模式**：CI 以 `--require-catalog` 运行，Catalog 缺失即直接失败并指出「F-0705 未交付」——宁可红，不假绿。（F-0711）

### 变更

- **MCP 错误带稳定 `reason`**：错误响应在既有 `code` 之外新增细粒度 `reason`（`KairoErrorCode` 的 rawValue）；`code` 的 5 个取值冻结不变，按 `invalid_argument` / `task_not_found` 匹配的消费者不受影响。`message` 阶段一保持中文逐字不变，切英文排在 v0.10.0。（F-0708）
- **分层不再持有文案**：违例改为「错误码 + 参数」、会话与 Updater 错误码化、快照只带语义枚举；CLI 与 MCP 各自渲染，不与视图层共享文案表。（F-0703 / F-0704）
- **违例码 `schedule_start_after_project_window`**：任务开始日落在项目窗口外时单独归因，不再报成「负宽延」；参数含任务开始日与项目窗口，中文文案点明是输入导致。（F-0715）
- **打包清单**：`CFBundleDevelopmentRegion` 由 `zh_CN` 改为 `en`。

### 修复

- **时限窗口按日历日计算（D-023）**：原先用 `86400` 秒换算，跨夏令时（America/New_York 春进 / 秋退）会差一小时并误判时限冲突；改用日历加法。（F-0716）
- **排期「无下界」哨兵统一（D-024）**：`startDateLowerBound` 与排期内部哨兵共用同一常量，行为不变。（F-0717）

## v0.8.5 — 2026-10-24

### 新增

- **发布附带 CLI / MCP 二进制**：Release 增加 `kairo-v0.8.5-macos-universal.tar.gz`（含 `kairo` 与 `kairo-mcp`，arm64 + x86_64 通用二进制）及 `.sha256` 校验文件。接入智能体不再需要装 Swift 工具链编译，解包即可用。
- **持续集成**：新增 `.github/workflows/ci.yml`，push 与 PR 触发 macOS（测试 + 两道门禁）与 Linux（`swift:6.0-jammy`，验证 ADR-004 可移植性）双任务，README 挂 CI 徽章。
- **可选签名与公证**：发布流水线支持 Developer ID 签名 + `notarytool` 公证 + staple；未配置证书时整段跳过，未签名发布照常进行。所需 secrets 见 `CONTRIBUTING.md`。
- **英文文档**：新增 `QUICKSTART.md`、`ARCHITECTURE.md`、`CONTRIBUTING.md`、`SECURITY.md`、Issue / PR 模板；五张架构图改为中英双语生成（`tools/gen-arch-svg.py`，`KAIRO_SVG_LANG=en|zh`）。

### 修复

- **Linux 构建失败（#4）**：`Package.swift` 外层 `#if os(macOS)` 内嵌套同名条件，非 macOS 时 `updaterProduct` 未定义、清单编译失败。
- **核心层依赖 CoreFoundation（#5）**：`FormatDocument.parseVersion` 用 `CFGetTypeID` 判 JSON 布尔，Linux 无此符号；改用 `objCType`，行为不变。
- **测试目标硬依赖 Darwin / Process（#6）**：`InterfaceTests` 条件导入 Darwin/Glibc；`TaskHookTests` 依赖 `Process`，限定在 Darwin 主机执行。

## v0.8.4 — 2026-10-24

### 修复

- **甘特图双指横向平移无响应（D-027，F-14-18 回归）**：v0.6.0 交付的触摸板平移在真机上表现为「画布不动」，两轮排查后确认是四处串联闸门，逐条拆除：
  - **坐标同源**：视口改由 `CanvasViewportProbe`（NSView `convert(bounds, to: nil)`）上报 AppKit 窗口坐标，光标用 `window.convertPoint(fromScreen:)` 换算到同一空间；不再拿 SwiftUI `.global` 矩形比对 `locationInWindow`。
  - **单实例**：监听与平移上下文收敛为全进程单例（`HorizontalScrollMonitor.shared` / `HorizontalPanContext.shared`），视图重建只重复 `start()`（接管语义）。此前 SwiftUI 重复 `onAppear` 会叠出多个监听，且可能绑在已销毁实例上（视口恒 nil）。
  - **不按事件窗口身份判定**：`scrollWheel` 的 `event.window` 常为 nil、`keyWindow` 可能指向辅助窗口，改为「光标是否在画布视口内」定位。
  - **「编辑中」按光标落点判定**：SwiftUI 工作台窗口在没有任何输入框获得焦点时，首响应者仍是窗口共用 field editor，原判据会把每条滚动当成编辑中放行 —— 这是最后一处、也是最隐蔽的一处。
  - 判定抽为纯函数 `GanttScrollRouter`；连续滚动由 `advance(byDays:)` 就地推进窗口起点（不再反复派发同一目标），整天推进改用 `Calendar` 加法（跨 DST 安全）。
  - 现场诊断：新增 `os.Logger`（subsystem `ai.kairo.app` / category `gantt-pan`）记录安装、首个滚动事件（含视口/光标/是否命中）、每种放行原因与每次平移提交，可用 `log stream --predicate 'subsystem == "ai.kairo.app"'` 定位。
  - 验证：合成 `CGEvent` 横向滚动 + 光标定位跑通端到端（日志显示 8 次滚动 → 7 次整天提交，状态栏窗口区间由 10/23–… 移至 10/17–11/2）；新增 26 例用例（含事件级消费与「编辑中」判据），全量 768/768。

### 变更

- **更新面板改为标准面板形态**：图标徽章 + 标题 + 说明 + 详情 + 右对齐动作三段式（宽 400pt），替代原来「一行文字 + 好」的裸对话框；8 个状态各有语义图标与配色，`已是最新` / `已下载` 不再留空档，更新说明区限高可滚动、错误文案单列显示。
- **空项目去掉「通过 MCP 导入…」按钮**：MCP 是协议而非界面能力，WBS 导入由 AI 智能体在会话侧（MCP / CLI）完成；空态只保留「新建任务」一个入口，说明文案改为「或由 AI 智能体通过 MCP / CLI 导入现有 WBS」。

## v0.8.3 — 2026-10-23

### 新增

- **一键发版（`tools/release.sh`）**：`tools/release.sh 0.8.3` 一次完成发版全流程——前置校验（必须在 main、工作区干净、tag 不存在、版本递增、CHANGELOG 有对应章节）→ 同步三处版本号 → 全量测试 → 打包 → 提交 → annotated tag → 推送。`--dry-run` 只做校验、测试与打包，不动仓库。
- **产物打包抽为 `tools/package.sh`**：本地与 CI 同源，一次产出 `Kairo-<tag>.dmg`（挂载后拖入 Applications）与 `Kairo-<tag>.zip`（OTA 载体，ditto 保留签名）。打包前校验应用内 `CFBundleShortVersionString` 与 tag 一致——版本号漏改会在打包阶段直接失败，而不是把旧版本装进新版本附件。
- **Release 说明单一来源 `tools/release_notes.sh`**：CI 与本地共用同一段 CHANGELOG 抽取逻辑，Release 说明即 `CHANGELOG.md` 的对应章节；章节缺失时回退为自动生成的提交列表。

### 变更

- 发版工作流改为调用上述脚本：CI 内联的 zip / DMG / changelog 逻辑（三处重复实现）合并为一处，避免本地与线上产物口径漂移。

## v0.8.2 — 2026-10-23

### 修复

- **发版归档步骤加固（D-026）**：产物推送失败不再让整轮发版白跑。
  - `git push origin artifacts` 连续失败时重试 3 次（间隔 10 秒）；提交已生成，重试不产生冗余提交。同时抬高 `http.postBuffer` 并放宽低速判定，减少 408 / 断连概率。
  - `artifacts` 分支的 `latest/` 每次重建，只镜像当前版本；此前的 `Kairo-v0.3.1.*`、`Kairo-v0.4.0.*` 等历史残留随本次归档一并清除（`git add -Af` 记录删除）。
  - 同一 tag 重跑幂等：内容无变化时跳过提交，推送为 no-op 且判成功。

## v0.8.1 — 2026-10-23

### 修复

- **发版 CI 在 UTC runner 上整体错位一天（D-025）**：`Sprint8DateFieldRenderTests` 把日历钉死在 Asia/Shanghai，而被测的 `Display.isoDate` 与视图渲染使用 `TimeZone.current`，两者在 UTC 主机上相差一天，导致 4 条用例失败、v0.5.0 起的 tag 全部跑红。测试日历改为跟随主机时区（locale 与周首仍固定），断言与被测实现同口径。核销：`TZ=UTC swift test` 742/742。
- 由此确认：v0.5.0–v0.8.0 只存在于 CHANGELOG 与 git 历史，未发布过 GitHub Release；首个带产物的发布版本为 v0.8.1。

## v0.8.0 — 2026-10-22

### 新增

- **大纲列宽可调（F-14-20）**：表头每列右缘出现 6pt 调整手柄，拖动即可改列宽，双击复位默认宽。
  - 拖动中实时预览（表头与行同步）、松手才提交一次，不逐帧写偏好；位移 < 2pt 视为误触不提交。
  - 宽度区间按列区分：状态/违例 10–60、序号 18–80、其余 24–320；任务说明为弹性列继续吃余量（最小 120pt）。
  - 列宽持久化到视图偏好，**不进撤销栈、不把项目标记为已修改**。
- **列显隐可配置（F-14-20）**：视图菜单新增 8 条「显示/隐藏…列」，大纲表头右键菜单提供带勾选的同源开关。
  - **序号（#）与任务说明固定显示**，不出现在开关列表，隐藏请求双重忽略。
  - 窄窗阈值降级仍优先（放不下的列不会因用户配置强行显示）；聚焦标签栏忽略用户配置。
  - 显隐同样持久化、不产生撤销点。
- 表头与行列表统一 leading 锚定并加右侧裁切：列宽总和超过大纲宽度时从右侧裁切，不再出现表头居中导致的错列。

## v0.7.0 — 2026-10-22

### 新增

- **大纲「开始 / 结束」日期列可编辑（F-14-19）**：左侧大纲两列由只读文本改为点击即弹月历，快速选日期。
  - 开始列：写任务意图开始日期（可「清除」回落自动排期）；显示值仍是排期开始（与画布对齐），依赖可能使排期后移，单元格 tooltip 已说明。
  - 结束列：改写持续时间（结束为排他端点），最小可选日 = 起点次日；不允许清除。
  - 禁用语义与检查器一致：群组两列只读、里程碑结束只读、无排期时结束不可选，均以灰字 + tooltip 给出原因而不是静默无反应。
  - 写回动作与撤销粒度与检查器完全同源（`setTaskStart` / `setTaskFinish`，`task-start-*` / `task-finish-*`）；命令层零改动。
- 新增 `OutlineDateEditing` 纯函数策略（KairoPresentation）承载启用/原因/最小日判定，视图不写规则；跨 DST 日期以日历加法而非 +86400 秒推进。
- 设计稿与测试矩阵：docs/archive/Sprint10-outline-date-cells/design.md（17 例策略测试 + 2 例同源断言）。

## v0.6.0 — 2026-10-22

### 新增

- **甘特图横向平移（F-14-18）**：任务或依赖链超出视口时可左右移动时间窗查看前后日期。
  - 触摸板双指横向滑动直接平移（光标在画布内即生效；鼠标用户用 Shift + 纵向滚轮）。
  - 画布空白处按住拖拽平移，内容跟手；条体 / 端点 / 依赖线上的拖拽仍是 F-14-09 编辑行为，互不干扰。
  - 平移粒度为整天（布局契约）：滚动输入按亚日余量累积、跨整天才提交，慢速滑动不丢位移也不跳格；切换缩放档位时余量清零。
  - 平移自动退出「适合项目」，窗口起点按整天归一；Escape 可取消进行中的拖拽（已生效的平移不回滚，与表头拖拽一致）。
- 实现：`HorizontalPanAccumulator` 纯函数（KairoPresentation）、`PanDragSession` 拖拽状态机与 `HorizontalPanContext` 引用上下文（App 层）、`HorizontalScrollMonitor` 事件捕获薄层；命令层与 Store 复用既有 `.panWindow`，零改动。
- 设计稿：docs/archive/Sprint9-gantt-horizontal-pan/design.md；F-14-13 原「本期不做横向滚动条」约束改写（仍不做滚动条，横向平移由触摸板/拖拽承担）。

## v0.5.0 — 2026-10-21

### 新增

- **任务起止日期可自定义（F-14-10）**：检查器任务页「开始」「结束」两行可编辑，点击字段弹出月历（236×300）选择日期——月份导航、今天/选中/非本月/周末状态、越界日置灰、预览行「开始日 – 结束日 · N 天」、「今天 / 下周一 / +1 周 / 清除」快捷项、方向键/Return/Esc/Tab 键盘导航与 VoiceOver 标签；深浅色全部走 DesignTokens。
  - 「开始」写 `startDate`（用户意图锚点，可清除；群组只读；与计划开始相差 ≥1 天时副行显示计划开始）。
  - 「结束」写 `durationDays`（保持开始不变，落点为排他端点；里程碑/群组/无排期禁用并给出原因；结束早于开始不可达，Store 二次拒绝）。
  - 截止日期与项目开始/结束改用同一组件；行内日期统一 `YYYY-MM-DD`；每次编辑一步撤销，与画布拖拽撤销互不合并；提交时校验排期起点是否已变化（陈旧输入拒绝，不占撤销点）。
- **排期引擎消费 `startDate`（D-021 修复）**：显式开始日作为「开始不早于」下界参与前向传播（叶子任务与里程碑；群组仍由子任务聚合），ASAP/ALAP 选定安排统一收敛到该下界。**v0.4.0 中画布拖条改期实际不移动条体的缺陷随本项修复**——拖条、检查器、命令三条入口自本版起真正生效。
- **按日历日计算排期（夏令时修复）**：`addDays` / `daysBetween` 改为 Calendar 整日算术（小数天余量仍按秒折算）。跨夏令时的结束落点不再少一天，宽延恒为整数天；America/New_York 回拨/春令两侧均有自动化用例。

### 已知观感变化（升级必读）

- v0.4.0 期间由画布拖拽或命令写入、但因 D-021 从未生效的 `startDate`，自 v0.5.0 起会参与排期：相关任务可能前移、依赖链随之位移。**不做数据迁移**（无字段改写）；如不希望某个任务被钉住，可在检查器点「清除开始」。

### 已知限制（顺延 v0.5.1，均不阻断）

- **D-022**：给任务设置晚于项目窗口的开始日后，违例页出现错误级「任务无法安排：最晚开始早于最早开始」，文案未点明是用户输入导致（后向传播按裁定不变）。
- **D-023**：违例引擎仍以 86 400 秒换算持续时间，跨夏令时的时限窗口可能误报/漏报。
- **D-024**：同文件两个「无下界」哨兵取值不一致（`distantPast` vs epoch 0），无现实故障。
- **真机未验证**：popover 系统动画与屏幕边缘翻转、物理键盘事件与焦点环可见性、VoiceOver 实际播报顺序、系统 firstWeekday 真机渲染、窄窗排版。

### 门禁与证据

- `swift test`：**669 用例 / 69 套件全部通过**（v0.4.0 收尾基线 558 → 669，只增不减）；日志 `docs/archive/Sprint8-task-dates/logs/gate-*.log`。
- `tools/gate-core.sh` · `tools/gate-ui.sh` 通过；`swift build -c release -Xswiftc -warnings-as-errors` 通过（CI 口径）。
- 判据：[acceptance.md](docs/archive/Sprint8-task-dates/acceptance.md)（AC-S8-01…23）· 设计与裁定：[design.md](docs/archive/Sprint8-task-dates/design.md) · 范围：[scope.md](docs/archive/Sprint8-task-dates/scope.md)。
- 审查：[Sprint8-task-dates-review.md](docs/reviews/Sprint8-task-dates-review.md)（3 HIGH 全部修复并复跑；MEDIUM 修复 5 项、驳回 1 项经裁定、LOW 修 3 项）。
- 缺陷：[defects.md](docs/defects.md) D-021 已核销；D-022…D-024 顺延 v0.5.1。

## v0.4.0 — 2026-10-21

### 新增

- **甘特图直接编辑（F-14-09）**：画布支持拖条改期（日粒度吸附，显式锚定开始日期）、拖右端点改持续、拖左端点改开始（结束不变）；从条端点外环带拖出绘制依赖线（FS / lag 0，拖出方向决定前后驱，成环自动拒绝）；点选依赖线后按 Delete/Backspace 删除。拖拽中显示虚线预览与目标日期标签，松手生效，Escape 取消。
- 交互架构：`GanttHitTesting` 纯函数命中测试（KairoPresentation，区域表全分支单测）+ `CanvasDragSession` 引用语义节流状态机（100ms 节流、松手必提交末值、同值去重）；长拖拽多笔提交经撤销合并键（`canvas-move-*` / `canvas-resize-*`）并为一步撤销。命令层复用 `updateTask(id:patch:)` 与依赖动作，零改动。
- 对象适配：里程碑仅拖改期（菱形端点退化为条体）；群组聚合条不可拖（由子任务推导）；群组/里程碑仍可作依赖端点。
- 设计稿：docs/archive/Sprint7-gantt-direct-edit/design.md；ui-redesign §10「画布禁拖」约束随本特性解除。

## v0.3.1 — 2026-10-20

### 新增

- **OTA 自动检查**：启动后 5 秒静默检查一次，此后每 4 小时一次；静默语义 = 网络失败不打扰（手动检查可见失败态），发现未跳过的新版本才自动展示更新面板，同版本一次运行只弹一次。「跳过此版本」仍然有效。
- **产物仓库归档**：发版时 DMG / OTA 载体 zip / 签名清单自动提交到 `artifacts` 分支（按 tag 子目录 + `latest/` 镜像），主分支保持干净。
- 文档：US-E7-01 落 PRD Backlog（完成）；新增 docs/features/05-ota-updates.md（F-36 规格族）与 docs/archive/Sprint7-ota-updates/design.md（设计决策记录）；roadmap 补状态更新与 Sprint 7/8 计划。

## v0.3.0 — 2026-10-20

本版引入应用内 OTA 更新（通用更新模块 KairoUpdater，移植自 COFFER OTA 的安全设计）。

### 新增

- **应用内 OTA 更新**：应用菜单「检查更新…」手动检查（零网络姿态：无启动静默检查、无定时后台检查）。安全链路与 COFFER OTA 同构——Ed25519 签名清单（canonical JSON）验证、下载 zip SHA256 完整性校验、产物 CDHash 与清单比对、GitHub host 白名单 + 强制 HTTPS + 重定向拦截、防降级地板（minimumVersion）；下载完成后经确认弹窗退出替换并自动重启，支持「跳过此版本」（安全关键版本禁跳）。
- **通用更新模块 KairoUpdater**（独立库 target）：清单解析/验签、版本比较、端点白名单、网络层（协议注入、禁缓存）、8 态更新状态机、zip 安装器（非沙盒 detached 脚本替换协议：等退出→备份→替换→relaunch→result 握手），全部可独立测试；appId/公钥/feed/白名单经配置注入，可直接复用于其他 Apple 平台项目。
- Release 附件扩展：DMG（人装）之外新增 OTA 载体 zip 与签名清单 update-manifest.json（/releases/latest/download/ 永久链接即 feed）。

### 已知限制

- v0.2.0 及更早版本不含 OTA 客户端：需手动安装 v0.3.0 一次，此后版本即可应用内更新。
- 应用为 ad-hoc 签名（无 Apple 开发者证书）：首次打开需要在「系统设置 → 隐私与安全性」中点「仍要打开」，或执行 `xattr -cr /Applications/Kairo.app`。
- 视图偏好文件任一字段缺失或损坏会使**全部**偏好回落默认值（项目数据不受影响，Sprint 7 改为逐字段容错）。
- 「适合项目」在跨多年的超长项目下时间窗口无上限，逐日刻度绘制量偏大（Sprint 7 设上限）。
- 拖条改期、拖拽建依赖、多选、基线与资源视图未实现；依赖创建从检查器进入。

### 安装

1. 从本页附件下载 `Kairo-v0.3.0.dmg`。
2. 打开 DMG，把 `Kairo.app` 拖入「应用程序」（窗口内有 Applications 快捷方式）。
3. 首次打开：右键点按 → 「打开」，或按上面的已知限制放行 Gatekeeper。
4. 之后的新版本可直接在应用内「检查更新…」完成升级。

## v0.2.0 — 2026-10-20

本版聚焦文件与协作基础（格式版本契约、另存为、负责人、大纲编号前置）与甘特图时间轴的自由缩放。

### 新增

- 甘特图时间轴「日宽可自定义」：2–120 点/天连续可调，全轴由单一标量日宽驱动（每天等宽、每周等宽）；刻度粒度在启用自定义日宽时按实际日宽推导（≥18 逐日 / ≥6 逐周 / 其余逐月），预设档位与「适合项目」沿用既有粒度行为不变；标签不重叠、绘制量有界。入口为工具栏标尺弹出面板（滑杆 / ± 步进 / 档位芯片 / 重置）、缩放菜单步进项与 `⌘+` / `⌘-` / `⌘0`；自定义值持久化在视图偏好（`customDayWidth`），不改 `.kairo` 项目文件格式。
- CLI `task add/update` 增加 `--assignee`，MCP `task_add/task_update` 增加 `assignee` 属性：设置任务负责人，空串清空；与 Claude Code 协作时可填子智能体名（US-E1-02-A1…A4）。
- `task get` 文本输出渲染负责人行。
- 大纲「前置」列支持按大纲编号填写依赖（如 `1.1`、`1.1:fs`、`1.1:ss:1`），可与任务 ID 前缀混用；前置摘要同以大纲编号展示（US-E4-01-C1…C4）。
- 「文件 → 另存为…」（⇧⌘S）：另存为新 `.kairo` 文件并继续在新文件上工作，原文件不变；保存面板预填当前文件名，未保存项目按项目标题生成；写入当前最新格式版本（FR-FILE-SAVEAS-1…6）。
- `.kairo` 格式版本兼容：读取 1…当前版本并顺序迁移；读取更高版本或迁移失败时明确报错且不改动磁盘文件；保存与另存为恒写当前版本；CLI/MCP 打开结果报告磁盘版本与升级需求，保存结果报告写入版本与升级来源（FR-KAIRO-FMT-1…6）。

### 修复

- 负责人输入去除首尾空白，纯空白等价清空（D-004）。
- 计划视图大纲与甘特图纵向错位：大纲行分隔线改为行内自绘 overlay，不再占用 28pt 行布局空间；行数越多错位越明显的累积漂移消除，画布点击选中恢复逐行对齐（D-006）。

### 变更

- `KairoPresentation` 公共 API 变更：新增 `WorkspaceAction` case（`setCustomDayWidth` / `nudgeCustomDayWidth` / `clearCustomDayWidth`，外部穷尽 switch 需补 `default`）、`GanttSnapshot` 新增 `tickGranularity` 字段（init 参数可选，缺省由 `zoom` 派生，旧构造点源码兼容）。
- 应用启动不再默认加载示例数据：默认打开为空项目；「文件 → 载入示例项目」按需填充示例（有未保存修改时先确认）。

### 已知限制

- 应用为 ad-hoc 签名（无 Apple 开发者证书）：首次打开需要在「系统设置 → 隐私与安全性」中点「仍要打开」，或执行 `xattr -cr /Applications/Kairo.app`。
- 视图偏好文件任一字段缺失或损坏会使**全部**偏好回落默认值（含窗口布局与日宽自定义；项目数据不受影响，Sprint 7 改为逐字段容错）。
- 「适合项目」在跨多年的超长项目下时间窗口无上限，逐日刻度绘制量偏大（Sprint 7 设上限）。
- 拖条改期、拖拽建依赖、多选、基线与资源视图未实现；依赖创建从检查器进入。

### 安装

1. 从本页附件下载 `Kairo-v0.2.0.dmg`。
2. 打开 DMG，把 `Kairo.app` 拖入「应用程序」（窗口内有 Applications 快捷方式）。
3. 首次打开：右键点按 → 「打开」，或按上面的已知限制放行 Gatekeeper。

## v0.1.0 — 2026-10-18

第一个可安装版本。围绕「计划工作台」重设计完成 macOS 客户端重构。

### 新增

- **计划工作台**：大纲与时间画布逐行对齐、充满窗口；检查器三页（任务 / 项目 / 违例）、状态栏健康摘要、⌘K 命令面板。
- **可拖拽分界线**：大纲 ⇄ 甘特分界线可左右拖动调整宽度（320–640pt）并持久化；拖动时列表各列等比压缩，标题列吃剩余宽度。
- **列表显隐**：工具栏开关隐藏任务列表，时间画布占满主区。
- **「关于」面板**：应用菜单显示版本号 0.1.0 与编译时间。
- **甘特布局 v2**：月/年 + 日/周两级刻度、四型依赖直角折线路由、今天线、折叠群组汇总条、无排期标记、月缩放隐藏非工作带。
- **核心层地基**：项目摘要与健康度（加权进度、逾期口径、剩余天数）、大纲树（过滤/展开/群组聚合）、四型依赖 CRUD 与环校验、撤销用值快照。
- **会话写路径**：任务补丁 set/clear 语义、移动与父子环校验、级联删除（CLI / MCP 同步采用）、排期缓存按需重算、导出采用不重写磁盘。
- **外部更新检测**：前台每 2 秒比较磁盘 mtime，未保存时提示「重新载入 / 保留本地」。
- **撤销/重做**：50 步快照栈，连续输入 500ms 合并，删除群组、依赖变更可撤销。

### 修复

- 项目未设开始日期时排期落在 1970 纪元（D-003）：按最早任务开始日期推导并提示。
- 表头被分界线抬高、行被压到窗口中部的布局塌陷。
- 分界线拖动被滚动手势吞掉（改用 highPriorityGesture）。

### 已知限制

- 应用为 ad-hoc 签名（无 Apple 开发者证书）：首次打开需要在「系统设置 → 隐私与安全性」中点「仍要打开」，或执行 `xattr -cr /Applications/Kairo.app`。
- 拖条改期、拖拽建依赖、多选、基线与资源视图未实现；依赖创建从检查器进入。

### 安装

1. 从本页附件下载 `Kairo-v0.1.0.zip`。
2. 解压得到 `Kairo.app`，拖入「应用程序」。
3. 首次打开：右键点按 → 「打开」，或按上面的已知限制放行 Gatekeeper。
