# Logs Directory Reference

The `logs/` directory is the single source of truth for observing a buildteam run. In Docker, set `BUILDTEAM_LOGS_DIR` to a volume-mounted path and everything below lands on the host.

---

## Directory layout

```
logs/
├── run-metadata.json                  # Run configuration (written at startup)
├── events.jsonl                       # Structured event timeline (append-only)
├── milestones.log                     # Milestone boundary records
│
├── orchestrator.log                   # Orchestrator text log
├── bootstrap.log                      # Bootstrap text log
├── planner.log                        # Planner text log
├── builder-1.log                      # Builder 1 text log
├── reviewer-1.log                     # Reviewer 1 text log
├── milestone-reviewer.log             # Milestone reviewer text log
├── tester.log                         # Tester text log
├── validator.log                      # Validator text log
│
├── builder-1.done                     # Builder 1 completion sentinel
├── reviewer-1.branch-checkpoint       # Reviewer 1 last-reviewed SHA
├── reviewer.milestone                 # Milestones the milestone reviewer has processed
├── tester.milestone                   # Milestones the tester has processed
├── validator.milestone                # Milestones the validator has processed
│
├── validation-<milestone>.txt         # Per-milestone validation results (PASS/FAIL lines)
├── analysis-<milestone>.txt           # Per-milestone tree-sitter code analysis
│
├── prompts/                           # Full prompt text for every Copilot call
│   ├── bootstrap-20260227-073521.txt
│   ├── planner-20260227-073522.txt
│   ├── builder-1-20260227-073540.txt
│   └── ...
│
├── builder-1-spawn.log                # (headless only) Raw stdout/stderr from spawned builder-1
├── reviewer-1-spawn.log               # (headless only) Raw stdout/stderr from spawned reviewer-1
├── milestone-reviewer-spawn.log       # (headless only) Raw stdout/stderr from spawned milestone-reviewer
├── tester-spawn.log                   # (headless only) Raw stdout/stderr from spawned tester
├── validator-spawn.log                # (headless only) Raw stdout/stderr from spawned validator
│
├── playwright-<milestone>/            # (optional) Playwright artifacts when --save-traces
│   ├── report/                        #   HTML report
│   └── traces/                        #   Trace files
│
├── docker-output.log                  # (harness only) Raw combined stdout/stderr from tee
└── exit-code                          # (harness only) Container exit code as plain text
```

---

## File reference

### run-metadata.json

Written once by the orchestrator at the start of every `go` command. Contains the run configuration so external tooling can correlate events with parameters without parsing log text.

```json
{
  "project_name": "minimal-python-api-20260227-073521",
  "model": "claude-sonnet-4.6",
  "agent_models": {},
  "num_builders": 1,
  "headless": true,
  "version": "0.11.0.dev (abc1234)",
  "started_at": "2026-02-27T13:35:21.000000+00:00"
}
```

| Field | Description |
|---|---|
| `project_name` | GitHub repo name for the target project |
| `model` | Default Copilot model for all agents |
| `agent_models` | Per-agent model overrides (only non-default entries) |
| `num_builders` | Number of parallel builders launched |
| `headless` | Whether agents ran as background processes |
| `version` | buildteam package version and git hash |
| `started_at` | UTC ISO-8601 timestamp when the run started |

When using the test harness (`run_docker_test.sh`), the harness writes its own version of this file before the container starts, then appends `completed_at` and `exit_code` after the container exits. The orchestrator also writes one inside the container; the harness version includes additional fields (`image`, `timestamp`, `spec_file`).

---

### events.jsonl

Append-only structured event log. Each line is a self-contained JSON object. This is the primary machine-readable record of a run — every significant state transition emits an event here.

Every event has these base fields:

| Field | Type | Description |
|---|---|---|
| `ts` | string | UTC ISO-8601 timestamp |
| `agent` | string | Agent that emitted the event |
| `event` | string | Event name |

Additional fields vary by event. The complete event catalog:

#### Orchestrator events

| Event | Additional fields | When emitted |
|---|---|---|
| `agents_launched` | `num_builders` | After all agent processes are spawned |
| `run_complete` | — | After all builders have written their `.done` sentinels |

#### Bootstrap events

| Event | Additional fields | When emitted |
|---|---|---|
| `bootstrap_started` | `name` | Before the bootstrap Copilot call |
| `bootstrap_completed` | `name`, `success` | After bootstrap finishes (success or failure) |

#### Planner events

