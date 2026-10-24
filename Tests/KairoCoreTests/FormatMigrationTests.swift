import Foundation
import Testing

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "当前格式"
private let b0Fixture2 = "端到端 v2 v3"
@testable import KairoCore

// MARK: - 合成迁移（仅测试使用）

/// 记录迁移步骤的执行顺序。
private final class MigrationRecorder {
    private(set) var appliedVersions: [Int] = []

    func record(_ version: Int) {
        appliedVersions.append(version)
    }
}

/// 成功迁移：把文档推进到 `toVersion`，并在根节点留下可断言的标记。
private struct RecordingMigration: FormatMigration {
    let toVersion: Int
    let recorder: MigrationRecorder

    func migrate(_ document: inout FormatDocument) throws {
        recorder.record(toVersion)
        document.root["migratedThrough\(toVersion)"] = true
        document.formatVersion = toVersion
    }
}

/// 违规迁移：不更新 `formatVersion`，用于验证管线的每步版本校验。
private struct VersionPreservingMigration: FormatMigration {
    let toVersion: Int

    func migrate(_ document: inout FormatDocument) throws {}
}

private enum SyntheticMigrationFailure: Error, CustomStringConvertible {
    case boom

    var description: String { "合成迁移拒绝继续" }
}

/// 抛错迁移：用于验证错误包装。
private struct ThrowingMigration: FormatMigration {
    let toVersion: Int

    func migrate(_ document: inout FormatDocument) throws {
        throw SyntheticMigrationFailure.boom
    }
}

/// 字段迁移：改写 project.title，用于证明解码的是迁移后的内容。
private struct FieldMigratingMigration: FormatMigration {
    let toVersion: Int
    let recorder: MigrationRecorder

    func migrate(_ document: inout FormatDocument) throws {
        recorder.record(toVersion)
        var project = document.root["project"] as? [String: Any] ?? [:]
        project["title"] = "\(project["title"] as? String ?? "") v\(toVersion)"
        document.root["project"] = project
        document.formatVersion = toVersion
    }
}

/// 破坏迁移：版本推进成功，但产出无法通过强类型解码。
private struct CorruptingMigration: FormatMigration {
    let toVersion: Int

    func migrate(_ document: inout FormatDocument) throws {
        document.root["project"] = "not-an-object"
        document.formatVersion = toVersion
    }
}

// MARK: - 夹具

private enum SyntheticFixtureError: Error {
    case invalidRoot
}

private func makeProject(title: String = "迁移测试项目") -> Project {
    let project = Project()
    project.metadata.title = title
    project.add(TaskItem(title: "任务 A"))
    return project
}

/// 构造指定 formatVersion 的合法 JSON 数据（合成旧格式）。
private func makeData(formatVersion: Int) throws -> Data {
    let encoded = try KairoFile.encode(project: makeProject(title: "端到端"))
    guard var root = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
        throw SyntheticFixtureError.invalidRoot
    }
    root["formatVersion"] = formatVersion
    return try JSONSerialization.data(withJSONObject: root)
}

/// 由指定版本的合法数据构造文档（合成旧格式）。
private func makeDocument(formatVersion: Int) throws -> FormatDocument {
    let encoded = try makeData(formatVersion: formatVersion)
    guard let root = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
        throw SyntheticFixtureError.invalidRoot
    }
    return FormatDocument(root: root)
}

/// 文件修改时间；用于断言打开/迁移失败不改动磁盘。
private func modificationDate(of url: URL) throws -> Date {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.modificationDate] as? Date)
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kairo-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 捕获错误，便于对 case 与关联值做细致断言。
private func capturedError<T>(_ body: () throws -> T) -> Error? {
    do {
        _ = try body()
        return nil
    } catch {
        return error
    }
}

// MARK: - FR-KAIRO-FMT-1：当前版本不做迁移

