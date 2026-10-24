import Foundation
import KairoCore
import KairoPresentation

/// 筛选摘要的视图层渲染（F-0705 / F-0718）。
///
/// 快照只带语义谓词（`FilterExplanation`），自然语言在这里按 Catalog 拼；
/// 核心层不再产出「筛选：逾期 + tag:设计」这类整句。
enum FilterExplanationText {
    /// 摘要整句；无谓词时返回 nil（调用点据此不显示）。
    static func text(_ explanation: FilterExplanation) -> String? {
        guard !explanation.predicates.isEmpty else { return nil }
        let parts = explanation.predicates.map(describe)
        return I18n.t("outline.filter.explanation.prefix", "Filter: %1$@", parts.joined(separator: " + "))
    }

    private static func describe(_ predicate: FilterExplanation.Predicate) -> String {
        switch predicate {
        case .overdue:
            return I18n.t("outline.filter.explanation.overdue", "overdue")
        case .dueToday:
            return I18n.t("outline.filter.explanation.due_today", "due today")
        case .field(let key, let match, let value):
            let field = fieldName(key)
            switch match {
            case .hasTag:
                return I18n.t("outline.filter.explanation.has_tag", "tag:%1$@", value)
            case .contains:
                return I18n.t("outline.filter.explanation.contains", "%1$@ contains %2$@", field, value)
            case .equals, .isValue:
                return I18n.t("outline.filter.explanation.equals", "%1$@: %2$@", field, value)
            }
        }
    }

    /// 筛选字段名（与列名同一套术语）。
    private static func fieldName(_ key: SearchKey) -> String {
        switch key {
        case .title: return I18n.t("outline.filter.field.title", "Title")
        case .notes: return I18n.t("outline.filter.field.notes", "Notes")
        case .tags: return I18n.t("outline.filter.field.tags", "Tags")
        case .assignee: return I18n.t("outline.filter.field.assignee", "Assignee")
        case .priority: return I18n.t("outline.filter.field.priority", "Priority")
        case .status: return I18n.t("outline.filter.field.status", "Status")
        }
    }
}
