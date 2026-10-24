# 多语言支持（先英文）· 方案与任务拆分

> 版本 0.5 · 2026-10-24 · 状态：方案（已评审；v0.9.0 开工中）· 归属版本：v0.9.0（阶段一）/ v0.10.0（阶段二）
> 本版回填：F-0700 实测结论（§7.1 三条事实与主路径 B）、§4 取词与门禁规约、CLI 语言回退定为 zh-Hans、F-0715 码名统一为 `schedule_start_after_project_window`。
> 上版追加：F-0715 / F-0716 / F-0717 承接缺陷登记表顺延项 D-022 / D-023 / D-024。
> 上游依据：[02-architecture.md](../02-architecture.md) 的 ADR-004（核心层零 UI 依赖）与 ADR-013（唯一写路径 + 快照边界）、[04-glossary.md](04-glossary.md)（术语）
> 本文只定方案与任务拆分，不含实现代码。

## 1. 背景与范围

Kairo 的界面文案当前是硬编码中文。仓库的对外形象已英文化（README、架构图、发布说明），但产品本身仍是单语，英文用户装完之后面对中文界面。

**盘点口径**：两个口径同时给出，避免混用。

```bash
grep -rho '"[^"]*[一-龥][^"]*"' <目录> --include=*.swift | wc -l          # 行口径（未去重）
grep -rho '"[^"]*[一-龥][^"]*"' <目录> --include=*.swift | sort -u | wc -l  # 去重口径
```

行口径含重复与注释中的字符串片段，属上界；去重口径用于估算翻译工作量。统计提交为 03fb63b（v0.8.5）。

| 位置 | 行 | 去重 | 说明 |
|---|---|---|---|
| `Apps/macos/Sources` | 461 | 344 | 25 个文件含中文字符，其中 **17 个**含中文字符串字面量，另 8 个仅注释含中文 |
| `Sources/KairoCLI` | 111 | 99 | 用法说明、回执 |
| `Sources/KairoMCP` | 42 | 37 | 工具描述、JSON-RPC 错误 |
| `Sources/KairoCommands` | 30 | 18 | `KairoSession` 的会话错误与提示 |
| `Sources/KairoPresentation` | 19 | 17 | 快照派生文案（违例原因、缩放标签、每天点数） |
| `Sources/KairoCore` | 88 | 82 | `ViolationEngine` 20（规则名 + 消息模板）、`SeedData` 31（示例项目模板）、其余为日期与校验错误 |
| `Sources/KairoUpdater` | 49 | 49 | 全部是面向用户的 `errorDescription`，会原样出现在更新面板 |
| `Tests` | 1028 | 625 | 其中 `#expect` 含中文的断言 327 条（App 187 / Presentation 81 / Core 38 / Interface 18 / Updater 3） |

本方案的源语言为**英文**：String Catalog 的 `sourceLanguage` 为 `en`，键用语义命名，中文作为 `zh-Hans` 译文。代码评审看到英文键，不出现中文键名。

## 2. 目标与非目标

目标（版本级，可测）：

1. 系统语言为英文时，应用主窗口、检查器、命令面板、菜单、状态栏、更新面板无中文残留。
2. 系统语言为简体中文时，文案语义与 v0.8.5 一致；差异逐条落在变更说明中。
3. CLI 支持 `--lang` 与 `KAIRO_LANG`，`--json` 输出与语言设置无关。
4. MCP 分两步收敛：阶段一（v0.9.0）错误携带稳定 `code` 且 `message` 保持中文；阶段二（v0.10.0）工具描述与错误消息切英文，`code` 不变。
5. 全量测试在中文与英文两种 Locale 下均通过；CI 阻止新增未登记的硬编码中文。

非目标：

- 除中英之外的语言（架构留位，不做交付）。
- 运行中即时切换语言（列为可选，见 §5）。
- 用户数据不翻译：`.kairo` 内的任务标题、备注、标签一旦写入即视为用户数据。
- 报告输出（Markdown 叙述）的语言由调用方决定，本期不约束。

**示例项目模板（`SeedData`）的决策**：模板属于产品生成内容，不属于用户数据。交付口径为「**按创建时的界面语言生成**」：界面为英文时载入英文示例任务，界面为中文时载入中文示例任务；写入之后即按用户数据处理，不再随语言变化重写。这样既避免英文用户首次新建就看到中文任务名，也不引入「同一文件两种语言」的歧义。

