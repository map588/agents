# agent-pipeline

Seven-agent development pipeline for Claude Code over coop.
The main session orchestrates (via the `pipeline` skill). Each agent runs as its own
headless Claude Code process and joins the coop session as its own peer. Agents write
markdown artifacts in `.pipeline/`. They send signals (`DONE`, `BLOCKED`, `API`, `REVISE`,
`SKIP`, `RELEASE`) and questions to each other through coop. `skills/pipeline/protocol.md`
defines the messages and the standby loop. The orchestrator is the only peer that asks
the user: both gates are coop questions to `operator`.

## Flow

```
user request
   │
   ▼
researcher (opus, read-only) ──► .pipeline/research.md
   │   (stands by: answers codebase questions until Phase 5)
   ▼
story-writer (sonnet) ─────────► .pipeline/storyboard.md
   │
   ▼  GATE 1: ask operator — user approves intent + stories (REVISE on correction)
   │
project-manager (inherit) ─────► .pipeline/plan.md   (tasks, scopes, waves)
   │
   ▼  GATE 2: ask operator — user approves plan · git baseline recorded
   │
engineers (opus, parallel, one git worktree each) ──► pipeline/T* branches
   │   send API notices to wave peers                 + reports/engineer-T*.md
   │   stand by for integrator questions
integrator (opus, starts with the wave) — merges each branch on DONE in plan order,
   │                resolves conflicts, repairs API breaks, proves build green
   │
   ├─► e2e-tester (opus, adversarial) ──► .pipeline/test-report.md
   └─► validator (opus, adversarial)  ──► .pipeline/validation-report.md
         (parallel; each sends the other findings that belong in its report)
   │
   ▼
pass → done
fail → PM classifies: code defect → replan → new round (max 3)
                      spec defect → story-writer revises → GATE 1 → replan
cap reached → ask operator (rollback to checkpoint offered, never automatic)
```

## Roles

| Agent | Model | Job | Explicitly NOT its job |
|-------|-------|-----|------------------------|
| researcher | opus | Map the codebase from evidence | Design, planning |
| story-writer | sonnet | User intent → storyboards + acceptance criteria; revises on spec defects | Technical design |
| project-manager | inherit (session) | Feasibility, tasks, waves, failure classification | Implementing, launching agents |
| engineer | opus | One scoped task in a private worktree, evidence-backed claims | Scope creep, merging |
| integrator | opus | Merge task branches, resolve conflicts, glue API breaks | Re-implementing, redesign |
| e2e-tester | opus | Reproduce claims by running the product | Fixing, intent judgment |
| validator | opus | Intent fidelity vs baseline diff, scope creep | Functional testing |

## Install

As a plugin: add this directory to a marketplace and `/plugin install agent-pipeline`.
Standalone: symlink `agents/*.md` into `~/.claude/agents/` and `skills/pipeline` into
`~/.claude/skills/`.

## Use

Needs a coop session. In the project: `coop session <name>`, then `coop claude`. In that
session: `/pipeline <feature request>` — or ask to run the request "through the pipeline".
The orchestrator starts each agent with `claude --agent agent-pipeline:<role> -p` and
`--permission-mode auto`, because a headless agent cannot answer a permission prompt.
One pipeline run per coop session: coop allows one live process for each agent name. Parallel engineering and rollback need the target to be a git repo; without
one, engineers run sequentially in place.
