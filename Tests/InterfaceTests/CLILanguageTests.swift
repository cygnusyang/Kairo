import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Testing
import KairoCore
@testable import KairoCLI
@testable import KairoMCP

// F-0707 CLI 语言策略的验收用例。
// 用例编号对应 docs/features/06-localization-cases.md 的 D 组与 G-01/G-02。

// MARK: - 判据工具

/// 是否含汉字：「英文输出无中文残留」的判据。
private func containsHan(_ text: String) -> Bool {
    text.range(of: "\\p{Han}", options: .regularExpression) != nil
}

/// 建临时工作目录，返回目录与 .kairo 路径；调用方 defer 清理。
private func makeScratch() throws -> (dir: URL, kairo: URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("kairo-i18n-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (dir: dir, kairo: dir.appendingPathComponent("demo.kairo"))
}

/// stderr 捕获（与 InterfaceTests.swift 的 captureStdout 同法：dup2 重定向 + 独立锁）。
/// fd 2 同样是进程级资源，捕获窗口不得重叠，故单独一把锁。
private let stderrCaptureLock = NSLock()

private func captureStderr(_ body: () throws -> Void) throws -> String {
    stderrCaptureLock.lock()
    defer { stderrCaptureLock.unlock() }

    let pipe = Pipe()
    let savedFD = dup(FileHandle.standardError.fileDescriptor)
    dup2(pipe.fileHandleForWriting.fileDescriptor, FileHandle.standardError.fileDescriptor)

    var thrown: Error?
    do {
        try body()
    } catch {
        thrown = error
    }
    fflush(stderr)
    dup2(savedFD, FileHandle.standardError.fileDescriptor)
    close(savedFD)
    pipe.fileHandleForWriting.closeFile()

    if let thrown { throw thrown }
    return String(decoding: try pipe.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self)
}

// MARK: - CLI 语言（F-0707）

struct CLILanguageOptionTests {
    /// 建一个含单个 ASCII 标题任务的项目（标题是用户数据，不能用中文干扰「无中文」判据）。
    private func makeProject() throws -> (dir: URL, kairo: URL) {
        let scratch = try makeScratch()
        try CLIRouter.execute(arguments: ["project", "create", "Lang Demo", "--file", scratch.kairo.path])
        try CLIRouter.execute(arguments: ["task", "add", "Alpha", "--file", scratch.kairo.path])
        return scratch
    }

    /// D-01：\`--lang en\` 出英文、\`--lang zh-Hans\` 出中文（阶段一中文与 v0.8.5 一致）。
    @Test func langFlagSwitchesHumanOutput() throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo.path
        try CLIRouter.execute(arguments: ["project", "create", "Lang Demo", "--file", file])

        let en = try captureStdout {
            try CLIRouter.execute(arguments: ["task", "add", "Alpha", "--lang", "en", "--file", file])
        }
        #expect(!containsHan(en))
        #expect(en.hasPrefix("task created: "))

        let zh = try captureStdout {
            try CLIRouter.execute(arguments: ["task", "add", "Beta", "--lang", "zh-Hans", "--file", file])
        }
        #expect(zh.hasPrefix("已创建任务："))
    }

    /// D-06：\`--lang\` 位置无关，且 \`--lang en\` / \`--lang=en\` 等价。
    @Test func langOptionIsPositionIndependent() throws {
        let scratch = try makeProject()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo.path

        let after = try captureStdout {
            try CLIRouter.execute(arguments: ["task", "list", "--lang", "en", "--file", file])
        }
        let before = try captureStdout {
            try CLIRouter.execute(arguments: ["--lang", "en", "task", "list", "--file", file])
        }
        let equalsForm = try captureStdout {
            try CLIRouter.execute(arguments: ["task", "list", "--lang=en", "--file", file])
        }

        #expect(after == before)
        #expect(after == equalsForm)
        #expect(!containsHan(after))
        #expect(after.contains("Alpha"))
    }

    /// D-02 / G-02：\`KAIRO_LANG\` 生效；非法值静默回退系统语言；系统不可判定回退 zh-Hans。
    @Test func environmentLanguageAndSilentFallback() throws {
        let scratch = try makeProject()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo.path
        let args = ["task", "list", "--file", file]

        let explicitEN = try captureStdout {
            try CLIRouter.execute(arguments: ["task", "list", "--lang", "en", "--file", file])
        }
        let envEN = try captureStdout {
            try CLIRouter.execute(
                arguments: args,
                environment: ["KAIRO_LANG": "en"],
                preferredLanguages: ["zh-Hans-CN"]
            )
        }
        #expect(envEN == explicitEN)

        let systemZH = try captureStdout {
            try CLIRouter.execute(arguments: args, environment: [:], preferredLanguages: ["zh-Hans-CN"])
        }
        #expect(containsHan(systemZH))

        // G-02：非法环境变量不得让命令失败，输出与不设逐字节一致。
        let badEnv = try captureStdout {
            try CLIRouter.execute(
                arguments: args,
                environment: ["KAIRO_LANG": "xx"],
                preferredLanguages: ["zh-Hans-CN"]
            )
        }
        #expect(badEnv == systemZH)

        // 系统语言不可判定（如法语）→ zh-Hans 兜底，不破坏既有中文脚本。
        let unknownSystem = try captureStdout {
            try CLIRouter.execute(arguments: args, environment: [:], preferredLanguages: ["fr-FR"])
        }
        #expect(unknownSystem == systemZH)
    }

    /// D-03：优先级 命令行 > 环境变量。
    @Test func commandLineBeatsEnvironment() throws {
        let scratch = try makeProject()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo.path

        let flagEN = try captureStdout {
            try CLIRouter.execute(arguments: ["task", "list", "--lang", "en", "--file", file])
        }
        let flagOverEnvironment = try captureStdout {
            try CLIRouter.execute(
                arguments: ["task", "list", "--lang", "en", "--file", file],
                environment: ["KAIRO_LANG": "zh-Hans"],
                preferredLanguages: ["zh-Hans-CN"]
            )
        }
        #expect(flagOverEnvironment == flagEN)

        let zh = try captureStdout {
            try CLIRouter.execute(arguments: ["task", "list", "--lang", "zh-Hans", "--file", file])
        }
        let flagOverEnglishEnvironment = try captureStdout {
            try CLIRouter.execute(
                arguments: ["task", "list", "--lang", "zh-Hans", "--file", file],
                environment: ["KAIRO_LANG": "en"],
                preferredLanguages: ["en-US"]
            )
        }
        #expect(flagOverEnglishEnvironment == zh)
    }

    /// D-04：\`--json\` 与语言无关——四种语言设置下 stdout 字节完全一致。
    @Test func jsonOutputIsLanguageIndependent() throws {
        let scratch = try makeProject()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo.path

        var outputs: [String] = []
        let settings: [(arguments: [String], environment: [String: String], preferred: [String])] = [
            (["task", "list", "--json", "--lang", "en", "--file", file], [:], ["zh-Hans-CN"]),
            (["task", "list", "--json", "--lang", "zh-Hans", "--file", file], [:], ["en-US"]),
            (["task", "list", "--json", "--file", file], ["KAIRO_LANG": "en"], ["zh-Hans-CN"]),
            (["task", "list", "--json", "--file", file], [:], ["zh-Hans-CN"]),
        ]
        for setting in settings {
            outputs.append(try captureStdout {
                try CLIRouter.execute(
                    arguments: setting.arguments,
                    environment: setting.environment,
                    preferredLanguages: setting.preferred
                )
            })
        }
        #expect(Set(outputs).count == 1)
        #expect(outputs[0].contains("\"title\":\"Alpha\""))
    }

    /// D-05：退出码 0/1/2 的语义不随语言变化。
    @Test(arguments: ["en", "zh-Hans"])
    func exitCodesAreLanguageInvariant(_ language: String) throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo.path
        try CLIRouter.execute(arguments: ["project", "create", "Codes", "--file", file])

        let success = CLIRouter.run(
            arguments: ["violations", "--lang", language, "--file", file],
            environment: [:],
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(success == 0)

        let runtimeError = CLIRouter.run(
            arguments: ["task", "list", "--lang", language, "--file", "/nonexistent/kairo/demo.kairo"],
            environment: [:],
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(runtimeError == 1)

        let usageError = CLIRouter.run(
            arguments: ["task", "list", "--jsn", "--lang", language, "--file", file],
            environment: [:],
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(usageError == 2)
    }

    /// G-01：非法 \`--lang\` → 用法错误、退出码 2、提示列出允许值、不落任何文件。
    @Test(arguments: ["fr", "zh_CN", "zh-Hant", ""])
    func invalidLanguageIsUsageError(_ raw: String) throws {
        let scratch = try makeScratch()
        defer { try? FileManager.default.removeItem(at: scratch.dir) }
        let file = scratch.kairo.path

        let code = CLIRouter.run(
            arguments: ["task", "list", "--lang", raw, "--file", file],
            environment: [:],
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(code == 2)

        do {
            try CLIRouter.execute(
                arguments: ["project", "create", "Nope", "--lang", raw, "--file", file],
                environment: [:],
                preferredLanguages: ["zh-Hans-CN"]
            )
            Issue.record("非法 --lang 应抛用法错误：\(raw)")
        } catch let error as UsageError {
            #expect(error.message.contains("en"))
            #expect(error.message.contains("zh-Hans"))
        }
        // 非法语言在打开/写入之前就被拒，不创建文件。
        #expect(!FileManager.default.fileExists(atPath: file))
    }

    /// G-01：\`--lang\` 缺值同属用法错误。
    @Test func missingLanguageValueIsUsageError() throws {
        let code = CLIRouter.run(
            arguments: ["task", "list", "--lang"],
            environment: [:],
            preferredLanguages: ["zh-Hans-CN"]
        )
        #expect(code == 2)
    }

    /// G-01：用法错误的提示确实落在 stderr，且列出允许值。
    @Test func invalidLanguageWritesStderrWithAllowedValues() throws {
        let text = try captureStderr {
            let code = CLIRouter.run(
                arguments: ["task", "list", "--lang", "fr"],
                environment: [:],
                preferredLanguages: ["zh-Hans-CN"]
            )
            #expect(code == 2)
        }
        #expect(!text.isEmpty)
        #expect(text.contains("en"))
        #expect(text.contains("zh-Hans"))
    }

    /// 阶段一中文列逐字等于 v0.8.5（回归闸门：改字即红）。
    @Test func chineseColumnMatchesV085Wording() {
        let s = CLIStrings(language: .zhHans)
        #expect(s.formatVersionLine(written: 1, upgradedFrom: nil) == "格式版本：v1")
        #expect(
            s.sourceVersionLine(source: 1, current: 2) == "源格式版本：v1（当前 v2），保存后升级"
        )
        #expect(s.unknownTask == "未知任务")
        #expect(s.noViolations == "无违例")
        #expect(s.usagePrefix("x") == "用法错误：x")
        #expect(s.errorPrefix("x") == "错误：x")
    }

    /// 违例文案：中文列逐字等于 v0.8.5 的 ViolationEngine 模板。
    @Test func chineseViolationTextMatchesV085() {
        let s = CLIStrings(language: .zhHans)
        #expect(
            s.violationText(Violation(reason: .cycle(taskTitle: "T")))
                == "任务「T」处于相关性环中，无法确定先后顺序"
        )
        #expect(
            s.violationText(Violation(reason: .taskAfterProjectEnd(taskTitle: "T")))
                == "任务「T」的结束日期晚于项目结束日期"
        )
        #expect(
            s.violationText(Violation(reason: .taskBeforeProjectStart(taskTitle: "T")))
                == "任务「T」的开始日期早于项目开始日期"
        )
        #expect(
            s.violationText(Violation(reason: .constraintWindowTooNarrow(
                taskTitle: "T", windowDays: 1, requiredDays: 3
            )))
                == "任务「T」的开始时限与结束时限相距过近（1 天），无法容纳持续时间（3 天）"
        )
        #expect(
            s.violationText(Violation(reason: .negativeSlack(taskTitle: "T")))
                == "任务「T」无法安排：最晚开始早于最早开始（负宽延）"
        )
        #expect(
            s.violationText(Violation(reason: .constraintConflict(
                taskTitle: "T", kind: .startNoEarlierThan, conflict: .latestBeforeConstraint
            )))
                == "任务「T」的「开始不早于」时限与相关性链冲突：最晚开始早于时限"
        )
        #expect(
            s.violationText(Violation(reason: .constraintConflict(
                taskTitle: "T", kind: .endNoEarlierThan, conflict: .windowDoesNotFit
            )))
                == "任务「T」的「结束不早于」时限与相关性链冲突：窗口无法容纳任务持续时间"
        )
        #expect(
            s.violationText(Violation(reason: .constraintUnmetByPrerequisite(
                taskTitle: "T", kind: .endNoLaterThan
            )))
                == "任务「T」因先决条件无法满足「结束不晚于」时限"
        )
        // v0.8.5 的 title(_:) 在任务缺失时回退「未知任务」，文案层面必须保持一致。
        #expect(
            s.violationText(Violation(reason: .cycle(taskTitle: nil)))
                == "任务「未知任务」处于相关性环中，无法确定先后顺序"
        )
    }
}
