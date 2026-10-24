import Foundation

/// 从参数数组中抽取操作数与选项值。
struct Options {
    var items: [String]
    /// 人类输出的语言（`--lang` > `KAIRO_LANG` > 系统 > zh-Hans）；由路由在分发前注入。
    var language: CLILanguage
    /// 人类输出出口（默认写 stdout）。接口测试注入收集器，避免抓 fd 与并行用例互相污染。
    var emit: (String) -> Void

    init(
        _ args: [String],
        language: CLILanguage = .current,
        emit: @escaping (String) -> Void = { print($0) }
    ) {
        items = args
        self.language = language
        self.emit = emit
    }

    /// 本命令的文案表。
    var strings: CLIStrings { CLIStrings(language: language) }

    /// 第 n 个非选项操作数。
    func operand(_ index: Int, name: String) throws -> String {
        let operands = items.filter { !$0.hasPrefix("--") }
        guard index < operands.count else {
            throw UsageError(message: strings.missingOperand(name))
        }
        return operands[index]
    }

    /// 选项的值（--key value）。
    func value(for key: String) -> String? {
        guard let i = items.firstIndex(of: key), i + 1 < items.count else { return nil }
        return items[i + 1]
    }

    /// 选项的多个值（可重复出现）。
    func values(for key: String) -> [String] {
        var result: [String] = []
        for (i, item) in items.enumerated() where item == key {
            if i + 1 < items.count { result.append(items[i + 1]) }
        }
        return result
    }

    func double(for key: String) -> Double? {
        value(for: key).flatMap(Double.init)
    }

    /// 布尔开关（无值选项，如 `--json`）。
    func flag(_ key: String) -> Bool {
        items.contains(key)
    }

    /// 校验所有 --选项 都在允许集合内；发现未知选项即用法错误（避免静默忽略）。
    func rejectUnknown(_ allowed: [String]) throws {
        for item in items where item.hasPrefix("--") && !allowed.contains(item) {
            throw UsageError(message: strings.unknownOption(item, allowed: allowed))
        }
    }

    /// --file 选项或默认文件名。
    func fileURL(defaultName: String) -> URL {
        URL(fileURLWithPath: value(for: "--file") ?? defaultName)
    }
}

/// 全局选项（F-0707）：与具体子命令无关，必须在分发前统一处理。
enum GlobalOptions {
    /// 语言选项名。
    static let languageOption = "--lang"

    /// 从 argv 摘除 `--lang <bcp47>` / `--lang=<bcp47>`，返回剩余参数与显式语言。
    ///
    /// 为什么在分发前摘：各命令各自维护 `rejectUnknown` 白名单，只在白名单里加
    /// `--lang` 的话，「`kairo --lang en task list`」这种前置写法仍会被当成子命令；
    /// 统一摘除后白名单零改动，位置天然无关（D-06）。
    ///
    /// 重复给出时以最后一次为准；缺值或取值非法 → 用法错误（退出码 2）。
    static func extract(_ arguments: [String]) throws -> (arguments: [String], language: CLILanguage?) {
        var rest: [String] = []
        var language: CLILanguage?
        // 报错文案跟随「已解析出的语言」，让 `--lang en --lang fr` 也出英文提示。
        var messageLanguage = CLILanguage.current
        var index = 0
        while index < arguments.count {
            let item = arguments[index]
            let raw: String
            if item == languageOption {
                guard index + 1 < arguments.count else {
                    throw UsageError(message: messageLanguage.strings.missingLanguageValue())
                }
                raw = arguments[index + 1]
                index += 2
            } else if item.hasPrefix(languageOption + "=") {
                raw = String(item.dropFirst(languageOption.count + 1))
                index += 1
            } else {
                rest.append(item)
                index += 1
                continue
            }
            guard let parsed = CLILanguage.parse(raw) else {
                throw UsageError(message: messageLanguage.strings.invalidLanguage(raw))
            }
            language = parsed
            messageLanguage = parsed
        }
        return (rest, language)
    }
}

/// 把「子命令 + 余下参数」从命令数组中拆出来。
func subcommand(_ args: [String], from command: String) -> (String, [String]) {
    guard let first = args.first else {
        return ("", [])
    }
    return (first, Array(args.dropFirst()))
}