| Event | Additional fields | When emitted |
|---|---|---|
| `planning_started` | `mode`, `story_name` | Before the planner Copilot call. `mode` is `"backlog"` for initial planning or `"milestone"` for between-milestone planning. `story_name` is the story being expanded (milestone mode only). |
| `planning_completed` | `mode`, `success` | After planning finishes. Emitted on every exit path (5 distinct failure paths + 1 success path). |

#### Builder events

| Event | Additional fields | When emitted |
|---|---|---|
| `story_claimed` | `story_number`, `story_name` | After successfully claiming a story in BACKLOG.md (push succeeded) |
| `story_completed` | `story_number` | After marking a story `[x]` in BACKLOG.md (push succeeded) |
| `milestone_started` | `milestone`, `builder_id` | Before the builder's Copilot call for a milestone |
| `milestone_completed` | `milestone`, `builder_id` | After the milestone merge to main and tag |
| `build_failed` | `milestone`, `builder_id`, `reason` | When a build fails. `reason` is `"copilot_exit_nonzero"` or `"merge_failed"`. |
| `builder_done` | `builder_id`, (optional) `role` | When the builder writes its `.done` sentinel. `role` is `"issue"` for the issue builder. |

#### Reviewer events

| Event | Additional fields | When emitted |
|---|---|---|
| `review_started` | `branch`, `commit_count` | Before a Copilot review of commits on a feature branch |
| `review_completed` | `branch`, `commit_count`, `exit_code` | After the review Copilot call completes |

#### Milestone reviewer events

| Event | Additional fields | When emitted |
|---|---|---|
| `milestone_review_started` | `milestone` | Before the cross-cutting milestone review |
| `milestone_review_completed` | `milestone` | After the milestone review finishes |

#### Tester events

| Event | Additional fields | When emitted |
|---|---|---|
| `testing_started` | `milestone` | Before the scoped test run |
| `testing_completed` | `milestone`, `exit_code` | After the test Copilot call completes |

#### Validator events

| Event | Additional fields | When emitted |
|---|---|---|
| `validation_started` | `milestone` | Before the container-based validation |
| `validation_completed` | `milestone`, `exit_code`, `total_pass`, `total_fail` | After validation finishes |

#### Copilot call events (all agents)

Every `run_copilot()` invocation emits a pair of events regardless of which agent calls it:

| Event | Additional fields | When emitted |
|---|---|---|
| `copilot_call_started` | `model` | Before each `copilot` CLI invocation |
| `copilot_call_completed` | `model`, `exit_code`, `duration_s` | After each invocation finishes (including timeout retries) |

**Example timeline** (single-builder, one milestone):

```jsonl
{"ts": "2026-02-27T13:35:21Z", "agent": "orchestrator", "event": "agents_launched", "num_builders": 1}
{"ts": "2026-02-27T13:35:22Z", "agent": "builder-1", "event": "story_claimed", "story_number": 1, "story_name": "Scaffolding"}
{"ts": "2026-02-27T13:35:23Z", "agent": "builder-1", "event": "milestone_started", "milestone": "milestone-01", "builder_id": 1}
{"ts": "2026-02-27T13:35:23Z", "agent": "builder-1", "event": "copilot_call_started", "model": "claude-sonnet-4.6"}
{"ts": "2026-02-27T13:38:40Z", "agent": "builder-1", "event": "copilot_call_completed", "model": "claude-sonnet-4.6", "exit_code": 0, "duration_s": 197.2}
{"ts": "2026-02-27T13:38:41Z", "agent": "builder-1", "event": "milestone_completed", "milestone": "milestone-01", "builder_id": 1}
{"ts": "2026-02-27T13:38:42Z", "agent": "builder-1", "event": "story_completed", "story_number": 1}
{"ts": "2026-02-27T13:38:42Z", "agent": "tester", "event": "testing_started", "milestone": "Scaffolding"}
{"ts": "2026-02-27T13:38:42Z", "agent": "validator", "event": "validation_started", "milestone": "Scaffolding"}
{"ts": "2026-02-27T13:40:30Z", "agent": "tester", "event": "testing_completed", "milestone": "Scaffolding", "exit_code": 0}
{"ts": "2026-02-27T13:41:15Z", "agent": "validator", "event": "validation_completed", "milestone": "Scaffolding", "exit_code": 0, "total_pass": 4, "total_fail": 0}
{"ts": "2026-02-27T13:41:20Z", "agent": "builder-1", "event": "builder_done", "builder_id": 1}
{"ts": "2026-02-27T13:41:21Z", "agent": "orchestrator", "event": "run_complete"}
```

