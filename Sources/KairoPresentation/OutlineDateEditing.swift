import Foundation
import KairoCore

/// 日期字段不可编辑的语义原因（F-0704）：视图按 Catalog 渲染，核心/呈现层不出文案。
public enum DateFieldDisabledReason: Hashable, Sendable {
    /// 群组（聚合）行：字段由子任务聚合，只读。
    case aggregate
    /// 里程碑无持续时间（结束日与开始日同日）。
    case milestone
    /// 无排期；带具体排期缺失原因（依赖环 / 空群组 / 不可排期），nil = 快照未给出原因。
    case unscheduled(UnscheduledReason?)
}

/// 日期字段的可编辑性（F-0704）：替代原先返回中文整句的 disabledReason(for:)。
public enum DateFieldAvailability: Hashable, Sendable {
    case editable
    case disabled(reason: DateFieldDisabledReason)

    public var isEditable: Bool { self == .editable }

    public var disabledReason: DateFieldDisabledReason? {
        guard case .disabled(let reason) = self else { return nil }
        return reason
    }
}

/// 大纲「开始 / 结束」日期列的可编辑策略（F-14-19）。
///
/// 视图只查这份策略，不判语义：群组 / 里程碑 / 无排期三类禁用与最小可选日
/// 全部落在纯函数里，可脱离 SwiftUI 单测。本策略只服务日期列，
/// 其它列（状态、标题、持续时间……）不参与——它们一律「可编辑、无原因、无下限」，
/// 由各自单元格自己的规则管。
///
/// 禁用原因的措辞不在这里（F-0704）：返回 DateFieldAvailability，文案由视图按
/// date.field.<reason> 查 Catalog；三条禁用原因与检查器「开始 / 结束」行同键，
/// 同一行在大纲与检查器给出的解释必须相同。
public enum OutlineDateEditing {
    /// 该列在该行是否可编辑。
    ///
    /// - .start：仅群组禁用（无排期、里程碑均可编辑——清除排期起点即回落自动排期）。
    /// - .finish：群组 / 里程碑 / 无排期禁用。
    /// - 其它列：恒 true。
    ///
    /// 无排期（scheduledStart == nil，或快照自相矛盾地标记了无排期）**故意保持禁用**：
    /// 结束日只折算持续时间，必须先有一个排期起点才能算天数；WorkspaceStore.setTaskFinish
    /// 还会用 currentScheduleStart 复核起点，放开只会让用户选完日期再吃一条
    /// 「排期已变化，请重新选择结束日期」。后续若要统一检查器口径，先改 Store 的折算入口，
    /// 再放开这里的判定。
    public static func isEnabled(column: OutlineColumn, row: PlanRow) -> Bool {
        availability(column: column, row: row).isEditable
    }

    /// 该列的「清除」是否可用；不可用时视图不显示清除按钮。
    ///
    /// 只对开始列成立，且只认**意图起点**（row.startDate）：开始列显示的是排期结果
    /// （scheduledStart，可能因依赖被后移），若按显示值给清除按钮，用户会看到
    /// 一个「清掉不存在的意图值」的入口——点了没有可见变化。
    public static func canClear(column: OutlineColumn, row: PlanRow) -> Bool {
        guard column == .start, !row.isAggregate else { return false }
        return row.startDate != nil
    }

    /// 该列在该行的可编辑性；不可编辑时携带语义原因（视图按原因出解释文案）。
    public static func availability(column: OutlineColumn, row: PlanRow) -> DateFieldAvailability {
        switch column {
        case .start:
            return row.isAggregate ? .disabled(reason: .aggregate) : .editable
        case .finish:
            if row.isAggregate { return .disabled(reason: .aggregate) }
            if row.kind == .milestone { return .disabled(reason: .milestone) }
            // 结束日折算持续时间必须站在排期起点上；无排期的行没有可折算的起点。
            if row.scheduledStart == nil || !row.hasSchedule {
                return .disabled(reason: .unscheduled(row.unscheduledReason))
            }
            return .editable
        default:
            return .editable
        }
    }

    /// 结束列的提交参数：(用户选的结束日, 同一快照的排期起点)。
    ///
    /// 返回 nil 表示「不该提交」：该列在该行禁用，或快照没有排期起点。
    /// 起点缺失时绝不拿结束日兜底当起点——那会折算成 0 天，把「没有排期起点」
    /// 这条真实原因掩盖成一次静默无效的写入。
    public static func finishCommit(
        row: PlanRow,
        finish: Date
    ) -> (finish: Date, start: Date)? {
        guard isEnabled(column: .finish, row: row), let start = row.scheduledStart else {
            return nil
        }
        return (finish: finish, start: start)
    }

    /// 最小可选日（含）；nil 表示不限。
    ///
    /// 只有结束列有下限：排他端点，普通任务为起点次日，里程碑为起点当日
    /// （里程碑行本身已禁用，此处仅为口径完整）。开始列与其它列恒 nil。
    public static func minimumDate(
        column: OutlineColumn,
        row: PlanRow,
        calendar: Calendar = .current
    ) -> Date? {
        switch column {
        case .finish:
            guard let start = row.scheduledStart else { return nil }
            return ScheduleDateMath.minimumFinish(start: start, kind: row.kind, calendar: calendar)
        default:
            return nil
        }
    }
}
