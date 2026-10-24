# 多语言（v0.9.0）验收用例与判据

> 依据：[06-localization.md](./06-localization.md) §11、docs/defects.md（D-022/023/024）。本文件为**测试前置**产物：先于实现落盘，实现完成后逐条转绿。
> 口径：源语言 en（String Catalog `sourceLanguage: en`），译文 zh-Hans。本版只做阶段一；判据 4b（MCP 文案切英文）属 v0.10.0，本文件仅留位（A-05b）。

## 0. 通用口径（三条，全组共用）

**S1 无中文扫描口径**（A-01/A-06/F-01 共用，唯一实现 `tools/i18n-lint.sh`，已入库）：只统计 `Apps/macos/Sources` 的**字符串字面量**，注释内中文不算；匹配 `"[^"]*[一-龥][^"]*"`。退出码 0 通过 / 1 违规 / 2 用法或输入缺失。基线清单 `tools/i18n-whitelist.txt` 的语义是**待清理基线**而非永久豁免：新增即失败，已清理条目只提示不阻塞。脚本**没有跳过开关**（传 `--skip-catalog` 属未知参数 → exit 2）；`--require-catalog` 额外要求 Catalog 源文件，缺则 exit 2。故「该步骤绿」等价于「(a)(b)(c) 全验过」，不存在只验两项也算通过的路径。

**S2 豁免口径**：只有系统提供的文本（系统菜单栏项、服务菜单、系统标准按钮 `NSButton` 系统标题）可以留在白名单。**不得**包含 `AppDelegate.swift`（退出确认、保存失败两处 `NSAlert`）与 `Updater/UpdateSheet.swift`（错误行与按钮）。当前基线 404 条中这两文件占 8 + 25 条 —— 是**待清理债**，发布闸门要求归零（A-02）。

**S3 判定样式**：每条判据必须落到「一个断言 / 一条命令 + 期望输出」。类型：**自动**（`swift test` 内）、**半自动**（脚本 + 人工看结论，须给出命令与可核对输出）、**人工**（截图归档 + 检查表，不用于阻断）。

---

## A. 版本级判据展开（§11 的 1..6）

| ID | 用例 | 前置 | 步骤 / 判据 | 类型 | 工作项 |
|---|---|---|---|---|---|
| A-01 | 英文系统无中文残留（扫描） | 英文系统、构建产物 | `bash tools/i18n-compile.sh /tmp/kairo-lproj && bash tools/i18n-lint.sh --require-catalog --lproj-dir /tmp/kairo-lproj`（对 .app 产物则用 `--lproj-dir dist/Kairo.app/Contents/Resources`）；**期望** exit 0 且输出「(a) … 无新增」「(c) … 键与占位符一致」，**且** `bash tools/i18n-lint.sh --require-catalog --fail-if-whitelist-nonempty --lproj-dir <lproj>` exit 0（清零的**权威判定**）（基线条数随 F-0705 递减，**不写死数字**，以当日 lint 输出的「白名单内中文 N 条 / 已清理 M 条」为准；需要数字时用 `grep -v '^#' tools/i18n-whitelist.txt | grep -c '[^[:space:]]'`，**不要用 `grep -vc '^#'`——末尾空行会被计入，恒差 1**） | 自动 | F-0711 |
| A-02 | 豁免清单不含应用自写文案 | 同上 | `grep -c 'AppDelegate.swift' tools/i18n-whitelist.txt` == 0，`grep -c 'UpdateSheet.swift'` == 0；**期望** 两数均为 0（当前 8 / 25 → 必红，用于驱动 F-0705 收口） | 自动 | F-0711、F-0705 |
| A-03 | 八个界面英文目视归档 | 英文系统、.app | 逐界面截图存 `docs/archive/v0.9.0-i18n/`：主窗口/检查器/命令面板/菜单/状态栏/更新面板/退出确认/保存失败；**期望**：8 个文件存在，检查表 8 行全勾，任一格未勾即不通过 | 人工 | F-0705 |
| A-04 | 中文语义与 v0.8.5 一致 | F-0701 键-文案对照表 | 以表为基线逐条 diff；**期望**：差异条目数 == `CHANGELOG` 变更说明条目数，且每条含键名 + 理由；无理由的差异视为回归 | 半自动 | F-0701、F-0710 |
| A-05a | MCP 错误含 code 且 message 保持中文原样 | 见 E 组 | 以 E-01/E-02 全绿为准（本条不单独执行） | 自动 | F-0708 |
| A-05b | MCP 描述与 message 切英文、code 不变 | v0.9.0 已发布 + 一个版本窗口 | **v0.10.0 判据，本版不执行**：`tools/mcp-code-baseline.json` 逐条比对 code 集合相等；描述与 message 无 `[一-龥]` | 自动 | F-0714 |
| A-06 | 双 Locale 全量测试通过 | 干净工作树 | ① `swift test --disable-sandbox`；② `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 swift test --disable-sandbox`；**期望** 两次 exit 0、通过数相同、失败 0。另加产物冒烟（不阻断）：`dist/Kairo.app/Contents/MacOS/Kairo -AppleLanguages '(en)'` 与 `'(zh-Hans)'` 各起一次，界面语言随之切换 | 自动 + 半自动 | F-0710 |
| A-07 | 键完整性（两侧零缺键 + 占位符一致） | `.xcstrings` 入库 | 解析 Catalog：**期望** 每个键在 en/zh-Hans 均非空；两侧占位符集合相等；未翻译键数 == 0 | 自动 | F-0710、F-0711 |
| A-08 | 打包产物语言清单与资源 | G4 Catalog 已交付；`tools/build.sh` 产物（缺 Catalog/缺任一侧 .lproj 会 exit 1，属设计） | `plutil -p Kairo.app/Contents/Info.plist` 含 `CFBundleLocalizations = [en, zh-Hans]` 且 `CFBundleDevelopmentRegion = en`；`ls Kairo.app/Contents/Resources/*.lproj` 同时含 `en.lproj`、`zh-Hans.lproj`；`codesign --verify --deep --strict` exit 0 | 半自动 | F-0709 |

