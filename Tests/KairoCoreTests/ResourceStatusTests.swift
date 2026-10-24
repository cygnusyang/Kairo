import Foundation
import Testing

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "测试机"
@testable import KairoCore
@testable import KairoCommands

// 资源模型与投入↔持续时间换算（US-E1-05 / F-22-03 / F-23-01）
// 与状态回写（US-E3-01 / US-E3-02）。

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

// MARK: - 投入 ↔ 持续时间换算

struct EffortDurationConversionTests {
    @Test func effortSplitAcrossTwoUnits() throws {
        let r = Resource(name: "工程师", kind: .person, units: 2, efficiency: 1)
        let t = TaskItem(title: "任务", effortHours: 8, assignments: [TaskAssignment(resourceID: r.id, units: 2)])
        let result = ScheduleEngine.compute(tasks: [t], resources: [r], calendar: utc)
        let s = try #require(result.scheduled(t.id))
        // duration = 8h / 8(h/日) / (2×1) = 0.5 天。
        #expect(s.durationDays == 0.5)
    }

    @Test func effortAdjustedByEfficiency() throws {
        let r = Resource(name: "半效员工", kind: .person, units: 1, efficiency: 0.5)
        let t = TaskItem(title: "任务", effortHours: 16, assignments: [TaskAssignment(resourceID: r.id, units: 1)])
        let result = ScheduleEngine.compute(tasks: [t], resources: [r], calendar: utc)
        let s = try #require(result.scheduled(t.id))
        // duration = 16 / 8 / 0.5 = 4 天。
        #expect(s.durationDays == 4)
    }

    @Test func effortWithoutAssignmentConvertsAtOneUnit() throws {
        // 无分配时按 1 个 100% 单位换算：8h → 1 天，16h → 2 天（US-E1-05 验收 1）。
        let eight = TaskItem(title: "八小时", effortHours: 8)
        let sixteen = TaskItem(title: "十六小时", effortHours: 16)
        let result = ScheduleEngine.compute(tasks: [eight, sixteen], calendar: utc)
        #expect(try #require(result.scheduled(eight.id)).durationDays == 1)
        #expect(try #require(result.scheduled(sixteen.id)).durationDays == 2)
    }

    @Test func durationDaysTakesPrecedenceOverEffort() throws {
        let r = Resource(name: "工程师", kind: .person, units: 1, efficiency: 1)
        let t = TaskItem(
            title: "任务", effortHours: 32, durationDays: 2,
            assignments: [TaskAssignment(resourceID: r.id, units: 1)]
        )
        let result = ScheduleEngine.compute(tasks: [t], resources: [r], calendar: utc)
        let s = try #require(result.scheduled(t.id))
        #expect(s.durationDays == 2)
    }

    @Test func milestoneStaysZeroDurationWithEffort() throws {
        let t = TaskItem(title: "里程碑", kind: .milestone, effortHours: 8)
        let result = ScheduleEngine.compute(tasks: [t], calendar: utc)
        let s = try #require(result.scheduled(t.id))
        #expect(s.durationDays == 0)
    }
}

// MARK: - 资源模型编码与持久化

struct ResourceModelTests {
    @Test func resourceCodableRoundTrip() throws {
        let resource = Resource(name: "李工", kind: .person, units: 0.5, efficiency: 0.8)
        let data = try JSONEncoder().encode(resource)
        let decoded = try JSONDecoder().decode(Resource.self, from: data)
        #expect(decoded == resource)
        #expect(decoded.kind == .person)
    }

    @Test func taskAssignmentCodableRoundTrip() throws {
        let assignment = TaskAssignment(resourceID: UUID(), units: 2)
        let data = try JSONEncoder().encode(assignment)
        let decoded = try JSONDecoder().decode(TaskAssignment.self, from: data)
        #expect(decoded == assignment)
    }

    @Test func resourcesPersistThroughKairoFileRoundTrip() throws {
        let project = Project()
        project.resources.append(Resource(name: b0Fixture1, kind: .equipment, units: 1, efficiency: 1))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kairo-res-\(UUID().uuidString).kairo")
        defer { try? FileManager.default.removeItem(at: url) }
        try KairoFile.save(project, to: url)
        let loaded = try KairoFile.load(from: url)
        #expect(loaded.resources.count == 1)
        #expect(loaded.resources.first?.name == b0Fixture1)
    }

