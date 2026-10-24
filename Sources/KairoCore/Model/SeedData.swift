import Foundation

/// 示例项目的生成语言（F-D7 / F-0705）。
///
/// 模板属于产品生成内容，不属于用户数据：按创建时的界面语言选一套写入；
/// 写入之后即按用户数据处理，不再随语言变化重写（避免同一文件出现两种语言）。
public enum SeedLanguage: String, Codable, Hashable, Sendable {
    case en
    case zhHans
}

/// Sample data shown on first launch: a realistic project with varied
/// statuses, priorities, tags and dates relative to now.
///
/// 结构与两套文案分开：任务数量、依赖关系、日期偏移、优先级/状态在两语言下完全一致，
/// 只有标题 / 备注 / 标签随 `language` 变化（F-D7）。
public enum SeedData {
    /// 生成示例项目。
    ///
    /// - Parameter language: 模板语言。默认中文——与 v0.8.5 行为一致，零破坏；
    ///   界面层应按当前生效语言显式传入（英文界面载入英文示例，F-0705 判据）。
    public static func makeProject(language: SeedLanguage = .zhHans) -> Project {
        let copy = Copy(language: language)
        let project = Project()
        let now = Date()
        let calendar = Calendar.current

        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: now) ?? now
        }

        let backend = TaskItem(
            title: copy.backend.title,
            notes: copy.backend.notes,
            startDate: day(-2),
            dueDate: day(0),
            priority: .critical,
            status: .inProgress,
            tags: copy.backend.tags,
            assignee: "Bob",
            progress: 0.6
        )
        let review = TaskItem(
            title: copy.review.title,
            notes: copy.review.notes,
            dueDate: day(0),
            priority: .high,
            status: .blocked,
            tags: copy.review.tags,
            assignee: "Bob",
            dependencies: [TaskDependency(predecessorID: backend.id)],
            progress: 0.1
        )
        let release = TaskItem(
            title: copy.release.title,
            notes: copy.release.notes,
            dueDate: day(30),
            priority: .high,
            status: .pending,
            tags: copy.release.tags,
            assignee: "Mei",
            dependencies: [TaskDependency(predecessorID: review.id)],
            progress: 0
        )
        let design = TaskItem(
            title: copy.design.title,
            notes: copy.design.notes,
            startDate: day(-4),
            dueDate: day(-1),
            priority: .high,
            status: .pending,
            tags: copy.design.tags,
            assignee: "Alice",
            progress: 0.3
        )
        let loginCrash = TaskItem(
            title: copy.loginCrash.title,
            notes: copy.loginCrash.notes,
            dueDate: day(-2),
            priority: .critical,
            status: .done,
            tags: copy.loginCrash.tags,
            assignee: "Alice",
            progress: 1
        )
        let perf = TaskItem(
            title: copy.perf.title,
            notes: copy.perf.notes,
            dueDate: day(-3),
            priority: .high,
            status: .inProgress,
            tags: copy.perf.tags,
            assignee: "Bob",
            progress: 0.5
        )
        let feedback = TaskItem(
            title: copy.feedback.title,
            notes: copy.feedback.notes,
            dueDate: day(7),
            priority: .normal,
            status: .pending,
            tags: copy.feedback.tags,
            assignee: "Alice",
            progress: 0
        )
        let ci = TaskItem(
            title: copy.ci.title,
            notes: copy.ci.notes,
            dueDate: day(14),
            priority: .normal,
            status: .pending,
            tags: copy.ci.tags,
            assignee: "Mei",
            progress: 0
        )
        let interview = TaskItem(
            title: copy.interview.title,
            notes: copy.interview.notes,
            dueDate: day(-5),
            priority: .low,
            status: .done,
            tags: copy.interview.tags,
            assignee: "Alice",
            progress: 1
        )
        let spec = TaskItem(
            title: copy.spec.title,
            notes: copy.spec.notes,
            dueDate: day(3),
            priority: .normal,
            status: .pending,
            tags: copy.spec.tags,
            assignee: "Mei",
            progress: 0
        )

        // 演示项目时间线锚定到当前日期附近：排期引擎未设项目起点时从 1970 纪元起算，
        // 会让甘特显示 1970 年日期、时限违例无法用常规日期触发（D-002）。
        project.metadata.projectStart = day(-2)
        project.metadata.projectEnd = day(30)

        for task in [backend, review, release, design, loginCrash, perf, feedback, ci, interview, spec] {
            project.add(task)
        }
        return project
    }

    // MARK: - 文案

    /// 单条任务的模板文案（标题 / 备注 / 标签）。
    private struct Template {
        var title: String
        var notes: String
        var tags: [String]
    }

    /// 一套完整模板：字段语义两语言一一对应，缺一不可。
    private struct Copy {
        let backend: Template
        let review: Template
        let release: Template
        let design: Template
        let loginCrash: Template
        let perf: Template
        let feedback: Template
        let ci: Template
        let interview: Template
        let spec: Template

        init(language: SeedLanguage) {
            switch language {
            case .zhHans:
                backend = Template(
                    title: "实现搜索后端",
                    notes: "接入 FindController 与分词匹配，支持 ⌘F 全列表查找",
                    tags: ["后端", "搜索"]
                )
                review = Template(
                    title: "Code Review 搜索模块",
                    notes: "重点检查 wrap-around 与大小写匹配",
                    tags: ["评审"]
                )
                release = Template(
                    title: "发布 v1.0",
                    notes: "里程碑：功能冻结后打包并发布",
                    tags: ["里程碑"]
                )
                design = Template(
                    title: "设计首页原型",
                    notes: "覆盖任务列表、筛选栏与详情面板",
                    tags: ["设计"]
                )
                loginCrash = Template(
                    title: "修复登录崩溃",
                    notes: "用户反馈偶发闪退，根因已定位",
                    tags: ["Bug", "前端"]
                )
                perf = Template(
                    title: "优化启动性能",
                    notes: "冷启动从 1.8s 降到 0.9s",
                    tags: ["性能"]
                )
                feedback = Template(
                    title: "整理用户反馈",
                    notes: "汇总内测反馈并按主题聚类",
                    tags: ["调研"]
                )
                ci = Template(
                    title: "搭建 CI 流水线",
                    notes: "swift build + swift test 门禁",
                    tags: ["工程"]
                )
                interview = Template(
                    title: "用户访谈记录",
                    notes: "完成 5 场访谈并输出纪要",
                    tags: ["调研"]
                )
                spec = Template(
                    title: "撰写技术方案文档",
                    notes: "明确搜索架构与筛选语义",
                    tags: ["文档"]
                )
            case .en:
                backend = Template(
                    title: "Build search backend",
                    notes: "Wire up FindController and token matching; ⌘F searches the whole list",
                    tags: ["Backend", "Search"]
                )
                review = Template(
                    title: "Code review: search module",
                    notes: "Focus on wrap-around and case-insensitive matching",
                    tags: ["Review"]
                )
                release = Template(
                    title: "Ship v1.0",
                    notes: "Milestone: package and release after the feature freeze",
                    tags: ["Milestone"]
                )
                design = Template(
                    title: "Design home screen prototype",
                    notes: "Cover the task list, filter bar and detail panel",
                    tags: ["Design"]
                )
                loginCrash = Template(
                    title: "Fix login crash",
                    notes: "Intermittent crash reported by users; root cause identified",
                    tags: ["Bug", "Frontend"]
                )
                perf = Template(
                    title: "Improve launch performance",
                    notes: "Cold start cut from 1.8s to 0.9s",
                    tags: ["Performance"]
                )
                feedback = Template(
                    title: "Triage user feedback",
                    notes: "Cluster beta feedback by theme",
                    tags: ["Research"]
                )
                ci = Template(
                    title: "Set up CI pipeline",
                    notes: "swift build and swift test gates",
                    tags: ["Engineering"]
                )
                interview = Template(
                    title: "User interview notes",
                    notes: "Run five interviews and publish the summaries",
                    tags: ["Research"]
                )
                spec = Template(
                    title: "Write the technical design doc",
                    notes: "Pin down the search architecture and filter semantics",
                    tags: ["Docs"]
                )
            }
        }
    }
}
