import Foundation
import KairoCore

/// 缩放档位（F-0704）：预设档位名不再以中文出现在快照里，由视图按 `statusbar.zoom.<raw>` 渲染。
public enum ZoomPreset: String, Codable, Hashable, Sendable {
    /// 自定义日宽生效（优先于预设与「适合项目」）。
    case custom
    /// 「缩放以适合项目」。
    case fit
    case day
    case week
    case month
}

/// 缩放指示（F-0704）：档位 + 实际日宽读数。
///
/// 视图渲染：档位查 Catalog，日宽读数按 `statusbar.zoom.pointsPerDay` 格式化；
/// `pointsPerDay == nil` 表示日宽非有限值或超出可渲染范围，视图出占位符。
public struct ZoomIndicator: Hashable, Sendable {
    public var preset: ZoomPreset
    /// 实际日宽（点/天）；nil = 非有限值或超出 Int 可表示范围。
    public var pointsPerDay: Double?

    public init(preset: ZoomPreset, pointsPerDay: Double?) {
        self.preset = preset
        self.pointsPerDay = pointsPerDay
    }
}

/// 状态栏快照（ADR-013 §3.3）：健康点、加权进度、计数、剩余天数与保存状态同源。
public struct StatusBarSnapshot: Hashable, Sendable {
    public var health: ProjectSummary.Health
    public var weightedProgress: Double
    public var overdueCount: Int
    public var violationErrorCount: Int
    public var violationWarningCount: Int
    public var criticalPathCount: Int
    public var remainingDays: Int?
    public var saveState: SaveState
    public var visibleStart: Date?
    public var visibleEnd: Date?
    public var todayVisible: Bool
    public var hiddenTaskCount: Int
    public var selectionSummary: String?
    /// 缩放指示（档位 + 日宽读数），替代 v0.8.5 的 `zoomLabel` / `zoomDetail` 文案。
    public var zoom: ZoomIndicator

    public init(
        health: ProjectSummary.Health,
        weightedProgress: Double,
        overdueCount: Int,
        violationErrorCount: Int,
        violationWarningCount: Int,
        criticalPathCount: Int,
        remainingDays: Int?,
        saveState: SaveState,
        visibleStart: Date? = nil,
        visibleEnd: Date? = nil,
        todayVisible: Bool = false,
        hiddenTaskCount: Int = 0,
        selectionSummary: String? = nil,
        zoom: ZoomIndicator
    ) {
        self.health = health
        self.weightedProgress = weightedProgress
        self.overdueCount = overdueCount
        self.violationErrorCount = violationErrorCount
        self.violationWarningCount = violationWarningCount
        self.criticalPathCount = criticalPathCount
        self.remainingDays = remainingDays
        self.saveState = saveState
        self.visibleStart = visibleStart
        self.visibleEnd = visibleEnd
        self.todayVisible = todayVisible
        self.hiddenTaskCount = hiddenTaskCount
        self.selectionSummary = selectionSummary
        self.zoom = zoom
    }
}

/// 完整工作台快照。
public struct WorkspaceSnapshot: Hashable, Sendable {
    public var outline: OutlineSnapshot
    public var gantt: GanttSnapshot
    public var inspector: InspectorSnapshot
    public var statusBar: StatusBarSnapshot
    public var generatedAt: Date

    public init(
        outline: OutlineSnapshot,
        gantt: GanttSnapshot,
        inspector: InspectorSnapshot,
        statusBar: StatusBarSnapshot,
        generatedAt: Date
    ) {
        self.outline = outline
        self.gantt = gantt
        self.inspector = inspector
        self.statusBar = statusBar
        self.generatedAt = generatedAt
    }
}