@Test func fr_kairo_fmt_1_current_version_skips_migration() throws {
    // 若管线错误地对当前版本执行迁移，该步骤会抛错。
    let plan = FormatMigrationPlan([ThrowingMigration(toVersion: KairoFile.currentFormatVersion + 1)])
    let data = try KairoFile.encode(project: makeProject(title: b0Fixture1))

    let decoded = try KairoFile.read(from: data, plan: plan)

    #expect(decoded.sourceFormatVersion == KairoFile.currentFormatVersion)
    #expect(decoded.project.metadata.title == b0Fixture1)
}

// MARK: - FR-KAIRO-FMT-2：顺序迁移

@Test func fr_kairo_fmt_2_migrates_steps_in_ascending_order() throws {
    let recorder = MigrationRecorder()
    // 故意乱序传入：管线必须按 toVersion 升序执行。
    let plan = FormatMigrationPlan([
        RecordingMigration(toVersion: 2, recorder: recorder),
        RecordingMigration(toVersion: 1, recorder: recorder),
    ])
    var document = try makeDocument(formatVersion: 0)

    try plan.migrate(from: 0, to: 2, document: &document)

    #expect(recorder.appliedVersions == [1, 2])
    #expect(document.formatVersion == 2)
    #expect(document.root["migratedThrough1"] as? Bool == true)
    #expect(document.root["migratedThrough2"] as? Bool == true)
}

@Test func fr_kairo_fmt_2_read_migrates_end_to_end() throws {
    let recorder = MigrationRecorder()
    // 乱序传入两步迁移；read 必须升序执行并解码迁移后的内容。
    let plan = FormatMigrationPlan([
        FieldMigratingMigration(toVersion: 3, recorder: recorder),
        FieldMigratingMigration(toVersion: 2, recorder: recorder),
    ])
    let data = try makeData(formatVersion: 1)

    let decoded = try KairoFile.read(from: data, targetVersion: 3, plan: plan)

    #expect(decoded.sourceFormatVersion == 1)
    #expect(recorder.appliedVersions == [2, 3])
    #expect(decoded.project.metadata.title == b0Fixture2)
    #expect(decoded.project.tasks.count == 1)
}

@Test func fr_kairo_fmt_2_rejects_backwards_range() throws {
    let plan = FormatMigrationPlan([RecordingMigration(toVersion: 2, recorder: MigrationRecorder())])
    var document = try makeDocument(formatVersion: 2)

    let error = capturedError {
        try plan.migrate(from: 2, to: 1, document: &document)
    }

    #expect((error as? KairoFileError) == .noMigrationPath(from: 2, to: 1))
}

@Test func fr_kairo_fmt_2_rejects_missing_step() throws {
    let recorder = MigrationRecorder()
    let plan = FormatMigrationPlan([RecordingMigration(toVersion: 1, recorder: recorder)])
    var document = try makeDocument(formatVersion: 0)

    let error = capturedError {
        try plan.migrate(from: 0, to: 2, document: &document)
    }

    #expect((error as? KairoFileError) == .noMigrationPath(from: 1, to: 2))
    #expect(recorder.appliedVersions == [1])
}

@Test func fr_kairo_fmt_2_rejects_version_skip() throws {
    let recorder = MigrationRecorder()
    // 缺少 toVersion 2 的步骤（1 → 2 段）：即便存在 1 与 3，也不得跳版。
    let plan = FormatMigrationPlan([
        RecordingMigration(toVersion: 1, recorder: recorder),
        RecordingMigration(toVersion: 3, recorder: recorder),
    ])
    var document = try makeDocument(formatVersion: 0)

    let error = capturedError {
        try plan.migrate(from: 0, to: 3, document: &document)
    }

    // 缺失的是 1 → 2 这一段（2 → 3 的步骤虽然存在，也不得跳版）。
    #expect((error as? KairoFileError) == .noMigrationPath(from: 1, to: 2))
    #expect(recorder.appliedVersions == [1])
}

