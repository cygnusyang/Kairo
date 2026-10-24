import Foundation
import KairoCore
import KairoCommands

/// CLI 选项到核心枚举的解析。值集与 KairoCore 枚举 rawValue 对齐。
///
/// 每个入口都带 `language` 参数（默认跟随环境/系统）：用法错误也是人类输出，
/// 必须按 `--lang` 渲染（F-0707）。
enum CLIEnums {
    static func kind(_ raw: String?, language: CLILanguage = .current) throws -> TaskKind? {
        guard let raw else { return nil }
        guard let v = TaskKind(rawValue: raw) else {
            throw UsageError(message: CLIStrings(language: language).invalidKind(raw))
        }
        return v
    }

    static func priority(_ raw: String?, language: CLILanguage = .current) throws -> TaskPriority? {
        guard let raw else { return nil }
        guard let v = TaskPriority(rawValue: raw) else {
            throw CLIError.invalidPriority(raw)
        }
        return v
    }

    static func status(_ raw: String?, language: CLILanguage = .current) throws -> TaskStatus? {
        guard let raw else { return nil }
        guard let v = TaskStatus(rawValue: raw) else {
            throw CLIError.invalidStatus(raw)
        }
        return v
    }

    /// 调度策略解析（F-22-04：asap/alap）。
    static func schedulingPolicy(_ raw: String?, language: CLILanguage = .current) throws -> SchedulingPolicy? {
        guard let raw else { return nil }
        guard let v = SchedulingPolicy(rawValue: raw) else {
            throw UsageError(message: CLIStrings(language: language).invalidSchedulingPolicy(raw))
        }
        return v
    }

    /// 时限规格：type:ISO8601（如 startNoLaterThan:2026-11-05T00:00:00Z）。
    static func constraint(_ raw: String?, language: CLILanguage = .current) throws -> SchedulingConstraint? {
        guard let raw else { return nil }
        let strings = CLIStrings(language: language)
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let date = CLIEnums.parseDate(String(parts[1])) else {
            throw UsageError(message: strings.invalidConstraintSpec(raw))
        }
        switch String(parts[0]) {
        case "startNoEarlierThan": return .startNoEarlierThan(date)
        case "startNoLaterThan": return .startNoLaterThan(date)
        case "endNoEarlierThan": return .endNoEarlierThan(date)
        case "endNoLaterThan": return .endNoLaterThan(date)
        default:
            throw UsageError(message: strings.invalidConstraintType(String(parts[0])))
        }
    }

    /// 日期解析：ISO8601 完整形式或 YYYY-MM-DD（UTC 零点）。
    static func parseDate(_ raw: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(identifier: "UTC")
        day.locale = Locale(identifier: "en_US_POSIX")
        return day.date(from: raw)
    }

    /// 资源种类解析（F-23-01：person/equipment/material/group）。
    static func resourceKind(_ raw: String?, language: CLILanguage = .current) throws -> ResourceKind? {
        guard let raw else { return nil }
        guard let v = ResourceKind(rawValue: raw) else {
            throw UsageError(message: CLIStrings(language: language).invalidResourceKind(raw))
        }
        return v
    }

    /// 相关性规格：predecessor[:type[:lag]]，predecessor 为完整 UUID 或唯一前缀，
    /// type ∈ fs/ff/ss/sf。前缀在会话打开后经 `resolve(in:)` 解析。
    /// `language` 目前不影响该函数（错误由 `CLIError` 携带原文、出口统一渲染），
    /// 保留参数是为了与其它解析入口的签名一致，避免调用点分叉。
    static func dependency(_ spec: String, language: CLILanguage = .current) throws -> DependencySpec {
        _ = language
        // 保留空段：":fs" 的前驱为空，属用法错误而非前缀 "fs"。
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false)
        guard let raw = parts.first, !raw.isEmpty else {
            throw CLIError.invalidDependency(spec)
        }
        let type = parts.count > 1 ? parts[1].lowercased() : "fs"
        guard let depType = TaskDependency.DependencyType(rawValue: String(type)) else {
            throw CLIError.invalidDependencyType(String(type))
        }
        let lag = parts.count > 2 ? (Double(parts[2]) ?? 0) : 0
        return DependencySpec(predecessor: String(raw), type: depType, lagDays: lag)
    }
}

/// 待解析的相关性规格（前驱可为完整 UUID 或唯一前缀）。
struct DependencySpec {
    let predecessor: String
    let type: TaskDependency.DependencyType
    let lagDays: Double

    /// 用已打开的项目会话解析前驱标识。
    func resolve(in session: KairoSession, strings: CLIStrings) throws -> TaskDependency {
        let id = try CLIRouter.resolveTaskID(predecessor, in: session, strings: strings)
        return TaskDependency(predecessorID: id, type: type, lagDays: lagDays)
    }
}

/// 资源分配规格：resource[:units]，resource 为完整 UUID 或唯一前缀（US-E1-05）。
struct AssignmentSpec {
    let resource: String
    let units: Double

    func resolve(in session: KairoSession, strings: CLIStrings) throws -> TaskAssignment {
        let id = try CLIRouter.resolveResourceID(resource, in: session, strings: strings)
        return TaskAssignment(resourceID: id, units: units)
    }
}

extension CLIEnums {
    /// 解析 `资源[:单位]`；单位必须为正数，默认 1。
    static func assignment(_ spec: String, language: CLILanguage = .current) throws -> AssignmentSpec {
        let strings = CLIStrings(language: language)
        let parts = spec.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let raw = parts.first, !raw.isEmpty else {
            throw UsageError(message: strings.invalidAssignment(spec))
        }
        var units = 1.0
        if parts.count > 1 {
            guard let value = Double(parts[1]), value > 0 else {
                throw UsageError(message: strings.invalidAssignmentUnits(String(parts[1])))
            }
            units = value
        }
        return AssignmentSpec(resource: String(raw), units: units)
    }
}

/// CLI 专属错误：枚举值不合法。
///
/// 文案由 `message(_:)` 按语言渲染；`description` 只为 `CustomStringConvertible`
/// 兜底（`String(describing:)` 路径），正常出口（`CLIRouter.run`）总是显式传语言。
enum CLIError: Error, CustomStringConvertible {
    case invalidPriority(String)
    case invalidStatus(String)
    case invalidDependency(String)
    case invalidDependencyType(String)

    func message(_ language: CLILanguage) -> String {
        let strings = CLIStrings(language: language)
        switch self {
        case .invalidPriority(let raw):
            return strings.invalidPriority(raw)
        case .invalidStatus(let raw):
            return strings.invalidStatus(raw)
        case .invalidDependency(let spec):
            return strings.invalidDependencySpec(spec)
        case .invalidDependencyType(let raw):
            return strings.invalidDependencyType(raw)
        }
    }

    var description: String { message(.current) }
}
