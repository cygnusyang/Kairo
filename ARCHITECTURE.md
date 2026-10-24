# Architecture

How Kairo is put together, in the order you would want to learn it: layers, the single
write path, the data model, the derived schedule, and the interface contract. The canonical
and more detailed document is [docs/02-architecture.md](docs/02-architecture.md) (Chinese);
this page is its English counterpart and follows the same decisions.

## 1. Layers

![Kairo layered architecture](docs/architecture-layers.svg)

Four interfaces sit at the top and are deliberately **equal in capability**: the macOS
SwiftUI app, the MCP server, the CLI, and the Claude Code plugin (which is a thin wrapper
over the same MCP/CLI surface). Nothing in one interface may bypass another's semantics.

Below them, two Foundation-only modules:

| Layer | Responsibility | Must not |
|---|---|---|
| `KairoPresentation` | Turns view state into a platform-neutral snapshot plus actions | import SwiftUI, AppKit, Combine |
| `KairoCommands` | `KairoSession` — the single write path shared by UI, MCP and CLI | import any UI framework |
| `KairoCore` | Model, scheduler, violations, queries, layout geometry | import anything platform-bound |

Dependencies point one way only: app → presentation → commands → core. The MCP server and
the CLI depend on `KairoCommands` directly. Two scripts enforce this in CI:
`tools/gate-core.sh` (no platform imports in the three Foundation-only modules) and
`tools/gate-ui.sh` (views must not touch `Project`, `TaskItem` or `KairoSession`).

The macOS app is the only UI shell for now. `KairoCore`, `KairoCommands` and
`KairoPresentation` build and test on Linux, which is what the Linux CI job verifies.

### Where user-facing text lives

Text is not a layer concern; it follows one rule: **only the view layer translates.**

| Layer | Holds natural language? | Notes |
|---|---|---|
| `KairoCore` / `KairoCommands` / `KairoPresentation` | No | errors and violations are codes plus typed parameters; snapshots carry semantic values (`ZoomIndicator`, `ViolationReason`), never sentences |
| macOS views (`Apps/macos`) | Yes — the single translation point | resolves keys from the String Catalog with an English fallback (`I18n.t`) |
| CLI / MCP | Own renderers | no shared string table with the views; MCP reports a stable `code` plus a fine-grained `reason` |

Two consequences worth knowing:

- a snapshot is a public contract consumed by the app, the CLI and MCP; if it carried Chinese
  sentences, the CLI and MCP language policy would be pinned to whatever the UI happens to say;
- `KairoCore`, `KairoCommands` and `KairoPresentation` must not contain `Bundle.module` — there is
  no localisation resource for them to load, and `tools/i18n-lint.sh` (check b) fails the build if
  one appears.

Key grammar, the packaging path (String Catalog compiled to `.lproj` at build time) and the CI
gates: [docs/features/06-localization.md](docs/features/06-localization.md).

## 2. The write path

Every mutation — from a click, a slash command, or an MCP tool call — goes through
`KairoSession`:

```
open .kairo → KairoSession → (read) snapshot / (write) mutate + save → back to caller
```

Consequences that shape the rest of the code:

- The UI never calls `Project.add/update/remove` directly.
- The MCP server and the CLI have no persistence logic of their own; they translate
  arguments and call the same session methods.
- Write methods mark the schedule cache dirty; the next read recomputes once. The UI never
  schedules anything itself.
- The app detects on-disk changes while a session is open and asks the user to reload or
  keep the local version. Hook-driven write-backs from an agent and an open app are not
  merged automatically — see the known limitations in the README.

## 3. The core loop

![Kairo core loop](docs/architecture-dataflow.svg)

The AI reads requirements into a WBS, writes it through MCP/CLI, the core schedules it and
reports violations, the human reviews the Gantt, and the AI writes status back as tasks
land. Kairo never executes work; it keeps the ledger that makes "what is left and when"
answerable.

## 4. Data model

![Kairo project entity relations](docs/architecture-entities.svg)

`Project` aggregates settings, tasks, dependencies, resources, assignments, the work
calendar, baselines, change history and metadata. The parts that carry the semantics:

- **Tasks** are a tree: `task` (leaf), `group`, `milestone`, `hammock`. Only leaves carry
  `effort`; group completion is aggregated from children, weighted by effort.