---

### milestones.log

Pipe-delimited log of completed milestone boundaries. One line per milestone. Written by the builder after each milestone merges to main.

Format: `name|start_sha|end_sha|label`

```
Scaffolding — project structure, FastAPI app|edca49a0|b1509c7a|milestone-01-scaffolding
Members API — CRUD endpoints|b1509c7a|4f2e8a1b|milestone-02-members-api
```

| Field | Description |
|---|---|
| `name` | Human-readable milestone name (from BACKLOG.md story) |
| `start_sha` | Commit SHA at the start of the milestone (previous milestone's end, or bootstrap commit) |
| `end_sha` | Merge commit SHA on main |
| `label` | Git tag name (e.g. `milestone-01-scaffolding`) used to tag the merge commit |

Other agents poll this file to discover newly completed milestones. The tester, validator, and milestone reviewer each maintain a separate checkpoint file to track which milestones they've already processed.

---

### Agent text logs (`*.log`)

Each agent appends to its own text log file via the `log()` function. These are human-readable logs with timestamps, status messages, and Copilot CLI output (prompts and responses). Every `log()` call also prints to stdout.

| File | Agent | Content |
|---|---|---|
| `orchestrator.log` | Orchestrator | Project detection, agent spawning, completion polling |
| `bootstrap.log` | Bootstrap | Repo creation, SPEC.md generation |
| `planner.log` | Planner | Backlog creation, milestone expansion, quality checks |
| `builder-N.log` | Builder N | Story claims, Copilot build sessions, error details |
| `reviewer-N.log` | Reviewer N | Commit reviews per builder's feature branch |
| `milestone-reviewer.log` | Milestone reviewer | Cross-cutting milestone reviews, code analysis |
| `tester.log` | Tester | Test suite runs, bug filings |
| `validator.log` | Validator | Container builds, endpoint testing, Playwright results |

In headless mode, each agent also has a `<agent>-spawn.log` (e.g. `reviewer-1-spawn.log`) that captures raw stdout/stderr from the spawned background process.

---

### Sentinel and checkpoint files

These are coordination files used by agents to track progress and signal completion. All are plain text.

| File | Format | Purpose |
|---|---|---|
| `builder-N.done` | Single line: datetime | Written by builder N when it has no more stories to claim. All `.done` files must exist for the orchestrator to report `run_complete`. |
| `reviewer-N.branch-checkpoint` | Single line: commit SHA | Last commit SHA reviewed by reviewer N on the builder's feature branch. Persists across branch lifecycle (create → merge → next branch). |
| `reviewer.milestone` | One milestone name per line | Set of milestones the milestone reviewer has already reviewed. Prevents re-reviewing on restart. |
| `tester.milestone` | One milestone name per line | Set of milestones the tester has already tested. |
| `validator.milestone` | One milestone name per line | Set of milestones the validator has already validated. |

---

### validation-\<milestone\>.txt

One file per validated milestone. Contains structured PASS/FAIL lines written by the validator's Copilot session. Copied from the working directory to `logs/` by the Python orchestration after each validation.

Each line starts with `PASS` or `FAIL` followed by a category tag and description:

```
PASS  [A] GET /health -> 200 {"status":"healthy"}
PASS  [A] uvicorn app.main:app starts without errors
FAIL  [B] Members list endpoint returns 404 (expected 200)
PASS  [C] Bug #5 (login crash) no longer reproduces
PASS  [J-1] Create org → invite member → list members journey
FAIL  [UI] Members page does not render table
```

Category tags:

| Tag | Meaning |
|---|---|
| `[A]` | Current milestone validation (endpoints, pages, behaviors from the milestone's `> **Validates:**` block) |
| `[B]` | Requirements coverage (cross-referencing REQUIREMENTS.md against the running app) |
| `[C]` | Fixed bug verification (re-testing recently closed GitHub Issues) |
| `[J-N]` | Journey-based test N (multi-step user flows from JOURNEYS.md) |
| `[UI]` | Playwright browser test |

---

### analysis-\<milestone\>.txt

One file per reviewed milestone. Contains tree-sitter static analysis results produced by the milestone reviewer before its Copilot review call. Checks for long functions, deep nesting, large files, and other structural issues across Python, JS/TS, and C#.

```
Code analysis: Scaffolding — project structure, FastAPI app, health endpoint
========================================

No structural issues detected by static analysis.
```

When issues are found, each is listed with file path, line number, and description.

---

### prompts/

A subdirectory containing the full text of every prompt sent to the Copilot CLI. One file per invocation, named `<agent>-<timestamp>.txt`.

```
prompts/
├── bootstrap-20260227-073521.txt
├── planner-20260227-073522.txt
├── planner-20260227-073525.txt     # completeness check pass
├── planner-20260227-073528.txt     # quality review pass
├── builder-1-20260227-073540.txt
├── reviewer-1-20260227-073610.txt
├── tester-20260227-073640.txt
├── milestone-reviewer-20260227-073641.txt
├── validator-20260227-073642.txt
└── ...
```

These are useful for debugging prompt quality, reproducing agent behavior, and understanding exactly what instructions each agent received. The agent text logs contain the first 100 characters of each prompt as a preview; these files contain the complete text.

---

### playwright-\<milestone\>/ (optional)

Only present when the validator is run with `--save-traces`. Contains Playwright HTML reports and trace files for browser-based UI testing.

```
playwright-milestone-03-frontend/
├── report/      # Playwright HTML report (open index.html in a browser)
└── traces/      # Per-test trace .zip files (open with npx playwright show-trace)
```

---

### docker-output.log (harness only)

Written by the test harness (`run_docker_test.sh`) via `tee`. Contains the raw combined stdout/stderr from the Docker container. This is a superset of what's in `events.jsonl` — it includes human-readable log output, progress bars, and any error messages that don't make it into structured events.

---

### exit-code (harness only)

Written by the test harness after the container exits. Single line containing the numeric exit code (e.g. `0` or `1`). Useful for CI/CD pipelines that need to check run status without parsing logs.

---

## Multiple builders

When running with `--builders N` (N > 1), the logs directory scales horizontally. Each builder and its paired reviewer get their own numbered files.

### Files that multiply

| 1 builder | 3 builders |
|---|---|
| `builder-1.log` | `builder-1.log`, `builder-2.log`, `builder-3.log` |
| `builder-1.done` | `builder-1.done`, `builder-2.done`, `builder-3.done` |
| `reviewer-1.log` | `reviewer-1.log`, `reviewer-2.log` |
| `reviewer-1.branch-checkpoint` | `reviewer-1.branch-checkpoint`, `reviewer-2.branch-checkpoint` |

**Key details for multi-builder runs:**

- **Builders 1 through N-1** are milestone builders that claim and build stories from BACKLOG.md. **Builder N** (the last one) is the dedicated **issue builder** — it only fixes bugs and findings, never claims stories.
- **Reviewers 1 through N-1** each watch their paired milestone builder's feature branch. The issue builder (builder N) does **not** get a reviewer because it works on main, not on feature branches.
- When N=3: builders 1 and 2 build milestones, builder 3 fixes issues; reviewers 1 and 2 review branches; no reviewer-3 exists.
- **`milestones.log`** contains entries from all builders interleaved in completion order (not grouped by builder).
- **`events.jsonl`** contains events from all agents interleaved chronologically. Use the `agent` and `builder_id` fields to filter by builder.
- The **builder_done** event and `.done` sentinel include `builder_id`. The orchestrator waits for **all** `.done` sentinels before emitting `run_complete`.
- Milestone checkpoint files (`reviewer.milestone`, `tester.milestone`, `validator.milestone`) are **shared** — there is one of each regardless of builder count, since these agents process milestones from any builder.
- The **prompts/** directory will contain more files — one set per builder per milestone, plus the shared agents' prompts.

### Files that stay singular (regardless of builder count)

These files always exist as exactly one instance:

- `run-metadata.json`
- `events.jsonl`
- `milestones.log`
- `orchestrator.log`
- `bootstrap.log`
- `planner.log`
- `milestone-reviewer.log`
- `tester.log`
- `validator.log`
- `reviewer.milestone`
- `tester.milestone`
- `validator.milestone`
- `validation-<milestone>.txt` (one per milestone, not per builder)
- `analysis-<milestone>.txt` (one per milestone, not per builder)

---

## Docker volume mapping

In the Docker harness, the mapping is:

```
Host:       $RUN_DIR/logs/     →     Container: /workspace/data/logs/
                                     (via BUILDTEAM_LOGS_DIR=/workspace/data/logs)
```

Everything documented above lands in this single directory. No observability data is written outside of it.
