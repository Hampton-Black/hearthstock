# CLAUDE.md

Personal, local-first iPhone app for tracking emergency-preparedness supplies (food, water, power, gear, go-bags) and estimating how long they last ("runway") per site.

- **Spec (source of truth for behavior):** `docs/spec.md`
- **Work tracking:** Beads (`bd`). Each slice is an epic; each task is a child bead with acceptance criteria in its description. See "Task tracking" below.
- The app is **Hearthstock**. Modules: `HearthstockKit` (Swift package) containing `HearthstockCore` and `HearthstockStore`. The name may still change, so keep it out of user-facing strings beyond the app display name.

If the spec and a bead disagree, stop and ask. If the spec is silent, pick the simplest option, note it in your summary, and keep going.

## Stack

- Swift 6 (language mode 6, strict concurrency), SwiftUI, iOS 18.0 minimum, **iPhone only**
- Persistence: SQLite via **GRDB 7** (no SwiftData, no Core Data)
- Tests: **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest, except where UI tests require it later
- Project generation: **XcodeGen** (`project.yml`)
- No other third-party dependencies without asking first.

## Layout

```
.
├── CLAUDE.md
├── project.yml                  # XcodeGen manifest (committed)
├── Hearthstock.xcodeproj/           # GENERATED — gitignored, never edit
├── App/                         # SwiftUI app target: screens, view models, app entry
├── Packages/HearthstockKit/
│   ├── Package.swift
│   ├── Sources/HearthstockCore/        # pure domain: types, units, shelf life, runway math
│   ├── Sources/HearthstockStore/       # GRDB schema, migrations, repository implementations
│   ├── Tests/HearthstockCoreTests/
│   └── Tests/HearthstockStoreTests/
└── docs/
    └── spec.md
.beads/                          # Beads database (managed by bd — never edit by hand)
```

## Commands

| Task | Command |
| --- | --- |
| Domain + store tests (run constantly) | `cd Packages/HearthstockKit && swift test` |
| Single test | `swift test --filter <TestNameOrSuite>` |
| Regenerate Xcode project (after adding/removing files or editing project.yml) | `xcodegen generate` |
| Build the app | `xcodebuild -project Hearthstock.xcodeproj -scheme Hearthstock -destination 'platform=iOS Simulator,name=<device>' build` |
| List simulators | `xcrun simctl list devices available` |

`Package.swift` declares both `.iOS(.v18)` and `.macOS(.v15)` so `swift test` runs natively on the Mac without a simulator. Keep it that way.

## Architecture rules

1. **HearthstockCore is pure.** It imports only `Foundation`. No GRDB, no SwiftUI, no UIKit, no network. Everything in it is unit-testable without a database.
2. **Domain types are value types.** Structs and enums, `Sendable`, `Hashable`/`Codable` where useful. Typed IDs (`struct LotID: Hashable, Sendable, Codable { let rawValue: UUID }`), never bare `UUID` or `String` in signatures.
3. **Repository protocols live in HearthstockCore; implementations live in HearthstockStore.** The app talks to protocols. Swapping storage must only touch HearthstockStore.
4. **Derived values are never stored.** Calories, servings, gallons, Wh, runway, shelf-life state — all computed from lots, products and the evaluation date. Only facts are persisted.
5. **Quantities live on lots in the product's base unit** (lb, gal, Wh, count). Conversion happens at entry. See `docs/spec.md` → Data model → Units.
6. **Calendar dates are not timestamps.** Printed/expiry/acquired dates are a `CalendarDate` (year, month, day) value type, stored as ISO `YYYY-MM-DD` text. Never use `Date` for these — timezone shifts will move expiry by a day. Every function that depends on "today" takes the date as a parameter; nothing in HearthstockCore calls `Date()` directly.
7. **Every runway is scoped to a site.** No query or calculation aggregates across sites. Sites exist in the schema from day one, even while the UI shows one.
8. **Concurrency:** HearthstockCore is synchronous and `Sendable`. HearthstockStore exposes repositories that are `Sendable` (GRDB's `DatabaseQueue`/`DatabasePool` is thread-safe). View models are `@MainActor @Observable`. Don't silence concurrency diagnostics with `@unchecked Sendable` or `nonisolated(unsafe)` without asking.
9. **Defaults are data, not code paths.** Shelf-life tables, climate multipliers, kit and readiness templates ship as bundled data that the user can edit later. Defaults must be conservative.

## Persistence rules (HearthstockStore)

- Migrations use GRDB's `DatabaseMigrator`, named `v1_...`, `v2_...`, append-only.
- Once a migration has run on a real device, never edit it — add a new one. Until then (pre-release), say so explicitly before editing an existing migration.
- Store tests use an in-memory `DatabaseQueue()` and run the full migrator.
- Foreign keys on. Every lot, location, person, power load and readiness template has a `siteId`.

## Testing

- Write tests first for anything in HearthstockCore. Table-driven tests (`@Test(arguments:)`) for unit conversion, shelf-life states and runway math.
- Numeric comparisons on `Double` use a tolerance helper; don't compare floats with `==`.
- Fixtures go in `Tests/HearthstockCoreTests/Fixtures/`. A realistic pantry fixture is the main regression test for runway math — keep it passing and extend it rather than replacing it.
- `swift test` must be green before you say a task is done. Report the test count in your summary.

## Project file

- Never edit `Hearthstock.xcodeproj` or any `.pbxproj` by hand. Change `project.yml` and run `xcodegen generate`.
- Info.plist keys go in `project.yml` via `INFOPLIST_KEY_*` build settings (`GENERATE_INFOPLIST_FILE: YES`).

## Task tracking (Beads)

- Start a session with `bd prime`, then `bd ready` to see unblocked work.
- Claim before starting: `bd update <id> --claim`. Read the bead with `bd show <id>` — its description holds the acceptance criteria.
- Close when its criteria are met and `swift test` is green: `bd close <id> "<one-line summary, test count>"`.
- Work you discover but shouldn't do now becomes a new bead (`bd create "…" -p <0-4>`), linked to its epic with `bd dep add`. Don't expand the current bead's scope.
- Never track tasks in markdown TODO lists or in this file.
- Durable conventions belong in this file; `bd remember` is for project facts learned along the way (e.g. "GRDB 7 needs X for Y").
- Reference the bead ID in commit messages: `HearthstockCore: shelf-life evaluator (bd-a3f8.5)`.

## Working style

- Use plan mode at the start of each epic: read its beads and the relevant spec sections, propose the types and file layout, wait for approval, then build.
- Small, focused commits with descriptive messages; one bead per commit where practical.
- UI work: you can build it, but you can't see the simulator. After UI changes, tell me exactly what to tap and what I should see, and wait for my report.
- When a domain question isn't answered by the spec (a default value, an edge case), choose the conservative option and list it under "Assumptions" in your summary.
- End each task with: what changed, test count, assumptions made, anything I need to check by hand.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:46cd31e7 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   bd dolt push
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
