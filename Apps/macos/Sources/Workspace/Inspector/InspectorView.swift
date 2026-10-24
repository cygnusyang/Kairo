import SwiftUI
import KairoCore
import KairoPresentation

/// 检查器（280–420pt）：任务 / 项目 / 违例三页。
struct InspectorView: View {
    @ObservedObject var store: WorkspaceStore
    let snapshot: InspectorSnapshot
    let width: CGFloat
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            ScrollView {
                content
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: width)
        .background(DesignTokens.surfaceBase)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)
            Text(breadcrumb)
                .font(.system(size: DesignTokens.bodyFontSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if case .task = snapshot.content {
                Button {
                    store.dispatch(.setInspectorLocked(!snapshot.locked))
                } label: {
                    Image(systemName: snapshot.locked ? "lock.fill" : "lock.open")
                        .font(.system(size: 11))
                        .foregroundStyle(snapshot.locked
                            ? DesignTokens.accentStrong
                            : DesignTokens.textSecondary)
                }
                .buttonStyle(.plain)
                .help(snapshot.locked ? "解锁检查器" : "锁定当前任务")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .buttonStyle(.plain)
            .help("隐藏检查器")
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(DesignTokens.surfaceChrome)
    }

    private var breadcrumb: String {
        switch snapshot.content {
        case .task(let task): return task.title
        case .project(let project): return project.title
        case .violations: return "违例"
        }
    }

    private var violationCount: Int {
        let violationInspector = violationSnapshot
        return (violationInspector?.errorCount ?? 0) + (violationInspector?.warningCount ?? 0)
    }

    private var violationSnapshot: ViolationInspector? {
        if case .violations(let inspector) = snapshot.content { return inspector }
        return nil
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "检查器", tab: .inspector)
            tabButton(
                title: violationCount > 0 ? "违例 \(violationCount)" : "违例",
                tab: .violations
            )
        }
        .frame(height: 30)
        .background(DesignTokens.surfaceChrome)
    }

    private func tabButton(title: String, tab: InspectorTab) -> some View {
        Button {
            store.dispatch(.setInspectorTab(tab))
        } label: {
            Text(title)
                .font(.system(size: DesignTokens.captionFontSize, weight: snapshot.tab == tab ? .semibold : .regular))
                .foregroundStyle(snapshot.tab == tab
                    ? DesignTokens.textPrimary
                    : DesignTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .overlay(alignment: .bottom) {
                    if snapshot.tab == tab {
                        Rectangle()
                            .fill(DesignTokens.accentStrong)
                            .frame(height: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.locked, store.inspectorSelectionDrift {
                driftBanner
            }
            if snapshot.locked, store.lockedTaskID == nil, let title = store.lockedTaskTitle {
                missingBanner(title: title)
            }
            switch snapshot.content {
            case .task(let task):
                TaskInspectorContent(store: store, task: task)
            case .project(let project):
                ProjectInspectorContent(store: store, project: project)
            case .violations(let violations):
                ViolationInspectorContent(store: store, violations: violations)
            }
        }
    }

    private var driftBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
            Text("选择已变更：\(store.selectedTaskTitle ?? "未选择")")
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("切换") {
                store.dispatch(.setInspectorLocked(false))
                store.dispatch(.setInspectorLocked(true))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.accentStrong)
        }
        .font(.system(size: DesignTokens.captionFontSize))
        .padding(8)
        .background(DesignTokens.surfaceChrome, in: RoundedRectangle(cornerRadius: 6))
    }

    private func missingBanner(title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
            Text("任务已删除：\(title)")
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("关闭") {
                store.dispatch(.setInspectorLocked(false))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.accentStrong)
        }
        .font(.system(size: DesignTokens.captionFontSize))
        .padding(8)
        .background(DesignTokens.surfaceChrome, in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - 任务页

private struct TaskInspectorContent: View {
    @ObservedObject var store: WorkspaceStore
    let task: TaskInspector

    @State private var showingDependencyPicker = false

    var body: some View {
        if task.isAggregate {
            Text("群组字段由子任务聚合，只读。")
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textSecondary)
        }

        section("信息") {
            FieldRow(label: "标题") {
                TextField("标题", text: Binding(
                    get: { task.title },
                    set: { store.dispatch(.rename(task.taskID, $0)) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            FieldRow(label: "类型") {
                Text(Display.kindTitle(task.kind))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            FieldRow(label: "状态") {
                Menu {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        Button {
                            store.dispatch(.setStatus(task.taskID, status))
                        } label: {
                            Label(Display.statusTitle(status), systemImage: Display.statusSymbol(status))
                        }
                    }
                } label: {
                    Text(Display.statusTitle(task.status))
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            FieldRow(label: "优先级") {
                Menu {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Button(Display.priorityTitle(priority)) {
                            store.dispatch(.setPriority(task.taskID, priority))
                        }
                    }
                } label: {
                    Text(Display.priorityTitle(task.priority))
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            FieldRow(label: "负责人") {
                TextField("负责人", text: Binding(
                    get: { task.assignee ?? "" },
                    set: { text in
                        let trimmed = text.trimmingCharacters(in: .whitespaces)
                        store.dispatch(.setAssignee(task.taskID, trimmed.isEmpty ? nil : trimmed))
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(task.isAggregate)
            }
            if !task.tags.isEmpty {
                FieldRow(label: "标签") {
                    Text(task.tags.joined(separator: " · "))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(2)
                }
            }
        }

        section("排期") {
            DateFieldRow(
                label: "开始",
                value: task.startDate,
                placeholder: "未设置",
                helper: plannedStartHelper,
                isEnabled: !task.isAggregate,
                disabledReason: "群组字段由子任务聚合，只读",
                allowsClear: true,
                preview: { startPreview(for: $0) },
                onCommit: { date in
                    store.dispatch(.setTaskStart(task.taskID, date))
                }
            )
            DateFieldRow(
                label: "结束",
                value: finishValue,
                placeholder: "无排期",
                helper: finishHelper,
                isEnabled: finishDisabledReason == nil,
                disabledReason: finishDisabledReason,
                minimumDate: finishMinimumDate,
                allowsClear: false,
                boundaryHint: Self.finishBoundaryHint,
                preview: { finishPreview(for: $0) },
                onCommit: { date in
                    guard let date, let start = finishStart else { return }
                    store.dispatch(.setTaskFinish(task.taskID, finish: date, start: start))
                }
            )
            FieldRow(label: "持续时间") {
                TextField("天", text: Binding(
                    get: { task.durationDays.map { String(format: "%g", $0) } ?? "" },
                    set: { text in
                        store.dispatch(.setDuration(task.taskID, Double(text)))
                    }
                ))
                .textFieldStyle(.roundedBorder)
                // 里程碑恒为 0 天：与「结束」行一致，不提供编辑入口（设计 §1.1）。
                .disabled(task.isAggregate || task.kind == .milestone)
            }
            FieldRow(label: "投入") {
                readOnly(task.effortHours.map { String(format: "%g 小时", $0) } ?? "—")
            }
            FieldRow(label: "宽延") {
                readOnly(task.slackDays.map { Display.duration($0) } ?? "—")
            }
            DateFieldRow(
                label: "截止日期",
                value: task.dueDate,
                allowsClear: true,
                onCommit: { date in
                    store.dispatch(.setDueDate(task.taskID, date))
                }
            )
            FieldRow(label: "排期策略") {
                readOnly(Display.scheduleTitle(task.schedulingPolicy))
            }
            if task.deadlineRisk {
                Label("计划结束晚于截止日期", systemImage: "exclamationmark.circle")
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.violationWarning)
            }
            if task.isOverdue {
                Label("已逾期", systemImage: "clock")
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.overdue)
            }
            if !task.hasSchedule {
                Label(
                    Display.unscheduledReason(task.unscheduledReason),
                    systemImage: "calendar.badge.exclamationmark"
                )
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textSecondary)
            }
        }

        section("相关性") {
            if task.predecessors.isEmpty {
                Text("无前置任务")
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            ForEach(task.predecessors) { row in
                HStack(spacing: 6) {
                    Text(row.title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(Display.dependencyTitle(row.type)) · \(Display.duration(row.lagDays))")
                        .font(.system(size: DesignTokens.captionFontSize))
                        .foregroundStyle(DesignTokens.textSecondary)
                    Button {
                        store.dispatch(.removeDependency(taskID: task.taskID, predecessorID: row.taskID))
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("删除前置任务")
                }
                .font(.system(size: DesignTokens.captionFontSize))
                .contentShape(Rectangle())
                .onTapGesture { store.reveal(row.taskID) }
            }
            Button("添加前置任务…") {
                showingDependencyPicker = true
            }
            .buttonStyle(.link)
            .font(.system(size: DesignTokens.captionFontSize))

            if !task.successors.isEmpty {
                Divider()
                Text("后继任务")
                    .font(.system(size: DesignTokens.captionFontSize, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
                ForEach(task.successors) { row in
                    HStack(spacing: 6) {
                        Text(row.title).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(Display.dependencyTitle(row.type))
                            .font(.system(size: DesignTokens.captionFontSize))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .font(.system(size: DesignTokens.captionFontSize))
                    .contentShape(Rectangle())
                    .onTapGesture { store.reveal(row.taskID) }
                }
            }
        }

        section("进度") {
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { task.progress },
                        set: { store.dispatch(.setProgress(task.taskID, $0)) }
                    ),
                    in: 0...1
                )
                Text(Display.percent(task.progress))
                    .monospacedDigit()
                    .font(.system(size: DesignTokens.captionFontSize))
                    .frame(width: 36, alignment: .trailing)
            }
            .disabled(task.isAggregate)
            if let completedAt = task.completedAt {
                FieldRow(label: "完成于") { readOnly(Display.date(completedAt)) }
            }
        }

        section("备注") {
            TextEditor(text: Binding(
                get: { task.notes },
                set: { store.dispatch(.setNotes(task.taskID, $0)) }
            ))
            .font(.system(size: DesignTokens.bodyFontSize))
            .frame(minHeight: 64)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(DesignTokens.separator, lineWidth: 1)
            }
        }

        section("资源") {
            if task.assignmentNames.isEmpty {
                Text("无分配")
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                Text(task.assignmentNames.joined(separator: " · "))
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
        }

        if !task.violations.isEmpty {
            section("违例") {
                ForEach(task.violations, id: \.self) { violation in
                    Label(ViolationText.message(violation.reason), systemImage: "exclamationmark.triangle")
                        .font(.system(size: DesignTokens.captionFontSize))
                        .foregroundStyle(violation.severity == .error
                            ? DesignTokens.violationError
                            : DesignTokens.violationWarning)
                }
            }
        }

        Button("删除任务…", role: .destructive) {
            // 统一由 WorkspaceStore 判断是否需要确认与级联。
            store.requestDelete(id: task.taskID)
        }
        .font(.system(size: DesignTokens.captionFontSize))
        .padding(.top, 4)
        .sheet(isPresented: $showingDependencyPicker) {
            DependencyPicker(
                candidates: store.predecessorCandidates(for: task.taskID)
            ) { predecessorID, type, lagDays in
                store.dispatch(.addDependency(
                    taskID: task.taskID,
                    predecessorID: predecessorID,
                    type: type,
                    lagDays: lagDays
                ))
                showingDependencyPicker = false
            }
        }
    }

    // MARK: - 日期字段

    /// 结束字段的最小可选日提示（越界格 tooltip / 无障碍说明）。
    private static let finishBoundaryHint = "结束须晚于开始，至少 1 天"

    /// 「结束」换算采用的起点：排期起点优先，其次意图起点（设计 §1.4）。
    private var finishStart: Date? { task.scheduledStart ?? task.startDate }

    /// 「结束」显示值：排期结果；无排期时回退「起点 + 持续时间」（设计 §1.1）。
    ///
    /// 两者都夹取到最小可选日之后：亚日持续时间（< 1 天）会让原始结束日落在
    /// 「起点 + 1 天」之前，显示成不可选的死格（M-4）。
    private var finishValue: Date? {
        let finish: Date
        if let scheduledFinish = task.scheduledFinish {
            finish = scheduledFinish
        } else if let start = finishStart {
            finish = ScheduleDateMath.finish(start: start, durationDays: task.durationDays ?? 1)
        } else {
            return nil
        }
        return DateFieldValueMath.clampedFinish(finish, minimumDate: finishMinimumDate)
    }

    /// 结束行副行：排他口径 + 亚日持续时间的下限说明（M-4）。
    private var finishHelper: String {
        guard let duration = task.durationDays, duration > 0, duration < 1 else {
            return "结束日不含当天"
        }
        return "结束日不含当天；持续时间不足 1 天，结束日按最少 1 天显示"
    }

    /// 结束行最小可选日：起点 + 1 天（排他）；里程碑为起点当日（该行本身禁用）。
    private var finishMinimumDate: Date? {
        guard let start = finishStart else { return nil }
        return ScheduleDateMath.minimumFinish(start: start, kind: task.kind)
    }

    /// 结束行禁用原因，判定顺序：群组 → 里程碑 → 无起点。
    private var finishDisabledReason: String? {
        if task.isAggregate { return "群组字段由子任务聚合，只读" }
        if task.kind == .milestone { return "里程碑无持续时间" }
        if finishStart == nil {
            return "无排期（\(Display.unscheduledReason(task.unscheduledReason))），无法设置结束"
        }
        return nil
    }

    /// 「计划开始」副行：与意图起点相差 ≥ 1 天才显示（设计 §1.1）。
    private var plannedStartHelper: String? {
        guard let startDate = task.startDate, let planned = task.scheduledStart else { return nil }
        guard abs(ScheduleDateMath.dayOffset(from: startDate, to: planned)) >= 1 else { return nil }
        return "计划开始 \(Display.isoDate(planned))"
    }

    /// 开始弹层预览：「开始日 – 结束日 · N 天」（按当前持续时间推结束日）。
    private func startPreview(for date: Date?) -> String? {
        guard let date else { return nil }
        let days = (task.durationDays ?? 1).rounded()
        guard days >= 1 else { return nil }
        let finish = ScheduleDateMath.finish(start: date, durationDays: days)
        return Self.spanText(from: date, to: finish)
    }

    /// 结束弹层预览：「起点 – 选中日 · N 天」；小数持续时间额外明示换算（设计 §1.4）。
    private func finishPreview(for date: Date?) -> String? {
        guard let date, let start = finishStart else { return nil }
        let span = Self.spanText(from: start, to: date)
        guard let duration = task.durationDays, abs(duration - duration.rounded()) > 0.0001 else {
            return span
        }
        let days = ScheduleDateMath.dayOffset(from: start, to: date)
        return "\(span)（\(Display.duration(duration)) → \(days) 天）"
    }

    private static func spanText(from start: Date, to finish: Date) -> String {
        let days = ScheduleDateMath.dayOffset(from: start, to: finish)
        return "\(monthDayText(start)) – \(monthDayText(finish)) · \(days) 天"
    }

    private static func monthDayText(_ date: Date) -> String {
        String(Display.isoDate(date).suffix(5))
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: DesignTokens.captionFontSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surfaceChrome, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func readOnly(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 项目页

private struct ProjectInspectorContent: View {
    @ObservedObject var store: WorkspaceStore
    let project: ProjectInspector

    var body: some View {
        section("项目") {
            FieldRow(label: "标题") {
                TextField("标题", text: Binding(
                    get: { project.title },
                    set: { store.dispatch(.setProjectTitle($0)) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            DateFieldRow(
                label: "开始",
                value: project.projectStart,
                allowsClear: true,
                onCommit: { store.dispatch(.setProjectStart($0)) }
            )
            DateFieldRow(
                label: "结束",
                value: project.projectEnd,
                allowsClear: true,
                onCommit: { store.dispatch(.setProjectEnd($0)) }
            )
            FieldRow(label: "方向") {
                Menu {
                    Button("尽快开始（ASAP）") {
                        store.dispatch(.setProjectDirection(.forward))
                    }
                    Button("尽快结束（ALAP）") {
                        store.dispatch(.setProjectDirection(.backward))
                    }
                } label: {
                    Text(Display.directionTitle(project.direction))
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        section("健康摘要") {
            HStack(spacing: 6) {
                Circle()
                    .fill(healthColor)
                    .frame(width: 7, height: 7)
                Text(Display.healthTitle(project.summary.health))
                Spacer(minLength: 0)
                Text(Display.percent(project.summary.totalProgress))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .font(.system(size: DesignTokens.bodyFontSize))
            summaryLine("逾期", "\(project.summary.overdueCount)")
            summaryLine("违例", "\(project.summary.errorCount) 错误 · \(project.summary.warningCount) 警告")
            summaryLine("重要路径", "\(project.summary.criticalPathCount)")
            summaryLine("剩余天数", project.summary.remainingDays.map { String($0) } ?? "—")
        }

        section("最近完成") {
            if project.recentCompletions.isEmpty {
                Text("暂无完成记录")
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            ForEach(project.recentCompletions) { item in
                RecentCompletionRow(item: item) {
                    store.reveal(item.id)
                }
            }
        }

        section("文件") {
            summaryLine("保存状态", Display.saveStateTitle(project.saveState))
        }
    }

    private var healthColor: Color {
        switch project.summary.health {
        case .green: return DesignTokens.statusSuccess
        case .orange: return DesignTokens.violationWarning
        case .red: return DesignTokens.violationError
        }
    }

    private func summaryLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(DesignTokens.textSecondary)
            Spacer(minLength: 0)
            Text(value).monospacedDigit()
        }
        .font(.system(size: DesignTokens.captionFontSize))
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: DesignTokens.captionFontSize, weight: .semibold))
                .foregroundStyle(DesignTokens.textSecondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surfaceChrome, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - 违例页

private struct ViolationInspectorContent: View {
    @ObservedObject var store: WorkspaceStore
    let violations: ViolationInspector

    var body: some View {
        if violations.groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("无违例", systemImage: "checkmark.seal")
                    .foregroundStyle(DesignTokens.statusSuccess)
                Text("已检查规则")
                    .font(.system(size: DesignTokens.captionFontSize, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)
                ForEach(violations.checkedRules, id: \.code) { rule in
                    HStack(spacing: 6) {
                        Image(systemName: rule.severity == .error
                            ? "exclamationmark.octagon"
                            : "exclamationmark.triangle")
                            .font(.system(size: 9))
                            .foregroundStyle(rule.severity == .error
                                ? DesignTokens.violationError
                                : DesignTokens.violationWarning)
                        Text(ViolationText.ruleName(rule.code))
                            .font(.system(size: DesignTokens.captionFontSize))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
            .padding(8)
        } else {
            ForEach(violations.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(group.severity == .error ? "错误" : "警告")
                            .font(.system(size: DesignTokens.captionFontSize, weight: .semibold))
                            .foregroundStyle(group.severity == .error
                                ? DesignTokens.violationError
                                : DesignTokens.violationWarning)
                        Text("\(group.items.count)")
                            .font(.system(size: DesignTokens.captionFontSize))
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    ForEach(group.items) { item in
                        Button {
                            if let taskID = item.taskID { store.reveal(taskID) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ViolationText.message(item.reason))
                                    .lineLimit(2)
                                if let title = item.taskTitle {
                                    Text(title)
                                        .font(.system(size: DesignTokens.captionFontSize))
                                        .foregroundStyle(DesignTokens.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: DesignTokens.captionFontSize))
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.surfaceChrome, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

// MARK: - 字段组件

private struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: DesignTokens.captionFontSize))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 68, alignment: .leading)
            content()
                .font(.system(size: DesignTokens.bodyFontSize))
        }
    }
}

/// 最近完成行：5 分钟内的完成用 1 秒脉冲提示（减弱动态效果时静态显示）。
private struct RecentCompletionRow: View {
    let item: CompletedTask
    let onReveal: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var isRecent: Bool {
        Date().timeIntervalSince(item.completedAt) < 300
    }

    var body: some View {
        Button(action: onReveal) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.statusSuccess)
                    .opacity(pulsing ? 0.35 : 1)
                Text(item.title).lineLimit(1)
                Spacer(minLength: 0)
                Text(Display.shortDate(item.completedAt))
                    .font(.system(size: DesignTokens.captionFontSize))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.system(size: DesignTokens.captionFontSize))
        .animation(
            reduceMotion || !isRecent
                ? nil
                : .easeInOut(duration: 1).repeatForever(autoreverses: true),
            value: pulsing
        )
        .onAppear {
            if isRecent && !reduceMotion { pulsing = true }
        }
    }
}