> **发布闸门（四条同时满足，任一不满足即阻断）**：① `bash tools/i18n-lint.sh` 全量（含 (c) 键与占位符）exit 0；② 白名单清零 `--fail-if-whitelist-nonempty` exit 0（需要数字时 `grep -v '^#' tools/i18n-whitelist.txt | grep -c '[^[:space:]]'` == 0；`grep -vc '^#'` 恒差 1，勿用）；③ 八界面截图 8/8 归档；④ 双 Locale 全量测试通过。

## B. 核心层（KairoCore）

| ID | 用例 | 前置 | 步骤 / 判据 | 类型 | 工作项 |
|---|---|---|---|---|---|
| B-01 | 违例 code 集合冻结 | v0.8.5 基线（`git show v0.8.5:Sources/KairoCore/Schedule/ViolationEngine.swift`） | 用 `Tests/Fixtures/violation-codes-v085.json` 比对：**期望** 产出 code 集合 == 基线 **7 个**：`cannot_schedule_asap_alap / constraint_is_dependency / constraint_is_prerequisite / constraint_window_too_narrow / cycle / task_ends_after_project_end / task_starts_before_project_start`，不多不少。**注**：v0.8.5 实测为 11 处 `message:` 站点对 7 个 code，方案 §3 写的「12 条」与实际差 1（多码复用），以本表实测数为基线 | 自动 | F-0703 |
| B-02 | 违例不再携带自然语言 | F-0703 | 构造每条规则各一例，遍历 `Violation` 所有 String 字段；**期望** 每个值匹配 `^[a-z0-9_.]+$` 或 UUID 形态，且不含 `[一-龥]` | 自动 | F-0703 |
| B-03 | 英文日期格式 | 注入 `Locale(identifier:"en_US")` | 对 2026-11-06 格式化：**期望** 输出 == `"Nov 6, 2026"`（正则 `^[A-Z][a-z]{2} \d{1,2}, \d{4}$`），且 `!contains("年")` | 自动 | F-0702 |
| B-04 | 中文日期格式不回退 | 注入 `zh_CN` | 同上日期：**期望** == `"2026年11月6日"`（与 v0.8.5 逐字一致） | 自动 | F-0702 |
| B-05 | 时长/数字本地化 | 两种 Locale | `duration(3)`：en 为 `"3 days"`（或 `3d`，与 F-0701 键表一致）；zh 为 `"3 天"`；**期望** en 侧无 `天/点`，两侧数字文本一致 | 自动 | F-0702 |
| B-06 | 核心层零本地化依赖 | — | 断言 `Sources/KairoCore`、`KairoCommands`、`KairoPresentation` 中 `Bundle.module` 出现次数 == 0（S1 同款扫描）；CI 同判据 | 自动 | F-0711 |

