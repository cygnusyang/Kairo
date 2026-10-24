import Foundation
import Testing
@testable import KairoCore
import KairoCommands

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "旧文件"

// 项目方向（ADR-011 / ADR-013）：旧文件缺省 forward，可更新并传入排期。

struct ProjectDirectionTests {
    @Test func legacyMetadataDecodesAsForward() throws {
        let metadata = ProjectMetadata(title: b0Fixture1)
        let encoded = try JSONEncoder().encode(metadata)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "direction")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ProjectMetadata.self, from: legacy)

        #expect(decoded.direction == .forward)
        #expect(decoded.title == b0Fixture1)
    }

    @Test func directionRoundTrips() throws {
        let metadata = ProjectMetadata(title: "方向", direction: .backward)

        let decoded = try JSONDecoder().decode(
            ProjectMetadata.self, from: JSONEncoder().encode(metadata)
        )

        #expect(decoded.direction == .backward)
    }

    @Test func sessionUpdatesDirectionAndPassesItToSchedule() throws {
        let session = KairoSession()
        try session.createProject(title: "方向")
        _ = try session.addTask(title: "任务")

        let metadata = try session.updateProjectMetadata(direction: .backward)
        let result = try session.computeSchedule()

        #expect(metadata.direction == .backward)
        #expect(result.direction == .backward)
    }

    @Test func directionPersistsThroughFileRoundTrip() throws {
        let session = KairoSession()
        try session.createProject(title: "方向持久化")
        _ = try session.addTask(title: "任务")
        try session.updateProjectMetadata(direction: .backward)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kairo")
        defer { try? FileManager.default.removeItem(at: url) }
        try session.saveProject(to: url)

        let reopened = KairoSession()
        let metadata = try reopened.openProject(at: url)

        #expect(metadata.direction == .backward)
    }
}