    @Test func legacyEnvelopeWithoutResourcesDefaultsEmpty() throws {
        let legacy = #"{"formatVersion":1,"project":{"id":"\#(UUID().uuidString)","title":"旧项目","createdAt":"2026-10-17T00:00:00Z","updatedAt":"2026-10-17T00:00:00Z"},"tasks":[]}"#
        let project = try KairoFile.decode(from: Data(legacy.utf8))
        #expect(project.resources.isEmpty)
    }

    @Test func sessionResourceAddAndList() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "资源项目")
        let id = try session.resourceAdd(name: "张工", kind: .person, units: 1, efficiency: 0.9)
        let resources = try session.resourceList()
        #expect(resources.count == 1)
        #expect(resources.first?.id == id)
        #expect(resources.first?.efficiency == 0.9)
    }
}

// MARK: - 状态回写（US-E3-01）

struct StatusUpdateTests {
    @Test func doneStatusRecordsCompletedAtAndProgressOne() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "回写项目")
        let id = try session.addTask(title: "完成的任务")
        let task = try session.statusUpdate(id: id, status: .done)
        #expect(task.status == .done)
        #expect(task.progress == 1)
        #expect(task.completedAt != nil)
    }

    @Test func progressUpdateReflectsWithoutCompleting() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "回写项目")
        let id = try session.addTask(title: "进行中的任务")
        let task = try session.statusUpdate(id: id, progress: 0.6)
        #expect(task.progress == 0.6)
        #expect(task.status == .pending)
        #expect(task.completedAt == nil)
    }

    @Test func progressAboveOneRejected() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "回写项目")
        let id = try session.addTask(title: "任务")
        #expect(throws: SessionError.self) {
            _ = try session.statusUpdate(id: id, progress: 1.5)
        }
    }

    @Test func progressBelowZeroRejected() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "回写项目")
        let id = try session.addTask(title: "任务")
        #expect(throws: SessionError.self) {
            _ = try session.statusUpdate(id: id, progress: -0.1)
        }
    }
}

// MARK: - 群组完成度聚合（US-E3-02）

struct GroupProgressTests {
    @Test func groupProgressWeightedByEffort() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "聚合项目")
        let groupID = try session.addTask(title: "群组 G", kind: .group)
        let doneID = try session.addTask(title: "子一", parentID: groupID, effortHours: 2)
        let pendingID = try session.addTask(title: "子二", parentID: groupID, effortHours: 8)
        _ = try session.statusUpdate(id: doneID, status: .done)
        _ = try session.statusUpdate(id: pendingID, progress: 0)
        let progress = try session.groupProgress(id: groupID)
        // (2×1 + 8×0) / 10 = 0.2。
        #expect(progress == 0.2)
    }

    @Test func groupProgressMixedEffortAndNoEffortLeaves() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "聚合项目")
        let groupID = try session.addTask(title: "群组 H", kind: .group)
        let doneID = try session.addTask(title: "有投入已完", parentID: groupID, effortHours: 2)
        let noEffortID = try session.addTask(title: "无投入未完", parentID: groupID)
        _ = try session.statusUpdate(id: doneID, status: .done)
        _ = try session.statusUpdate(id: noEffortID, progress: 0)
        // 无投入叶子按权重 1：(2×1 + 1×0) / 3 = 2/3。
        let progress = try session.groupProgress(id: groupID)
        #expect(abs(progress - 2.0 / 3.0) < 0.0001)
    }

    @Test func leafTaskReturnsOwnProgress() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "聚合项目")
        let id = try session.addTask(title: "叶子任务")
        _ = try session.statusUpdate(id: id, progress: 0.5)
        let progress = try session.groupProgress(id: id)
        #expect(progress == 0.5)
    }

    @Test func groupProgressAggregatesNestedGroups() throws {
        let session = KairoSession()
        _ = try session.createProject(title: "聚合项目")
        let topID = try session.addTask(title: "顶层群组", kind: .group)
        let subID = try session.addTask(title: "子群组", kind: .group, parentID: topID)
        let aID = try session.addTask(title: "孙任务", parentID: subID, effortHours: 4)
        _ = try session.statusUpdate(id: aID, status: .done)
        // 顶层群组的全部后代只有孙任务 → 100%。
        let progress = try session.groupProgress(id: topID)
        #expect(progress == 1)
    }
}
