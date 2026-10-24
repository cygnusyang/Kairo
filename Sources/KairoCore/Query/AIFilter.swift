import Foundation

/// A single clause produced by `AIFilterTranslator`.
/// Term clauses delegate to `SearchTerm`; date clauses derive from the task's
/// calendar state. Clauses AND-combine.
public enum FilterClause: Sendable {
    case term(SearchTerm)
    case overdue
    case dueToday
}

/// Deterministic, rule-based translator that turns a natural-language phrase
/// into AND-combined filter clauses. This is the "AI-era" search entry point:
/// no model, just a compact token table.
public struct AIFilterTranslator {
    /// Split a phrase into meaningful tokens: lowercased, whitespace-split,
    /// with punctuation-only tokens dropped.
    public static func tokenize(_ phrase: String) -> [String] {
        phrase
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { token in
                !token.isEmpty && token.contains { $0.isLetter || $0.isNumber }
            }
    }

    /// Map a phrase to filter clauses. Unknown tokens fall back to a
    /// case-insensitive title match; `tag:` prefixes become tag matches.
    public static func translate(_ phrase: String) -> [FilterClause] {
        var clauses: [FilterClause] = []
        for token in tokenize(phrase) {
            switch token {
            case "overdue", "逾期":
                clauses.append(.overdue)
            case "done", "完成":
                clauses.append(statusTerm("done"))
            case "todo", "pending", "待办":
                clauses.append(statusTerm("pending"))
            case "doing", "in_progress", "进行中":
                clauses.append(statusTerm("in_progress"))
            case "high", "urgent", "紧急":
                clauses.append(priorityTerm("high"))
            case "critical", "p0":
                clauses.append(priorityTerm("critical"))
            case "today", "今天":
                clauses.append(.dueToday)
            default:
                if token.hasPrefix("tag:") {
                    let tag = String(token.dropFirst(4))
                    guard !tag.isEmpty else { continue }
                    clauses.append(.term(SearchTerm(key: .tags, matcher: .hasTag(tag))))
                } else {
                    clauses.append(.term(SearchTerm(key: .title, matcher: .contains(token))))
                }
            }
        }
        return clauses
    }

    /// 生效子句的语义摘要（F-0718）：码 + 参数，不含自然语言。
    ///
    /// 旧实现返回「筛选：逾期 + status=done」这类中文整句，经 Presenter 进入快照，
    /// 导致同一项目在 en / zh 下快照不相等（C-01 红）。文案由视图 / CLI / MCP 各自渲染。
    public static func summary(for clauses: [FilterClause]) -> FilterExplanation {
        FilterExplanation(clauses: clauses)
    }

    /// Keep tasks satisfying every clause; an empty clause list returns all tasks.
    public static func apply(clauses: [FilterClause], to tasks: [TaskItem]) -> [TaskItem] {
        tasks.filter { task in
            clauses.allSatisfy { clause in
                switch clause {
                case .term(let term):
                    return term.matches(task)
                case .overdue:
                    return task.isOverdue
                case .dueToday:
                    guard let due = task.dueDate else { return false }
                    return Calendar.current.isDateInToday(due)
                }
            }
        }
    }

    private static func statusTerm(_ rawValue: String) -> FilterClause {
        .term(SearchTerm(key: .status, matcher: .isValue(rawValue)))
    }

    private static func priorityTerm(_ rawValue: String) -> FilterClause {
        .term(SearchTerm(key: .priority, matcher: .isValue(rawValue)))
    }

}

/// 筛选摘要的语义值（F-0718）：谓词列表，AND 组合；空数组表示「全部任务」。
///
/// 进快照的是它，不是字符串——视图按 Catalog 渲染（如 `filter.predicate.overdue`），
/// CLI / MCP 各持渲染器。这样同一项目在任意语言下快照逐位相等（C-01）。
public struct FilterExplanation: Codable, Hashable, Sendable {
    /// 匹配方式（与 SearchTerm.Matcher 一一对应）。
    public enum Match: String, Codable, Hashable, Sendable {
        case contains
        case equals
        case isValue
        case hasTag
    }

    public enum Predicate: Codable, Hashable, Sendable {
        case overdue
        case dueToday
        /// 字段匹配：`key` 是字段，`match` 是方式，`value` 是用户输入或枚举原始值。
        case field(key: SearchKey, match: Match, value: String)
    }

    public var predicates: [Predicate]

    public init(predicates: [Predicate]) {
        self.predicates = predicates
    }

    public init(clauses: [FilterClause]) {
        self.predicates = clauses.map { clause in
            switch clause {
            case .overdue:
                return .overdue
            case .dueToday:
                return .dueToday
            case .term(let term):
                switch term.matcher {
                case .contains(let value):
                    return .field(key: term.key, match: .contains, value: value)
                case .equals(let value):
                    return .field(key: term.key, match: .equals, value: value)
                case .isValue(let value):
                    return .field(key: term.key, match: .isValue, value: value)
                case .hasTag(let value):
                    return .field(key: term.key, match: .hasTag, value: value)
                }
            }
        }
    }
}
