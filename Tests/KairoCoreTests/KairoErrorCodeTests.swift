import Foundation
import Testing
@testable import KairoCore

// 错误码契约测试（F-0703 / 设计 §A）：文法冻结、全局唯一、Codable 稳定。
// 码表一旦发布即公共契约，只增不改；本套用例守住「同一 rawValue 不得出现两次」，
// 因为跨模块（KairoCore / KairoUpdater）各持一份码表时，唯一性只能靠断言兜底。

struct KairoErrorCodeTests {
    /// 文法：`<group>_<detail>`，全小写、无空格、至少两段。
    @Test func rawValuesFollowGroupDetailGrammar() {
        for code in KairoErrorCode.allCases {
            let raw = code.rawValue
            #expect(raw == raw.lowercased(), "码值必须全小写：\(raw)")
            #expect(!raw.contains(" "), "码值不得含空格：\(raw)")
            #expect(!raw.hasPrefix("_") && !raw.hasSuffix("_"), "码值不得以分隔符起止：\(raw)")
            #expect(raw.contains("_"), "码值必须为 <group>_<detail> 两段以上：\(raw)")
        }
    }

    /// 全局唯一：rawValue 去重后数量不变（防止复制粘贴出重码）。
    @Test func rawValuesAreGloballyUnique() {
        let values = KairoErrorCode.allCases.map(\.rawValue)
        #expect(Set(values).count == values.count, "存在重复错误码：\(values)")
    }

    /// 分组前缀必须落在约定的域内，便于按域过滤与文档归档。
    @Test func groupPrefixesAreFromFrozenVocabulary() {
        let allowed: Set<String> = [
            "model", "schedule", "storage", "session", "cli", "mcp", "internal",
        ]
        for code in KairoErrorCode.allCases {
            let group = code.rawValue.split(separator: "_").first.map(String.init) ?? ""
            #expect(allowed.contains(group), "未登记的错误码分组：\(group)（\(code.rawValue)）")
        }
    }

    /// Codable 以 rawValue 编码，接口层（MCP/JSON）序列化后仍是稳定字符串。
    @Test func codableRoundTripsThroughRawValue() throws {
        for code in KairoErrorCode.allCases {
            let data = try JSONEncoder().encode(code)
            #expect(String(data: data, encoding: .utf8) == "\"\(code.rawValue)\"")
            let decoded = try JSONDecoder().decode(KairoErrorCode.self, from: data)
            #expect(decoded == code)
        }
    }

    /// 领域模型码 11 个（含 F-0703 新增的 model_resource_not_found：
    /// 「资源不存在」原先无码可落，硬塞单位/效率码会错误归因）。
    @Test func modelCodesCoverSessionValidationSites() {
        let modelCodes = KairoErrorCode.allCases.filter { $0.rawValue.hasPrefix("model_") }
        #expect(modelCodes.count == 11, "model 码应为 11 个，实际 \(modelCodes.count)")
        #expect(KairoErrorCode.resourceNotFound.rawValue == "model_resource_not_found")
    }

    /// 违例相关 8 个码齐全（F-0704 / F-0715 的判据前置）。
    @Test func scheduleCodesCoverEveryViolationReason() {
        let scheduleCodes = KairoErrorCode.allCases.filter { $0.rawValue.hasPrefix("schedule_") }
        #expect(scheduleCodes.count == 8, "排期码应为 8 个，实际 \(scheduleCodes.count)")
        #expect(KairoErrorCode.startAfterProjectWindow.rawValue == "schedule_start_after_project_window")
    }
}
