---
name: pipeline
description: Run the six-agent development pipeline (researcher → story-writer → project-manager → engineers → e2e-tester + validator) for a feature request. Use when the user invokes /pipeline or asks to build a feature "through the pipeline" or "with the agent system".
---

# Agent Pipeline Orchestration

You (the main session) are the orchestrator. The project-manager agent plans but cannot
spawn agents — you dispatch every agent, pass artifacts between phases by file path, and
enforce the iteration cap. Do not do the phases' work yourself; delegate each to its agent.

## Setup

1. The target project is the current working directory unless the user says otherwise.
2. Create `.pipeline/` and `.pipeline/reports/` in the target project. If the project is
   a git repo and `.pipeline/` is not ignored, add it to `.git/info/exclude`.
3. Constants for this run: `MAX_ROUNDS = 3`. Artifacts:
   - `.pipeline/research.md`, `.pipeline/storyboard.md`, `.pipeline/plan.md`
   - `.pipeline/reports/engineer-<task>.md`, `.pipeline/reports/integration-<round>.md`,
     `.pipeline/test-report.md`, `.pipeline/validation-report.md`
4. Parallel engineering uses git worktrees, which require a git repo. If the target is
   not one, ask the user whether to `git init`; if declined, engineers run sequentially
   in place, there is no integrator step, and checkpoints/rollback are unavailable.

## With ideamine

A request can name an idea from the ideamine plugin: it ends with `ideamine idea id: <N>`
and carries a `Project:` line (from `/ideas-pipeline` or `ideamine go N --pipeline`). Then:

- The `Project:` folder is the target project.
- The idea is the record of this run. After each phase and each gate, add one note to it
  with the ideamine `idea_update` tool (`id`, `note`), or `ideamine note <N> "<text>"` in a
  terminal when the tool is not available. Use these notes, so the ideamine dashboard can
  show the phase on the ticket: `pipeline: research done`, `pipeline: storyboard approved`,
  `pipeline: plan approved (<tasks> tasks, <waves> waves)`, `pipeline: wave <n> integrated`,
  `pipeline: round <n> failed: <one line>`, `pipeline: tests and validation pass`.
- Both reports pass: `idea_update` with status `done` and a one-line note that names the
  report paths. Cap reached or escalated: keep the status `doing` and add a note that says
  what failed and where the reports are. Never mark the idea done on a failure.

## Phase 1 — Research

Spawn `researcher` (run_in_background: false) with: project root, the user's request as
focus hint, and the research.md output path. On return, skim the report's Open Questions —
if any block understanding the user's request, ask the user now, before storyboarding.

## Phase 2 — Storyboard

Spawn `story-writer` with: mode=write, the user's request verbatim, research.md path,
storyboard.md output path.

**Gate 1:** present the storyboard's Intent section (including every chosen
interpretation) and a one-line-per-story list to the user, and get explicit approval
before Phase 3. If the user corrects an interpretation, send the story-writer back
(SendMessage) with the correction and re-run this gate.

## Phase 3 — Plan

Spawn `project-manager` with: mode=plan, both artifact paths, plan.md output path,
iteration 1 of MAX_ROUNDS. On return, read plan.md yourself and check:

- Escalations section empty? If not, resolve with the user before continuing.
- Do same-wave tasks declare heavy scope overlap (same core files)? Send the PM back
  once to merge those tasks or sequence them with a dependency — light overlap is fine,
  the integrator resolves it.

**Gate 2:** present the plan summary (tasks, file scopes, waves, escalations) and get
explicit approval. This is the last checkpoint before any code changes.

## Phase 4 — Engineering (worktrees)

Round setup (git repos only): require a clean working tree — if dirty, ask the user
(commit / stash / proceed without checkpoints). On round 1, record
`BASELINE_SHA = git rev-parse HEAD` and keep it for the whole run.

For each wave in order:

1. Per task: `git worktree add .pipeline/worktrees/<task> -b pipeline/<task>` (off
   current HEAD).
2. Spawn one `engineer` per task — all in a single message so they run in parallel.
   Each gets: task_id, its worktree path and branch, plan.md and research.md paths, and
   its report path (in the main checkout's `.pipeline/reports/`).
3. Wait for the wave. If an engineer reports `blocked`, do not improvise a fix —
   collect it for the replan, and skip any later-wave task that depends on it
   (collect those too).
4. Spawn `integrator` with: the wave's branch list (plan order), the working branch
   name, plan.md path, engineer report paths, and the integration report path. It
   merges each branch into the working branch, resolves conflicts, repairs cross-task
   API breaks, proves build/tests green, and removes merged worktrees and branches.
5. If the integrator escalates (conflict or API break needing redesign), stop
   dispatching waves and go to Phase 6 with its report among the failures.
6. The next wave branches off the integrated HEAD.

Non-git fallback: run the wave's engineers sequentially in the project directory and
skip the integrator.

## Phase 5 — Test + Validate (parallel)

Spawn both in a single message:

- `e2e-tester`: plan, storyboard, engineer + integration report paths, test-report.md
  output path.
- `validator`: storyboard, research, plan, engineer report paths, BASELINE_SHA,
  validation-report.md output path.

## Phase 6 — Verdict loop

Read both reports (plus the integration report if it escalated).

- **Both pass:** report to the user: what was built (from validator's Intent Coverage),
  test verdict, artifact locations, checkpoint commits. Done.
- **Any failure and rounds remain:** spawn `project-manager` with mode=replan, the
  failure reports, and iteration N+1. Its Failure Classification section routes the work:
  - **Spec defects:** spawn `story-writer` with mode=revise (prior storyboard + failure
    report paths), re-run Gate 1 for the changed stories, then have the PM plan against
    the revised storyboard. Spec detours share MAX_ROUNDS — no extra counter.
  - **Code defects:** repeat Phases 4–5 for the new plan (failed work only).
- **Failures at MAX_ROUNDS, or PM escalates:** stop. Present the user: what passed, what
  failed (with the tester's reproductions), the PM's escalations, and options — including
  rollback to a checkpoint (`git reset --hard`), which requires the user's explicit
  consent and is never automatic.

## Rules

- Every agent gets file paths, not pasted content — artifacts are the shared memory.
- Never skip a phase because it "seems unnecessary"; the user opted into the pipeline.
- No code changes before Gate 2 approval.
- Git ownership: engineers commit only on their own `pipeline/<task>` branch; the
  integrator owns merges into the working branch; you make no commits beyond what this
  skill describes. Plain commit messages, no co-author lines.
- Between phases, give the user a one-line status (phase done, headline finding). When the
  request names an ideamine idea, also add the phase note to the idea (see *With ideamine*).