## 3. 分层职责与字符串归属

| 层 | 持有文案 | 现状 | 规则 |
|---|---|---|---|
| `KairoCore` | 否 | `ViolationEngine` 产出 12 条中文消息模板；日期按中文拼接 | 改为「规则码 + 参数」；日期格式化接受注入的 `Locale` |
| `KairoCommands` | 否 | 会话错误是中文整句 | 改为「错误码 + 参数」，不拼接自然语言 |
| `KairoPresentation` | 否 | 快照已携带中文：缩放标签、每天点数、违例原因 | 快照只带语义枚举与参数，例如 `reason.overdue(days: 3)` |
| `KairoUpdater` | 否（禁入 Catalog） | 49 行 `errorDescription` 全为中文 | 改为错误码，由更新面板视图翻译；不进 Catalog，避免与视图层文案双源 |
| 视图层（`Apps/macos`） | 是 | 344 行硬编码中文 | 唯一翻译点；装饰性文案可就地翻译 |
| CLI / MCP | 是（受 §6 约束） | 各自为中文 | 各自渲染，不与视图层共享文案表 |

**硬约束**：`KairoCore`、`KairoCommands`、`KairoPresentation` 必须不引入本地化资源（不得出现 `Bundle.module`），且必须在 Linux 编译。此约束由 CI 强制（F-0711）。

理由：快照是跨层公共契约，已被 UI、CLI、MCP 三端消费。若快照携带中文文本，CLI 与 MCP 的语言策略就被呈现层绑死。

## 4. 本地化机制

采用 **String Catalog（`.xcstrings`）作为唯一源文件**，构建期编译成 `.lproj` 装进 `.app`（加载路径的实测结论见 §7），运行期不读 Catalog。

| 方案 | 取舍 |
|---|---|
| String Catalog | 单一文件承载全部语言、可在 Xcode 内逐条审校、`sourceLanguage` 元数据与键同源；运行期需编译产物（§7） |
| `Localizable.strings` | 兼容性最好，但语言分散在多个 `.lproj` 目录，缺少统一的审校视图与键状态 |
| 自建键值表 | 失去系统语言协商与格式化能力，等于自造 i18n |

**取词入口**（唯一，`Apps/macos/Sources/Workspace/I18n.swift`）：

```swift
enum I18n {
    static func t(_ key: String, _ en: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: key, value: en, table: nil)
    }
    /// 位置参数（%1$ld / %2$@），避免语序差异。
    static func t(_ key: String, _ en: String, _ args: CVarArg...) -> String {
        String(format: t(key, en), arguments: args)
    }
}
```

调用形如 `I18n.t("column.status", "Status")`、`I18n.t("palette.result.count", "%1$ld tasks", count)`、`I18n.t("violation.rule.\(code)", fallbackName(for: code))`。

**为什么带英文兜底**：`swift run` / `swift test` 的产物里没有 `.lproj`（§7 的 E1/E2），`String(localized:)` 取不到值。统一走 `localizedString(forKey:value:table:)` 后，`.app` 内命中 Catalog 显示译文，未命中则显示调用点写的英文——任何情况下都不会把裸键显示给用户。代价是英文文案存在两处（Catalog 与调用点），由 F-0711 的键检查与评审保证不漂移。

**键命名规约**（v0.9.0 起冻结，只增不改）：`<域>.<对象>.<语义>`，域限 `menu` / `outline` / `inspector` / `palette` / `statusbar` / `update` / `alert` / `error` / `column` / `action` / `date` / `unit` / `violation.rule` / `seed`，例如 `inspector.task.effort`、`palette.command.schedule_compute`、`error.dependency.cycle`、`violation.rule.schedule_cycle`。占位符一律用位置参数（`%1$ld`），不用具名插值，避免语序差异；两侧语言的占位符必须同位置同类型。

复数用 String Catalog 的 variations 表达（编译后落入 `.stringsdict`），例如：

```
palette.result.count = "%1$ld task"
  variations:
    en:  one → "%1$ld task" / other → "%1$ld tasks"
    zh-Hans: other → "%1$ld 个任务"
```

