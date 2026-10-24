import Foundation
import Testing

// MARK: - 夹具数据（用户数据，不翻译；断言与构造共用同一常量）
private let b0Fixture1 = "今日任务"
private let b0Fixture2 = "完成任务"
private let b0Fixture3 = "支付网关"
private let b0Fixture4 = "逾期任务"
@testable import KairoCore

// MARK: - Fixtures

private func makeTask(
    title: String = "任务",
    notes: String = "",
    dueDate: Date? = nil,
    priority: TaskPriority = .normal,
    status: TaskStatus = .pending,
    tags: [String] = [],
    assignee: String? = nil
) -> TaskItem {
    TaskItem(
        title: title,
        notes: notes,
        dueDate: dueDate,
        priority: priority,
        status: status,
        tags: tags,
        assignee: assignee
    )
}

private final class StubFindTarget: FindTarget {
    var texts: [String]
    private(set) var revealed: [Int] = []

    init(texts: [String]) {
        self.texts = texts
    }

    var findableText: [String] { texts }

    func revealMatch(at index: Int) {
        revealed.append(index)
    }
}

// MARK: - FindPatternTests

@Test func literalPatternMatchesCaseInsensitively() {
    let pattern = LiteralFindPattern(needle: "hello")
    let text = "Say Hello world"
    #expect(pattern.find(in: text, from: text.startIndex) != nil)
}

@Test func literalPatternIsCaseSensitiveWhenRequested() {
    let pattern = LiteralFindPattern(needle: "hello", caseSensitive: true)
    let text = "Say Hello world"
    #expect(pattern.find(in: text, from: text.startIndex) == nil)
}

@Test func regexPatternFindsFirstMatch() {
    let pattern = RegexFindPattern(pattern: "\\d+")
    let text = "abc 123 def"
    let range = pattern?.find(in: text, from: text.startIndex)
    #expect(range != nil)
    if let range {
        #expect(text[range] == "123")
    }
}

@Test func invalidRegexPatternFailsInit() {
    #expect(RegexFindPattern(pattern: "[") == nil)
}

// MARK: - SearchTermTests

@Test func searchTermContainsMatchesAndRejects() {
    let term = SearchTerm(key: .title, matcher: .contains("pay"))
    #expect(term.matches(makeTask(title: "Payment Gateway")))
    #expect(!term.matches(makeTask(title: "Login")))
}

@Test func searchTermEqualsMatchesAndRejects() {
    let term = SearchTerm(key: .status, matcher: .equals("done"))
    #expect(term.matches(makeTask(status: .done)))
    #expect(!term.matches(makeTask(status: .pending)))
}

@Test func searchTermIsValueMatchesPriority() {
    let term = SearchTerm(key: .priority, matcher: .isValue("high"))
    #expect(term.matches(makeTask(priority: .high)))
    #expect(!term.matches(makeTask(priority: .normal)))
}

@Test func searchTermHasTagMatchesAndRejects() {
    let term = SearchTerm(key: .tags, matcher: .hasTag("backend"))
    #expect(term.matches(makeTask(tags: ["backend", "api"])))
    #expect(!term.matches(makeTask(tags: ["frontend"])))
}

// MARK: - AIFilterTests

@Test func translateCombinesOverdueAndDone() {
    let clauses = AIFilterTranslator.translate("overdue done")
    #expect(clauses.count == 2)
    #expect(isOverdueClause(clauses[0]))
    let term = termClause(clauses[1])
    #expect(term?.key == .status)
    #expect(term?.matches(makeTask(status: .done)) == true)
}

@Test func translateUrgentAndTag() {
    let clauses = AIFilterTranslator.translate("紧急 tag:backend")
    #expect(clauses.count == 2)
    let priorityTerm = termClause(clauses[0])
    #expect(priorityTerm?.key == .priority)
    #expect(priorityTerm?.matches(makeTask(priority: .high)) == true)
    let tagTerm = termClause(clauses[1])
    #expect(tagTerm?.key == .tags)
    #expect(tagTerm?.matches(makeTask(tags: ["backend"])) == true)
}