- **Dependencies** are `TaskDependency` with type `FS / FF / SS / SF` and a lag that can be
  working time, elapsed time, or a percentage.
- **Assignments** connect a task to a resource with a unit count; `assignee` remains as
  a convenient display string (ADR-009).
- **Change history** is append-only: field path, old value, new value, timestamp, source.

## 5. Effort, duration and the schedule

- `effortHours` is the input; duration is derived at 8 hours per person-day, and a leaf
  must have effort. Groups and milestones carry none.
- Dates are **derived**, never stored as truth: change an effort or a dependency and
  `schedule compute` recomputes. `startDate` is a user intent and a lower bound
  ("start no earlier than"), not a promise the scheduler must start the task that day.
- Four constraint kinds (`startNoEarlierThan` and friends) and a policy of `asap` or
  `alap` shape propagation.
- Violations (cycles, out-of-range dates, deadline conflicts) are **reported**, not fixed
  silently: `violations` / `violations_list` return them, the app surfaces them in a banner
  and the inspector.
- The critical path and per-task total/free slack come from `schedule path`.

The scheduler is a pure function over the project graph (ADR-007), which is why the whole
scheduling behaviour is testable without a file or a UI.

## 6. File format and migration

`.kairo` is a single JSON document with a `formatVersion` field (ADR-003, ADR-011):

- Reading **ignores unknown fields** (forward compatible) and rejects a version higher than
  the binary understands.
- Versions are migrated **in order**, one step at a time; a step that does not land on its
  `toVersion` fails the plan.
- Saving always writes the current version.
- Any format change requires a migration step. Rewriting documents without bumping the
  version is not allowed.

## 7. Interface contract

The MCP tool list is the single source of truth; the CLI and the plugin derive from it
(ADR-005), which is what keeps the four doors semantically equal.

- 16 MCP tools: `project_create/open/save`, `task_add/list/get/update/delete`, `wbs_import`,
  `schedule_compute`, `schedule_critical_path`, `violations_list`, `status_update`,
  `status_batch_update`, `resource_add`, `resource_list`.
- The CLI exposes the same operations as subcommands and adds nothing that MCP cannot do.
- IDs accept a full UUID or a unique prefix of four or more characters.
- Exit codes: `0` success, `1` runtime error, `2` usage error.

## 8. Repository layout

![Kairo repository layout](docs/architecture-repo-layout.svg)

```
Sources/KairoCore/          model, scheduler, violations, queries, layout geometry
Sources/KairoCommands/      KairoSession — the only write path
Sources/KairoPresentation/  snapshots, view state, actions
Sources/KairoMCP/           stdio JSON-RPC server
Sources/KairoCLI/           command line
Apps/macos/Sources/         SwiftUI workbench
Plugins/claude-code/        slash commands + TaskCompleted hook
Tests/                      core, presentation, interface parity, app
tools/                      build, package, gates, release, diagram generator
```

## 9. Decisions

| ID | Decision | Status |
|---|---|---|
| ADR-001 | Cross-platform core plus equal interface layers | accepted |
| ADR-002 | Swift for the MVP, Rust evaluated later | accepted |
| ADR-003 | Single-file `.kairo` JSON, local-first, no account, no server | accepted |
| ADR-004 | Core has zero UI dependencies (Foundation subset only) | accepted |
| ADR-005 | MCP tool list is the single source of truth for all interfaces | accepted |
| ADR-006 | Collaboration through file sync plus AI merge, no realtime server | accepted |
| ADR-007 | Scheduler and violation engine separated; scheduling is pure | proposed |
| ADR-008 | Reports are AI-written Markdown, no template engine | accepted |
| ADR-009 | `assignee` migrates to resource assignment, display string kept | accepted |
| ADR-010 | Minimal stdio JSON-RPC implemented in-house, no third-party SDK | accepted |
| ADR-011 | `formatVersion`, forward-compatible read, ordered migration, current on save | accepted |
| ADR-012 | Nested optionals use hand-written `init(from:)`, never synthesised required semantics | accepted |
| ADR-013 | Foundation-only presentation layer; `KairoSession` is the only write path | accepted |

## 10. Non-goals for now

Multi-user realtime collaboration, HTML report templates, drag-to-reschedule and
drag-to-create-dependency, baselines UI and a resource view, and per-project or per-resource
calendars beyond Saturday/Sunday shading. These are registered work, not accidental gaps.