**机器门禁**（`tools/i18n-lint.sh`，CI 与本地同跑，详见 §7；(d) 只在发版前置校验里启用）：

| 检查 | 拦截对象 | 退出码 |
|---|---|---|
| (a) 硬编码中文 | `Apps/macos/Sources` 出现白名单（`tools/i18n-whitelist.txt`）外的中文字符串字面量（注释内中文不计） | 1 |
| (b) 分层资源 | `KairoCore` / `KairoCommands` / `KairoPresentation` 出现 `Bundle.module` | 1 |
| (c) 键完整性 | `en` 与 `zh-Hans` 两份 `.lproj` 的键集合不同，或同一键的占位符位置/类型不同 | 1 |
| (d) 发布闸门 | 白名单仍有条目（仅 `--fail-if-whitelist-nonempty`，由 `tools/release.sh` 调用，不接 CI 常跑） | 1 |

0 = 通过，2 = 用法错误或输入缺失（缺 Catalog、缺 `.lproj`、缺白名单）。**脚本没有「跳过某一项」的开关**：CI 用 `--require-catalog`，Catalog 源文件缺失即失败（`::error` + 红），不以跳过代替。

## 5. 语言切换

设置项三档：跟随系统 / 简体中文 / English。选择持久化到应用偏好，非法或缺失值回退「跟随系统」。

生效路径：**切换后重启生效**。菜单栏常驻应用的视图重建路径分散（主窗口、面板、弹窗、菜单），运行中热切换需要为全链路注入 `locale` 并强制重建；本期列为可选，待前置验证 P2 有结论后再评估。

## 6. 接口面契约（CLI / MCP）

| 面 | 策略 | 判据 |
|---|---|---|
| CLI 人类输出 | 默认跟随系统语言；`--lang <bcp47>` 与 `KAIRO_LANG` 可钉死；优先级：命令行 > 环境变量 > 系统。**系统语言不可判定时回退 `zh-Hans`**——阶段一不得破坏既有中文脚本，英文用户显式传 `--lang en` 或设 `KAIRO_LANG=en`；`--lang` 值非法按用法错误退出 2 | 中英两种语言下回执与用法说明正确，退出码语义不变（0 成功 / 1 运行时 / 2 用法） |
| CLI `--json` | 键与值均与语言无关 | 任意语言设置下输出字节一致 |
| MCP 错误 | **两阶段**：阶段一补稳定 `code`、`message` 保持中文原样；阶段二把 `message` 切英文 | 阶段一：错误响应同时含 `code` 与原中文 `message`，既有文本匹配不被破坏；阶段二：`message` 为英文且 `code` 不变 |
| MCP 工具描述 | 阶段二一次性切英文（当前 16 条全中文） | 任意宿主语言下描述字节一致 |

**为什么分两步**。MCP 描述与错误文本会进入模型上下文，用户的 `CLAUDE.md` / `AGENTS.md` 里可能写了「当返回『该依赖会形成相关性环』时改依赖」这类依赖原文的指令。一次切换会让这类匹配静默失效。分两步后，阶段一先提供稳定 `code`，消费者有一个版本的窗口迁移；阶段二切文案时，破坏点已经可以被自愿规避。

**已知的、无法规避的代价**（阶段二发生时）：

1. 工具描述进入上下文，首轮提示词缓存失效一次；
2. 中文指令中直接引用中文错误原文的用法会失效——这是本方案唯一真实的破坏点，阶段二必须在 CHANGELOG 显著标注；
3. 描述改英文后，模型对中文用户回复中文的倾向会略微下降。

**做不到的事**：当前 MCP 实现是最小 stdio JSON-RPC，没有语言协商字段，无法按客户端语言返回不同描述。要么全英文，要么全中文，没有中间态。

## 7. 打包、清单与资源加载

### 7.1 实测结论（F-0700，已定论）

环境：macOS 26 / Swift 6.3.1 / tools-version 5.9。