@Test func translateTodayYieldsDueTodayClause() {
    let clauses = AIFilterTranslator.translate("today")
    #expect(clauses.count == 1)
    #expect(isDueTodayClause(clauses[0]))
}

@Test func translateUnknownTokenFallsBackToTitleContains() {
    let clauses = AIFilterTranslator.translate("onboarding")
    #expect(clauses.count == 1)
    let term = termClause(clauses[0])
    #expect(term?.key == .title)
    #expect(term?.matches(makeTask(title: "Onboarding flow")) == true)
}

@Test func explanationSummarizesClauses() {
    let clauses = AIFilterTranslator.translate("overdue done")
    let text = AIFilterTranslator.explanation(for: clauses)
    #expect(text.contains("筛选"))
    #expect(text.contains("逾期"))
    #expect(text.contains("status=done"))
}

@Test func applyFiltersFixtureTasks() {
    let calendar = Calendar.current
    let now = Date()
    let past = calendar.date(byAdding: .day, value: -1, to: now)!
    let future = calendar.date(byAdding: .day, value: 3, to: now)!
    // Late today: still today but never in the past, so not overdue.
    let todayEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!

    let tasks = [
        makeTask(title: b0Fixture4, dueDate: past, status: .pending),
        makeTask(title: b0Fixture2, dueDate: past, status: .done),
        makeTask(title: b0Fixture1, dueDate: todayEnd, status: .pending),
        makeTask(title: "未来任务", dueDate: future, status: .pending),
    ]

    let overdue = AIFilterTranslator.apply(clauses: [.overdue], to: tasks)
    #expect(overdue.count == 1)
    #expect(overdue.first?.title == b0Fixture4)

    let dueToday = AIFilterTranslator.apply(clauses: [.dueToday], to: tasks)
    #expect(dueToday.count == 1)
    #expect(dueToday.first?.title == b0Fixture1)

    let done = AIFilterTranslator.apply(
        clauses: [.term(SearchTerm(key: .status, matcher: .isValue("done")))],
        to: tasks
    )
    #expect(done.count == 1)
    #expect(done.first?.title == b0Fixture2)
}

@Test func applyAndCombinesClauses() {
    let tasks = [
        makeTask(title: b0Fixture3, status: .done, tags: ["backend"]),
        makeTask(title: b0Fixture3, status: .pending, tags: ["backend"]),
        makeTask(title: "登录页", status: .pending, tags: ["frontend"]),
    ]
    let clauses = AIFilterTranslator.translate("done tag:backend")
    let result = AIFilterTranslator.apply(clauses: clauses, to: tasks)
    #expect(result.count == 1)
    #expect(result.first?.title == b0Fixture3)
    #expect(result.first?.status == .done)
}

// MARK: - FindControllerTests

@MainActor
@Test func findControllerCountsAndWraps() {
    let controller = FindController()
    let target = StubFindTarget(texts: ["Hello world", "Goodbye", "Say hello"])
    controller.lastFindString = "hello"
    controller.attach(target: target)

    #expect(controller.matchCount == 2)
    #expect(controller.currentIndex == 0)

    controller.findNext()
    #expect(controller.currentIndex == 2)

    controller.findNext()
    #expect(controller.currentIndex == 0) // wraps around

    controller.findPrevious()
    #expect(controller.currentIndex == 2) // wraps back
}

@MainActor
@Test func findControllerReportsInvalidRegex() {
    let controller = FindController()
    let target = StubFindTarget(texts: ["abc"])
    controller.lastFindString = "["
    controller.regexMode = true
    controller.attach(target: target)

    #expect(controller.invalidRegex)
    #expect(controller.matchCount == 0)
}

// MARK: - Clause helpers

private func isOverdueClause(_ clause: FilterClause) -> Bool {
    if case .overdue = clause { return true }
    return false
}

private func isDueTodayClause(_ clause: FilterClause) -> Bool {
    if case .dueToday = clause { return true }
    return false
}

private func termClause(_ clause: FilterClause) -> SearchTerm? {
    if case .term(let term) = clause { return term }
    return nil
}
