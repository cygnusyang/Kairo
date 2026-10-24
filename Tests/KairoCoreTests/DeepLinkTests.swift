import Foundation
import Testing

@testable import KairoCore

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "验收"

// kairo:// 深链解析与定位（US-E5-04 / F-41-03）。

private func url(_ raw: String) -> URL {
    URL(string: raw)!
}

struct DeepLinkParsingTests {
    @Test func parsesTaskIDAndPrefix() throws {
        let id = UUID()
        let full = try #require(KairoDeepLink.parse(url("kairo://task/\(id.uuidString)")))
        #expect(full.target == .taskID(id.uuidString))

        let prefix = try #require(KairoDeepLink.parse(url("kairo://task/A1B2C3D4")))
        #expect(prefix.target == .taskID("A1B2C3D4"))
    }

    @Test func parsesPercentEncodedTitle() throws {
        let link = try #require(KairoDeepLink.parse(url("kairo://task?title=%E9%AA%8C%E6%94%B6")))
        #expect(link.target == .taskTitle(b0Fixture1))
    }

    @Test func parsesProjectID() throws {
        let id = UUID()
        let link = try #require(KairoDeepLink.parse(url("kairo://project/\(id.uuidString)")))
        #expect(link.target == .projectID(id))
    }

    @Test func rejectsMalformedLinks() {
        #expect(KairoDeepLink.parse(url("https://task/\(UUID())")) == nil)
        #expect(KairoDeepLink.parse(url("kairo://unknown/\(UUID())")) == nil)
        #expect(KairoDeepLink.parse(url("kairo://task")) == nil)
        #expect(KairoDeepLink.parse(url("kairo://task?title=%20")) == nil)
        #expect(KairoDeepLink.parse(url("kairo://project/not-a-uuid")) == nil)
        #expect(KairoDeepLink.parse(url("kairo://project")) == nil)
    }
}

struct DeepLinkResolutionTests {
    private func makeProject() -> (Project, TaskItem, TaskItem) {
        let project = Project(metadata: ProjectMetadata(title: "深链项目"))
        let first = TaskItem(title: b0Fixture1)
        let second = TaskItem(title: b0Fixture1)
        project.add(first)
        project.add(second)
        return (project, first, second)
    }

    @Test func resolvesUniqueIDPrefix() {
        let (project, first, _) = makeProject()
        let prefix = String(first.id.uuidString.prefix(8))
        let match = KairoDeepLinkResolver.resolve(
            KairoDeepLink(target: .taskID(prefix)),
            in: project
        )
        #expect(match.taskID == first.id)
        #expect(match.matchCount == 1)
    }

    @Test func rejectsShortOrUnknownPrefix() {
        let (project, _, _) = makeProject()
        let short = KairoDeepLinkResolver.resolve(
            KairoDeepLink(target: .taskID("A1B2")),
            in: project
        )
        #expect(short.taskID == nil)
        #expect(short.matchCount == 0)

        let unknown = KairoDeepLinkResolver.resolve(
            KairoDeepLink(target: .taskID("DEADBEEF")),
            in: project
        )
        #expect(unknown.taskID == nil)
    }

    @Test func titleTakesFirstMatchAndReportsAmbiguity() {
        let (project, first, _) = makeProject()
        let match = KairoDeepLinkResolver.resolve(
            KairoDeepLink(target: .taskTitle(b0Fixture1)),
            in: project
        )
        #expect(match.taskID == first.id)
        #expect(match.matchCount == 2)
    }

    @Test func titleFallsBackToCaseInsensitive() {
        let project = Project()
        let task = TaskItem(title: "Review Backend")
        project.add(task)
        let match = KairoDeepLinkResolver.resolve(
            KairoDeepLink(target: .taskTitle("review backend")),
            in: project
        )
        #expect(match.taskID == task.id)
        #expect(match.matchCount == 1)
    }

    @Test func projectLinkReportsMatchOnly() {
        let project = Project()
        let same = KairoDeepLinkResolver.resolve(
            KairoDeepLink(target: .projectID(project.metadata.id)),
            in: project
        )
        #expect(same.projectMatched)
        #expect(same.taskID == nil)

        let other = KairoDeepLinkResolver.resolve(
            KairoDeepLink(target: .projectID(UUID())),
            in: project
        )
        #expect(!other.projectMatched)
    }

    @Test func unknownTitleFindsNothing() {
        let (project, _, _) = makeProject()
        let match = KairoDeepLinkResolver.resolve(
            KairoDeepLink(target: .taskTitle("不存在")),
            in: project
        )
        #expect(match.taskID == nil)
        #expect(match.matchCount == 0)
    }
}