| # | 实测 | 后果 |
|---|---|---|
| E1 | `resources: [.process("Resources")]` 对 `.xcstrings` 只原样拷贝、不编译，产物 `localizations == []` | 「Catalog 进 target + `Bundle.module`」不通 |
| E2 | SwiftPM 生成的 resource bundle 无 `Info.plist`，`preferredLocalizations` 恒为 `["en"]`，显式 `locale:` 也不生效 | 资源宿主必须是自建 `.app` |
| E3 | `.app` + `Contents/Resources/{en,zh-Hans}.lproj` + 清单含 `CFBundleDevelopmentRegion=en` 与 `CFBundleLocalizations`：`preferredLocalizations`、`String(localized:)`、复数 `%1$ld` 全对，`-AppleLanguages` 可钉死 | 定为唯一路径 |

**结论**：本文档上一版的默认假设「Catalog 进 target、按 `Bundle.module` 命中」**判否**（E1/E2），改用主路径 B。`.xcstrings` 不进任何 target 的 `resources` 声明，`Package.swift` 不需要改动。

### 7.2 主路径 B（已实施）

```
Apps/macos/Resources/Localizable.xcstrings        # 唯一源文件
  → tools/i18n-compile.sh <输出目录>              # xcrun xcstringstool compile
  → <输出目录>/{en,zh-Hans}.lproj/{Localizable.strings, Localizable.stringsdict}
  → tools/build.sh：codesign 之前拷进 Kairo.app/Contents/Resources/
  → 运行期 Bundle.main 取词（§4），未命中时回退调用点写的英文
```

**表名约束**：`xcstringstool` 按 Catalog 文件名生成表名（`Localizable.xcstrings` → `Localizable.strings`），而运行期取词走 `Bundle.localizedString(forKey:value:table: nil)`，只读 `Localizable` 表。因此 `tools/i18n-compile.sh` 直接拒绝非 `Localizable.xcstrings` 的文件名——改名不会报错，只会让界面静默退回英文兜底。

`tools/build.sh` 的四处改动：

1. `CFBundleDevelopmentRegion` 由 `zh_CN` 改为 `en`；
2. 新增 `CFBundleLocalizations` 数组，声明 `en` 与 `zh-Hans`；
3. 拷可执行文件之后、`codesign` **之前**把两个 `.lproj` 拷进 `Contents/Resources/`——资源必须在签名覆盖范围内，OTA 是整包替换，升级后仍需命中（R4）；
4. 缺 Catalog 或缺任一 `.lproj` 直接 `exit 1`，不静默回退成单语包。

### 7.3 判据

```bash
bash tools/i18n-compile.sh /tmp/lproj                 # 产出 en / zh-Hans 两个 .lproj
bash tools/build.sh                                   # 打包（内部会重新编译并拷入 .app）
plutil -p dist/Kairo.app/Contents/Info.plist | grep -A3 CFBundleLocalizations
ls dist/Kairo.app/Contents/Resources | grep lproj     # 应有 en.lproj 与 zh-Hans.lproj
bash tools/i18n-lint.sh                               # (a)(b)(c) 全过
```

语言协商（两条各启动一次，界面文案随之切换；系统「语言与地区」不改也能判定）：

```bash
dist/Kairo.app/Contents/MacOS/Kairo -AppleLanguages '(en)'
dist/Kairo.app/Contents/MacOS/Kairo -AppleLanguages '(zh-Hans)'
```

### 7.4 副作用与不做的事

- `swift run` / `swift test` 下没有 `.lproj`（E1/E2），所以文案一律走 §4 的英文兜底取词函数，否则裸跑会显示裸键；
- 不把编译后的 `.lproj` 提交进仓库：同一文案两个源，必然漂移；
- CLI 不用 Catalog：`dist/KairoCLI` 是裸可执行文件、无 `Info.plist`，没有 `.lproj` 宿主（与 E2 同类结论），语言由 `--lang` / `KAIRO_LANG` / 系统语言决定（§6）。

## 8. 测试策略

现状：327 处 `#expect` 含中文字面量（口径见 §1）。

改造原则：

1. **断言语义，不断言措辞**：优先断言错误码、语义枚举、快照字段；涉及人类可读文本处，断言「键存在且占位符个数一致」。
2. **保留少量文案契约测试**：键完整性、两侧零缺键、占位符匹配。
3. **分类先行**：F-0713 逐条分类（需跟译 / 应改语义 / 应删），产出清单后再估 F-0710 的工作量；F-0713 在 F-0701 之后即可启动，不必等视图接入。

