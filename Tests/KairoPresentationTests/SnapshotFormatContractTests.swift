import Foundation
import Testing
import KairoCore
@testable import KairoPresentation

// F-0704 附带契约：快照里不得出现随 Locale 变的数字/文案。
//
// 旧实现用 Double.formatted() 拼前置延隔（1.5 / 1,5 随系统 Locale 变），该字符串进快照
// 并被 AppTests 逐字断言——属契约格式，必须钉死；缩放读数同理只在快照里放数值。

struct SnapshotFormatContractTests {
    @Test func contractDecimalUsesFixedPointRegardlessOfLocale() {
        // 定点输出：整数值不带小数位，非整数保留 1 位，小数点恒为 "."（非 Locale 相关）。
        #expect(WorkspacePresenter.contractDecimal(1.5) == "1.5")
        #expect(WorkspacePresenter.contractDecimal(2) == "2")
        #expect(WorkspacePresenter.contractDecimal(12.25) == "12.3")
        #expect(WorkspacePresenter.contractDecimal(-1.5) == "-1.5")
        #expect(!WorkspacePresenter.contractDecimal(1.5).contains(","))
    }

    @Test func predecessorsTextRendersLagWithoutLocaleSeparator() {
        let predecessorID = UUID()
        let dependencies = [
            TaskDependency(predecessorID: predecessorID, type: .fs, lagDays: 1.5),
            TaskDependency(predecessorID: UUID(), type: .ss, lagDays: 2)
        ]
        let text = WorkspacePresenter.predecessorsText(
            dependencies,
            outlineNumberByID: [predecessorID: "1"]
        )

        #expect(text.hasPrefix("1:fs+1.5"))
        #expect(text.contains("ss+2"))
        #expect(!text.contains(",5"), "延隔小数位不得随 Locale 变成逗号：\(text)")
    }

    @Test func renderableDayWidthRejectsValuesThatCannotBeRendered() {
        #expect(WorkspacePresenter.renderableDayWidth(12.5) == 12.5)
        #expect(WorkspacePresenter.renderableDayWidth(20) == 20)
        #expect(WorkspacePresenter.renderableDayWidth(.nan) == nil)
        #expect(WorkspacePresenter.renderableDayWidth(.infinity) == nil)
        #expect(WorkspacePresenter.renderableDayWidth(-.infinity) == nil)
        #expect(WorkspacePresenter.renderableDayWidth(1e16) == nil)
    }
}