@Test func fr_kairo_fmt_2_step_must_land_on_its_to_version() throws {
    let plan = FormatMigrationPlan([VersionPreservingMigration(toVersion: 1)])
    var document = try makeDocument(formatVersion: 0)

    let error = capturedError {
        try plan.migrate(from: 0, to: 1, document: &document)
    }

    guard let kairoError = error as? KairoFileError,
          case .migrationFailed(let from, let to, let reason) = kairoError else {
        Issue.record("应为 migrationFailed，实际 \(String(describing: error))")
        return
    }
    #expect(from == 0)
    #expect(to == 1)
    #expect(reason.contains("1"))
}

@Test func fr_kairo_fmt_2_rejects_document_version_mismatch() throws {
    let plan = FormatMigrationPlan([RecordingMigration(toVersion: 1, recorder: MigrationRecorder())])
    var document = try makeDocument(formatVersion: 0)

    let error = capturedError {
        try plan.migrate(from: 1, to: 2, document: &document)
    }

    guard let kairoError = error as? KairoFileError,
          case .migrationFailed(let from, let to, _) = kairoError else {
        Issue.record("应为 migrationFailed，实际 \(String(describing: error))")
        return
    }
    #expect(from == 1)
    #expect(to == 2)
}

// MARK: - FR-KAIRO-FMT-3：未来版本

@Test func fr_kairo_fmt_3_rejects_future_version() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("future.kairo")
    let encoded = try KairoFile.encode(project: makeProject())
    let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    var root = try #require(object)
    root["formatVersion"] = 999
    let bytes = try JSONSerialization.data(withJSONObject: root)
    try bytes.write(to: url)
    let mtimeBefore = try modificationDate(of: url)

    let error = capturedError { try KairoFile.read(from: url) }

    #expect((error as? KairoFileError) == .unsupportedFormatVersion(999))
    let description = (error as? KairoFileError)?.description ?? ""
    #expect(description.contains("999"))
    #expect(description.contains("\(KairoFile.currentFormatVersion)"))
    // 打开失败不得改动磁盘文件。
    #expect(try Data(contentsOf: url) == bytes)
    #expect(try modificationDate(of: url) == mtimeBefore)
}

// MARK: - FR-KAIRO-FMT-4：迁移失败

@Test func fr_kairo_fmt_4_throwing_step_is_wrapped_with_from_to() throws {
    let plan = FormatMigrationPlan([ThrowingMigration(toVersion: 1)])
    var document = try makeDocument(formatVersion: 0)

    let error = capturedError {
        try plan.migrate(from: 0, to: 1, document: &document)
    }

    guard let kairoError = error as? KairoFileError,
          case .migrationFailed(let from, let to, let reason) = kairoError else {
        Issue.record("应为 migrationFailed，实际 \(String(describing: error))")
        return
    }
    #expect(from == 0)
    #expect(to == 1)
    #expect(reason.contains("合成迁移拒绝继续"))
}

@Test func fr_kairo_fmt_4_failed_migration_writes_nothing() throws {
    // 经 URL read 端到端触发步骤抛错；源文件字节、mtime 与目录清单均不得变化。
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("source.kairo")
    let sourceBytes = try makeData(formatVersion: 1)
    try sourceBytes.write(to: sourceURL)
    let mtimeBefore = try modificationDate(of: sourceURL)

    let plan = FormatMigrationPlan([ThrowingMigration(toVersion: 2)])
    let error = capturedError {
        try KairoFile.read(from: sourceURL, targetVersion: 2, plan: plan)
    }

    guard let kairoError = error as? KairoFileError,
          case .migrationFailed(let from, let to, let reason) = kairoError else {
        Issue.record("应为 migrationFailed，实际 \(String(describing: error))")
        return
    }
    #expect(from == 1)
    #expect(to == 2)
    #expect(reason.contains("合成迁移拒绝继续"))
    #expect(try Data(contentsOf: sourceURL) == sourceBytes)
    #expect(try modificationDate(of: sourceURL) == mtimeBefore)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["source.kairo"])
}