**「无中文残留」的豁免只限系统提供的部分**：系统菜单栏项、服务菜单、系统标准按钮。以下位置由应用自己写文案，**不得**豁免，必须在 F-0705 范围内：

- 退出确认弹窗（`AppDelegate` 中 `NSAlert` 一处）
- 保存失败弹窗（`AppDelegate` 中 `NSAlert` 一处）
- 更新面板（`UpdateSheet`）的错误行与按钮

## 9. 迁移与落地路径

按层推进，不发布半本地化中间态：

```
F-0700 资源实验 → F-0701 键规范 → F-0713 断言分类（与后续并行）
  → F-0702 核心日期 / F-0712 视图日期 → F-0703 错误语义化（含 Updater）→ F-0704 快照语义化
  → F-0705 视图接入 → F-0707 CLI / F-0708 MCP 错误码 → F-0709 打包 → F-0706 切换
  → F-0710 测试改造 → F-0711 文档与门禁
  ── v0.9.0 发布 ──
  → F-0714 MCP 文案切英文 → v0.10.0 发布
```

发布分两次 MINOR，不合并：

| 版本 | 内容 | 闸门 |
|---|---|---|
| v0.9.0（阶段一） | 视图层与 CLI 双语、更新面板、`KairoUpdater` 错误码化、MCP 错误补 `code`（`message` 保持中文）、示例模板按语言生成 | 视图层中文清零、测试双 Locale 通过、MCP 错误同时含 `code` 与中文 `message`、更新面板无中文 |
| v0.10.0（阶段二） | MCP 工具描述与错误 `message` 切英文 | 阶段一已发布且经过一个版本窗口；`code` 无变化；CHANGELOG 显著标注文案变更 |

## 10. 任务拆分

规模：S ≈ 半日、M ≈ 跨文件中等改造、L ≈ 跨层或需前置验证。