## C. 呈现层（KairoPresentation）

| ID | 用例 | 前置 | 步骤 / 判据 | 类型 | 工作项 |
|---|---|---|---|---|---|
| C-01 | 快照与 Locale 无关 | 固定测试用项目 | 用 en/zh 两个 Locale 各构建一次 `GanttSnapshot`+`StatusBarSnapshot`+`OutlineSnapshot`；**期望** 两次结果 `==`（Equatable 逐字段相等）。改造前必红，用于证明快照仍在拼文案 | 自动 | F-0704 |
| C-02 | 缩放标签语义枚举 | F-0704 | `zoomLabel` 为枚举而非 String：**期望** rawValue 集合 == `{custom, fit, day, week, month}`；视图侧映射表覆盖全部 5 个 case（无 `default:` 兜底） | 自动 | F-0704 |
| C-03 | 违例原因语义化 | F-0704 | 快照违例原因字段为 `(kind: String, days: Int?)` 形态：**期望** kind 取值属冻结集合，且不含 `[一-龥]`；`days` 与核心参数一致 | 自动 | F-0704 |
| C-04 | 日宽读数改为数值 | F-0704 | 状态栏快照日宽字段为 `Double`；**期望** 该类型无 String 字段承载 `点/天`；渲染函数由视图层提供（`dayWidthPoints == 12.5` 精确断言） | 自动 | F-0704 |

## D. CLI（KairoCLI）

| ID | 用例 | 前置 | 步骤 / 判据 | 类型 | 工作项 |
|---|---|---|---|---|---|
| D-01 | `--lang en` 生效 | 临时项目文件 | `kairo task add T --lang en --file f.kairo`：**期望** stdout 无 `[一-龥]`，退出码 0；`--lang zh-Hans` 时 stdout 含中文且语义与 v0.8.5 一致 | 自动 | F-0707 |
| D-02 | `KAIRO_LANG` 生效 | 同上 | 仅设 `KAIRO_LANG=en`：**期望** 输出英文；未设时 == 系统语言 | 自动 | F-0707 |
| D-03 | 优先级 命令行 > 环境 > 系统 | 同上 | `KAIRO_LANG=zh-Hans` + `--lang en`：**期望** 输出英文（逐字节等于 D-01 的 en 输出）；三者三组组合各一断言 | 自动 | F-0707 |
| D-04 | `--json` 字节一致 | 同一 .kairo 文件 | `task list --json` 分别以 `--lang en` / `--lang zh-Hans` / `KAIRO_LANG=en` / 不设 四种跑：**期望** 四份 stdout ~`Data~` 完全相等（现有 `.sortedKeys` 编码已保证键序） | 自动 | F-0707 |
| D-05 | 退出码 0/1/2 不变 | 见 G-01 | 成功命令=0、缺失文件=1、未知选项/未知命令/非法 `--lang`=2；**期望** 上述结论在 en/zh 两语言下一致（同一断言表跑两遍） | 自动 | F-0707 |
| D-06 | `--lang` 位置无关 | 同上 | `kairo task list --lang en` 与 `kairo --lang en task list`：**期望** 两者 stdout 字节相等且均不触发「未知选项」退出码 2 | 自动 | F-0707 |

## E. MCP（阶段一）

