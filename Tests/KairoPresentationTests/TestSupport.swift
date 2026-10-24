import Foundation
import KairoCore
import KairoPresentation

/// 固定 UTC 日历：避免测试随本机时区漂移。
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 快照的语言（F-0702）：与 testCalendar 一样钉死，避免测试随本机语言漂移。
let testLocale = Locale(identifier: "zh_CN")

func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day))!
}

func makeState(
    _ tasks: [TaskItem],
    title: String = "测试项目",
    projectStart: Date? = nil,
    resources: [Resource] = []
) -> ProjectState {
    ProjectState(
        metadata: ProjectMetadata(
            title: title,
            createdAt: makeDate(2025, 1, 1),
            updatedAt: makeDate(2025, 1, 1),
            projectStart: projectStart
        ),
        tasks: tasks,
        resources: resources
    )
}

func makeSchedule(
    _ tasks: [TaskItem],
    projectStart: Date? = nil,
    now: Date
) -> ScheduleResult {
    ScheduleEngine.compute(
        tasks: tasks,
        projectStart: projectStart,
        calendar: testCalendar,
        now: now
    )
}

func makeSnapshot(
    state: ProjectState,
    schedule: ScheduleResult?,
    violations: [Violation] = [],
    viewState: WorkspaceViewState = WorkspaceViewState(),
    viewport: WorkspaceViewport = WorkspaceViewport(canvasWidth: 800, canvasHeight: 600),
    locale: Locale = testLocale,
    now: Date,
    saveState: SaveState = .saved
) -> WorkspaceSnapshot {
    WorkspacePresenter.make(
        state: state,
        schedule: schedule,
        violations: violations,
        viewState: viewState,
        viewport: viewport,
        calendar: testCalendar,
        locale: locale,
        now: now,
        saveState: saveState
    )
}
