# agent-pipeline

Seven-agent development pipeline for Claude Code. The main session orchestrates (via the
`pipeline` skill); agents communicate through markdown artifacts in `.pipeline/`.

## Flow

```
user request
   │
   ▼
researcher (opus, read-only) ──► .pipeline/research.md
   │
   ▼
story-writer (sonnet) ─────────► .pipeline/storyboard.md
   │
   ▼  GATE 1: user approves intent + stories
   │
project-manager (inherit) ─────► .pipeline/plan.md   (tasks, scopes, waves)
   │
   ▼  GATE 2: user approves plan · git baseline recorded
   │
engineers (opus, parallel, one git worktree each) ──► pipeline/T* branches
   │                                                  + reports/engineer-T*.md
   ▼
integrator (opus) — merges branches, resolves conflicts,
   │                repairs API breaks, proves build green
   │
   ├─► e2e-tester (opus, adversarial) ──► .pipeline/test-report.md
   └─► validator (opus, adversarial)  ──► .pipeline/validation-report.md
   │
   ▼
pass → done
fail → PM classifies: code defect → replan → new round (max 3)
                      spec defect → story-writer revises → GATE 1 → replan
cap reached → escalate to user (rollback to checkpoint offered, never automatic)
```

## Roles

| Agent | Model | Job | Explicitly NOT its job |
|-------|-------|-----|------------------------|
| researcher | opus | Map the codebase from evidence | Design, planning |
| story-writer | sonnet | User intent → storyboards + acceptance criteria; revises on spec defects | Technical design |
| project-manager | inherit (session) | Feasibility, tasks, waves, failure classification | Implementing, spawning agents |
| engineer | opus | One scoped task in a private worktree, evidence-backed claims | Scope creep, merging |
| integrator | opus | Merge task branches, resolve conflicts, glue API breaks | Re-implementing, redesign |
| e2e-tester | opus | Reproduce claims by running the product | Fixing, intent judgment |
| validator | opus | Intent fidelity vs baseline diff, scope creep | Functional testing |

## Install

As a plugin: add this directory to a marketplace and `/plugin install agent-pipeline`.
Standalone: symlink `agents/*.md` into `~/.claude/agents/` and `skills/pipeline` into
`~/.claude/skills/`.

## With ideamine

The [ideamine](https://github.com/equwal/ideamine) plugin is an idea inbox; `/ideas-pipeline [id]`
(or `ideamine go <id> --pipeline` in a terminal) sends one idea through this pipeline. The
request then ends with `ideamine idea id: <N>`, and the orchestrator adds a note to that idea
after each phase (`pipeline: research done`, `pipeline: plan approved`, `pipeline: wave 1
integrated`, ...), marks it done when the tester and the validator pass, and leaves it in
`doing` with a note when the iteration cap is reached. The ideamine dashboard shows the latest
note on the ticket, so the state of every run is visible in one place.

## Use

In any project: `/pipeline <feature request>` — or ask to run the request "through the
pipeline". Parallel engineering and rollback need the target to be a git repo; without
one, engineers run sequentially in place.