| ID | 用例 | 前置 | 步骤 / 判据 | 类型 | 工作项 |
|---|---|---|---|---|---|
| E-01 | 22 处错误均带 code | 参数错误矩阵 | 逐条构造非法 `tools/call`（缺参、UUID 非法、日期非法、枚举非法、类型非法…），断言响应 `isError==true` 且 `content[0].text` 解析出的 `code` 非空、匹配 `^[a-z0-9_.]+$`；**期望** 覆盖 22 条 throw 点，每条至少一个请求 | 自动 | F-0708 |
| E-02 | message 与 v0.8.5 逐字一致 | 基线 fixture `Tests/Fixtures/mcp-errors-v085.json`（code→message） | 同一请求下 `message` 与基线 `==`（逐字，含中文标点与全角括号）；**期望** 差异数 == 0 | 自动 | F-0708 |
| E-03 | 任意 LANG 下字节一致 | 子进程启动 `kairo-mcp` | `LANG=en_US.UTF-8` 与 `LANG=zh_CN.UTF-8` 下发同一 JSON-RPC：**期望** stdout 字节相等（含 `tools/list` 与一次 `tools/call` 错误） | 自动 | F-0708 |
| E-04 | 协议结构不变 | 同上 | 响应顶层键集合 == `{jsonrpc,id,result}`；错误响应 `result` 键集合仍为 `{content,isError}`，`code` 在 `content[0].text` 内而非新增顶层键；**期望** 旧 consumer 文本匹配仍可命中（`message` 含原中文子串） | 自动 | F-0708 |

## F. 视图层（Apps/macos）

| ID | 用例 | 前置 | 步骤 / 判据 | 类型 | 工作项 |
|---|---|---|---|---|---|
| F-01 | 八个界面无中文 | 英文系统 + .app | 见 A-01 扫描 + A-03 截图；**期望** 两路结论一致，任一界面扫描命中即红 | 半自动 | F-0705 |
| F-02 | 三处非豁免弹窗必须英文 | 英文系统 | 触发退出确认、保存失败、更新面板错误行：**期望** A-01 扫描对 `AppDelegate.swift`、`UpdateSheet.swift` 命中数 == 0（S2 已禁止其进白名单） | 自动 + 人工核对 | F-0705 |
| F-03 | 示例项目按界面语言生成 | 两种界面语言各一次 | `SeedData.makeProject(language:)`：**期望** `.en` 时所有 title/notes/tags 无 `[一-龥]`；`.zh` 时与 v0.8.5 逐字一致；两者任务数、依赖结构、日期偏移相同（结构一致性断言） | 自动 | F-0705 |
| F-04 | 示例写入后不再随语言重写 | 已载入示例的项目文件 | 以 en 建项目 → 切 zh 重启 → 读文件：**期望** 文件字节不变（用户数据不改写） | 自动 | F-0705 |
| F-05 | 英文环境日期与单位 | 英文系统 | 主窗口/检查器/甘特表头渲染取文本：**期望** 无 `年/月/日/点` 单位中文，月份为英文缩写 | 半自动 | F-0712 |
| F-06 | 菜单与状态栏 | 英文系统 | 应用自建菜单项标题（`CommandRegistry`）集合 ∩ 中文 == ∅；系统项允许中文（系统语言为中文时）**期望** 扫描命中仅落在白名单系统项 | 半自动 | F-0705 |

## G. 负路径与边界

| ID | 用例 | 前置 | 步骤 / 判据 | 类型 | 工作项 |
|---|---|---|---|---|---|
| G-01 | 非法 `--lang` | 临时项目 | `--lang fr` / `--lang zh_CN`（非 BCP-47）/ `--lang ""`：**期望** 退出码 2、stderr 非空且列出允许值、进程不崩溃、不落任何文件 | 自动 | F-0707 |
| G-02 | 非法 `KAIRO_LANG` | 同上 | `KAIRO_LANG=xx`：**期望** 静默回退系统语言（退出码 0，输出与不设 env 逐字节一致），不因 CI 环境变量炸掉 | 自动 | F-0707 |
| G-03 | 本地化资源缺失 | 先 `bash tools/build.sh` 出包（**包内只有 .lproj，源 .xcstrings 不进包**） | `rm -r dist/Kairo.app/Contents/Resources/zh-Hans.lproj` 后启动：**期望** `Bundle.preferredLocalizations` 回落到 `CFBundleDevelopmentRegion = en`；未命中的键显示调用点英文兜底，不出现键名形态文本（正则 `^[a-z]+(\.[a-z_]+){2,}$`） | 半自动 | F-0709 |
| G-04 | 缺键回退 | 拷贝 Catalog 到临时目录（**文件名必须保持 `Localizable.xcstrings`**，表名由文件名生成） | 删掉某键的 zh 译文、**保持 en 侧 `"state": "translated"`**，再 `i18n-compile.sh /tmp/g04-out /tmp/g04/Localizable.xcstrings` + `i18n-lint.sh --require-catalog --lproj-dir /tmp/g04-out`：**期望** lint exit 1 且报「键缺少 zh-Hans 译文：<键名>」；把 state 误写成 `new` 会让 en 侧也丢键、缺键检不出来（fixture 无效）。**另一情形**：一条 zh 译文都没有时不会生成 zh-Hans.lproj → exit 2（缺 lproj），同样是红 | 自动 | F-0710 |
| G-05 | 两侧缺键为零 | Catalog 入库 | 见 A-07 同一实现，作为发布闸门单独报数 | 自动 | F-0710 |
| G-06 | 占位符数量与类型匹配 | 同上 | 对含 `%n$` 的键：两侧占位符多重集合相等；**期望** 不匹配键数 == 0 | 自动 | F-0710 |
| G-07 | OTA 升级后资源仍命中 | 已装 v0.8.5 的机器 | 走更新流程整包替换到 v0.9.0 → 英文系统启动：**期望** A-01 扫描命中 0、`preferredLocalizations.first == "en"`、8 界面检查表与 A-03 一致 | 半自动 | F-0709 |