| ID | 任务 | 依赖 | 验收判据 | 规模 |
|---|---|---|---|---|
| F-0700 | 资源加载前置实验 | — | **已定论（见 §7.1，判据回填）**：原判据「Catalog 进 target、`Bundle.module` 可命中」**判否**（E1 只拷贝不编译 / E2 resource bundle 无 Info.plist）；实测通过的是 E3——`.xcstrings` 只作源，`xcstringstool` 编出 `.lproj` 装进 `.app` + 清单声明两语言，`preferredLocalizations`、`String(localized:)`、复数与 `-AppleLanguages` 全对 → 采用主路径 B（§7.2） | S |
| F-0701 | 字符串清单与键命名规范 | F-0700 | 清单按 §1 五类位置分册；键规范抽样 20 条评审无歧义；产出 v0.8.5 的键-文案对照表（作为 §11 判据 2 的基线）。规约已落 §4：域清单（14 个）、`<域>.<对象>.<语义>`、位置参数占位符、唯一取词入口 `I18n.t(key, en)` 及其英文兜底理由；机器校验见 §4 的三道门禁 | M |
| F-0702 | 核心层日期与数字格式化收敛 | F-0701 | 注入 `en_US` 时无「年月日」；`zh_CN` 下语义等价；Linux 编译通过 | M |
| F-0712 | 视图层日期与单位格式化收敛 | F-0701（与 F-0702 可并行） | 改造清单：`Display` 的 `dateFormatter` 与 `shortDateFormatter` 改为按注入 `Locale` 走 `setLocalizedDateFormatFromTemplate`；`monthTitle` / `weekdaySymbols` / `dayLabel` / `duration` 四个拼接函数改用本地化 API；`TimelineView` 预览日期、`CommandRegistry` 两处时间戳、`WorkspaceStore` 的 `clockFormatter` 各自判定「展示格式（本地化）」还是「契约格式（保持）」。排除项：`isoDateFormatter`（`en_US_POSIX` + `yyyy-MM-dd`）保持不动并新增用例锁死输出 | M |
| F-0703 | 核心、会话与更新模块错误语义化 | F-0701 | `ViolationEngine` 的 12 条消息模板、`KairoSession` 的 30 行、`KairoUpdater` 的 49 行 errorDescription 全部改为「码 + 参数」；无自然语言拼接；Linux 编译通过 | M |
| F-0704 | 呈现层快照语义化 | F-0703 | 快照类型不含自然语言字段（缩放标签、每天点数、违例原因）；三端渲染一致 | M |
| F-0705 | 视图层接入 String Catalog | F-0700、F-0704 | 英文环境主窗口/检查器/面板/菜单/状态栏/更新面板/两个确认弹窗无中文残留；键无遗漏；英文界面下「载入示例项目」生成的示例任务无中文 | L |
| F-0706 | 语言切换与持久化 | F-0705、F-0709 | 三档可持久化、重启生效；非法值回退跟随系统 | M |
| F-0707 | CLI 语言策略 | F-0703 | `--lang`/`KAIRO_LANG` 生效；`--json` 字节一致；退出码不变 | M |
| F-0708 | MCP 错误补稳定 `code`（阶段一） | F-0703 | 22 处中文错误全部带 `code`；`message` 与原中文逐字一致；协议结构不变；任意宿主语言下输出字节一致 | M |
| F-0714 | MCP 工具描述与错误切英文（阶段二） | F-0708 | 16 条工具描述与 22 处错误 `message` 为英文；`code` 集合与阶段一完全一致（逐条比对）；CHANGELOG 标注破坏点 | M |
| F-0709 | 打包与 Info.plist | F-0700 | 清单含两种本地化；资源进 `Contents/Resources` 且被签名覆盖；OTA 升级后仍命中 | M |
| F-0710 | 测试改造 | F-0705、F-0712、F-0713 | 双 Locale 全绿；新增键完整性测试；白名单外无硬编码文案 | L |
| F-0711 | 文档与 CI 门禁 | F-0710 | 术语表含英文列；CI 拦截白名单外新增中文；两侧零缺键检查在 CI 执行；**CI 断言三层无 `Bundle.module`** | S |
| F-0713 | 断言分类盘点 | F-0700 | 327 条全部归类并附理由；抽样 20 条评审一致 | M |
| F-0715 | D-022：任务晚于项目窗口时违例文案点明用户输入致因 | F-0703 | 违例码统一为 `schedule_start_after_project_window`（原写作 `window.startAfterProjectEnd`，与 §A 的 `<group>_<detail>` 文法不一致，冻结前改名）；参数含「任务开始日 / 项目窗口」；中文文案点明是输入导致；D-022 回归用例通过 | S |
| F-0716 | D-023：时限窗口改用日历日而非 86 400 秒 | — | America/New_York 跨 DST 的时限冲突判定与期望一致；新增两条跨 DST 用例（春进 / 秋退） | M |
| F-0717 | D-024：统一「无下界」哨兵口径 | — | `startDateLowerBound` 与排期内部哨兵使用同一常量；现有排期用例零变化 | S |
## 11. 验收判据（版本级）

| # | 判据 | 检测方式 |
|---|---|---|
| 1 | 英文系统下遍历主窗口、检查器、命令面板、菜单、状态栏、更新面板、退出确认弹窗、保存失败弹窗，无中文残留 | `tools/i18n-lint.sh` 白名单清零（`tools/release.sh` 以 `--fail-if-whitelist-nonempty` 断言，系统提供部分除外，清单见 §8）+ 八个界面各存一张截图归档 |
| 2 | 简体中文下文案语义与 v0.8.5 一致 | 以 F-0701 产出的键-文案对照表为基线逐条 diff，差异逐条记录在变更说明中 |
| 3 | CLI 双语言输出正确、`--json` 字节一致、退出码不变 | 接口测试：同命令以 `--lang en` / `--lang zh-Hans` 各跑一次，比较 stdout 字节与退出码 |
| 4a | 阶段一：MCP 错误含 `code` 且 `message` 仍是原中文 | 起进程、注入不同 `LANG` 发同一 JSON-RPC 请求，断言 `code` 存在且 `message` 与 v0.8.5 逐字一致 |
| 4b | 阶段二：MCP 描述与 `message` 为英文、`code` 不变 | 比较阶段一与阶段二的 `code` 集合完全一致；描述与 `message` 不含中文字符 |
| 5 | 双 Locale 全量测试通过、键完整性通过 | `swift test` 矩阵加 `-AppleLanguages` 参数；键完整性为纯数据比对 |
| 6 | 从零构建的应用在英文系统显示英文，OTA 升级后仍生效 | 构建产物断言（`plutil -p` 查清单、`Contents/Resources` 查 `.lproj` 存在）+ 启动后读 `Bundle.preferredLocalizations` 的半自动断言 |