@Test func fr_kairo_fmt_4_decode_failure_after_migration_is_wrapped() throws {
    // 迁移推进了版本但产出无法强类型解码：应包装为 migrationFailed(from:to:)。
    let data = try makeData(formatVersion: 1)
    let plan = FormatMigrationPlan([CorruptingMigration(toVersion: 2)])

    let error = capturedError {
        try KairoFile.read(from: data, targetVersion: 2, plan: plan)
    }

    guard let kairoError = error as? KairoFileError,
          case .migrationFailed(let from, let to, let reason) = kairoError else {
        Issue.record("应为 migrationFailed，实际 \(String(describing: error))")
        return
    }
    #expect(from == 1)
    #expect(to == 2)
    #expect(reason.contains("解码"))
}

@Test func fr_kairo_fmt_decode_error_without_migration_is_preserved() throws {
    // 不迁移路径保持原有行为：强类型解码失败仍抛 DecodingError，不做包装。
    let json = #"{"formatVersion":\#(KairoFile.currentFormatVersion)}"#
    let error = capturedError {
        try KairoFile.read(from: Data(json.utf8))
    }

    #expect((error as? DecodingError) != nil)
    #expect((error as? KairoFileError) == nil)
}

// MARK: - 无效 formatVersion：缺失 / 非整数 / ≤0

@Test func fr_kairo_fmt_malformed_missing_version_is_rejected_without_migration() throws {
    let recorder = MigrationRecorder()
    let plan = FormatMigrationPlan([RecordingMigration(toVersion: 1, recorder: recorder)])
    let json = #"{"project":{},"tasks":[]}"#

    let error = capturedError {
        try KairoFile.read(from: Data(json.utf8), plan: plan)
    }

    guard let kairoError = error as? KairoFileError,
          case .malformedFormatVersion = kairoError else {
        Issue.record("应为 malformedFormatVersion，实际 \(String(describing: error))")
        return
    }
    #expect(recorder.appliedVersions.isEmpty)
}

@Test(arguments: [
    #"{"formatVersion":"1","project":{},"tasks":[]}"#,
    #"{"formatVersion":1.5,"project":{},"tasks":[]}"#,
    #"{"formatVersion":true,"project":{},"tasks":[]}"#,
])
func fr_kairo_fmt_malformed_non_integer_version_is_rejected(json: String) throws {
    let error = capturedError {
        try KairoFile.read(from: Data(json.utf8))
    }

    guard let kairoError = error as? KairoFileError,
          case .malformedFormatVersion = kairoError else {
        Issue.record("应为 malformedFormatVersion，实际 \(String(describing: error))")
        return
    }
}

@Test(arguments: [
    #"{"formatVersion":0,"project":{},"tasks":[]}"#,
    #"{"formatVersion":-1,"project":{},"tasks":[]}"#,
])
func fr_kairo_fmt_malformed_non_positive_version_is_rejected(json: String) throws {
    let recorder = MigrationRecorder()
    // 即便存在一个覆盖 1 的迁移步骤，0/-1 也不得被当作旧版本迁移。
    let plan = FormatMigrationPlan([RecordingMigration(toVersion: 1, recorder: recorder)])

    let error = capturedError {
        try KairoFile.read(from: Data(json.utf8), plan: plan)
    }

    guard let kairoError = error as? KairoFileError,
          case .malformedFormatVersion = kairoError else {
        Issue.record("应为 malformedFormatVersion，实际 \(String(describing: error))")
        return
    }
    #expect(recorder.appliedVersions.isEmpty)
}

@Test(arguments: [
    "{ not json",
    "[]",
    #""scalar""#,
    "42",
    "null",
])
func fr_kairo_fmt_malformed_invalid_json_or_non_object_root_is_rejected(payload: String) throws {
    // 非法 JSON 与数组/标量根节点都归一为 malformedFormatVersion，不抛裸 NSError。
    let error = capturedError {
        try KairoFile.read(from: Data(payload.utf8))
    }

    guard let kairoError = error as? KairoFileError,
          case .malformedFormatVersion(let reason) = kairoError else {
        Issue.record("应为 malformedFormatVersion，实际 \(String(describing: error))")
        return
    }
    #expect(!reason.isEmpty)
}