## H. 上版缺陷回归（D-022 / D-023 / D-024）

| ID | 用例 | 前置 | 步骤 / 判据 | 类型 | 工作项 |
|---|---|---|---|---|---|
| H-01 | **D-022** 项目窗口外开始日不再误归因依赖 | projectStart=11-02、projectEnd=11-05；任务 `startDate=11-20`；ASAP 与 ALAP 各一次 | 打开违例：**期望** 违例 code == 新增 `start_after_project_window`（或裁定为不报错则集合为空），且**不含** `cannot_schedule_asap_alap`；文案点明「开始日期晚于项目可排窗口」 | 自动 | F-0715 |
| H-02 | **D-023** 跨 DST 时限窗口与日历日一致 | 时区 `America/New_York`；任务跨 2025-11-02 回拨日、duration=3、含 `startNoLaterThan` | 同构场景分别构造在 DST 周与非 DST 周：**期望** 两次违例 code 集合**完全相同**（当前实现因 86400 差 1 小时而分叉） | 自动 | F-0716 |
| H-03 | **D-024** 无下界哨兵统一 | — | `ScheduleEngine.startDateLowerBound` 与 `constraintStartLowerBound` 在无约束输入下：**期望** 返回值 `==`，且等于具名常量（`Date.distantPast`），源码中不再出现 `Date(timeIntervalSince1970: 0)` | 自动 | F-0717 |
| H-04 | D-022 反向（防过修） | 同在窗口内的合法 `startDate`（11-03） | **期望** 不产生 `start_after_project_window`，排期结果与改动前逐位一致 | 自动 | F-0715 |
| H-05 | D-023 反向（防过修） | 时限确实容纳不下 duration（窗口 1 天、duration 3） | **期望** 仍产生 `constraint_window_too_narrow`，且消息天数参数为 1 / 3 | 自动 | F-0716 |
| H-06 | D-024 行为不变 | v0.8.5 排期黄金基线 | 无下界输入的排期结果与基线逐位比对：**期望** 差异 0（只允许哨兵取值变化，不允许排期变化） | 自动 | F-0717 |

---

## 前置问题（实现前必须先定，否则对应用例无法判定）

1. **`--lang` 必须是全局选项**：现每条命令各自 `rejectUnknown([...])` 白名单（`Sources/KairoCLI/CLIOptions.swift:42`），若只在单命令白名单里加，D-06（位置无关）必红。需在路由前统一抽取并统一放行。
2. **C 组依赖 F-0704 先落地**：当前 `Presenter.zoomLabel` 与日宽读数直接拼中文（`Sources/KairoPresentation/Presenter.swift:761-780`），C-01「en 快照 == zh 快照」在改造前必然失败——需确认 F-0704 排期早于本组转绿。
3. ~~D-022/023/024 本版无工作项~~ **已裁定（2026-10-24）**：三项纳入本版，编号 F-0715（D-022）/ F-0716（D-023）/ F-0717（D-024），H 组 6 条按「本版必修」执行，不再作顺延表述。