**F-0705 收口顺序（发布证据链）**：① 清零前先跑一次 `tools/i18n-lint.sh --require-catalog --lproj-dir <编译产物>` 留档（输出里的「白名单有 N 条已清理」）；若已被 `--write-whitelist` 覆盖，轨迹可用 git 无损重建，不依赖终端截图：

```bash
git show <清零前的提交>:tools/i18n-whitelist.txt | grep -v '^#' | grep -c '[^[:space:]]'   # 404
git show <清零后的提交>:tools/i18n-whitelist.txt | grep -v '^#' | grep -c '[^[:space:]]'   # 0
```

② 清零与视图改动必须落在**同一个提交**里，否则「404 → 0」只存在于工作区，换分支即断链；③ 复核 `--fail-if-whitelist-nonempty` exit 0。发布闸门本身只认 `tools/release.sh` 里的 `--fail-if-whitelist-nonempty`，①②③ 是取证，不替代判定。

## 12. 风险与前置验证

| 编号 | 事项 | 处置 |
|---|---|---|
| P1 | SwiftPM 资源在自建 `.app` 内的加载路径 | **已定论**（§7.1）：SwiftPM 侧的「Catalog 进 target」判否，采用主路径 B（`.xcstrings` 只作源、编译进 `.app`）；剩余风险由 §7.3 的构建产物断言与 F-0711 门禁覆盖 |
| P2 | 运行中切换语言的可行性与回归面 | 不影响本期；有结论后再评估 |
| P3 | 327 处断言的分类比例 | F-0713 产出清单，作为 F-0710 估时依据 |
| R1 | 键命名定得太晚导致返工 | F-0701 先于 F-0703 / F-0704 / F-0705 |
| R2 | MCP 文案变更影响既有提示词 | 分两步发布：阶段一先给 `code`，阶段二再切文案；CHANGELOG 显著标注；迁移窗口至少一个版本 |
| R3 | 半本地化中间态被发布 | 发布闸门见 §9 |
| R4 | 资源未进签名覆盖或 OTA 后被丢弃 | F-0709 判据含签名覆盖与升级实测 |
| R5 | 日期格式随语言变化，影响按文本缓存的快照 | F-0702 / F-0712 完成后检查缓存键是否含格式化文本；含则改为语义值 |

## 13. 影响面清单

| 面 | 影响 | 动作 |
|---|---|---|
| README（中英两版） | 说明支持语言与切换方式 | 新增「语言」小节，两版互链 |
| CHANGELOG | 新特性 + 两次 MINOR：v0.9.0 记语言支持与 MCP `code`；v0.10.0 记 MCP 文案变更（显著标注破坏点） | 两条 MINOR 版本条目 |
| 术语表 | 新增「更新面板（UpdateSheet）」等条目与英文列 | `04-glossary.md` 扩列 |
| QUICKSTART | CLI 新增 `--lang` | 补参数说明与示例 |
| `tools/build.sh` + `tools/i18n-compile.sh` | 清单语言键 + 构建期编译 Catalog + 资源拷贝 | 资源缺失时构建失败，不静默回退（§7.2） |
| `tools/release.sh` | 发版前置校验新增多语言闸门：编译 Catalog → 全量 lint → 断言白名单为空 | 白名单非空即发版失败（§11 判据 1）；开发期不受影响 |
| CI | 新增硬编码中文门禁、缺键检查、`Bundle.module` 守卫，落在 `tools/i18n-lint.sh`（含白名单 `tools/i18n-whitelist.txt`），并跑 `tools/i18n-lint-selftest.sh` 自测 | 白名单入库；Linux 任务不变；**没有跳过模式**：CI 用 `--require-catalog`，Catalog 缺失即 `::error` + 失败（F-0705 合入前该步骤保持红色），不以跳过代替 |
| 测试套件 | 327 处含中文断言 | F-0713 分类后由 F-0710 改造 |
| 架构文档 | 分层职责新增「文案归属」 | `ARCHITECTURE.md` 补一条约束并指向本文 |
