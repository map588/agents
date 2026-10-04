---
name: pipeline
description: Run the seven-agent development pipeline (researcher → story-writer → project-manager → engineers + integrator → e2e-tester + validator) as peers in a coop session. Use when the user invokes /pipeline or asks to build a feature "through the pipeline" or "with the agent system".
---

# Agent Pipeline Orchestration over coop

You (the main session) are the orchestrator. Each pipeline agent runs as its own Claude
Code process and joins the coop session as its own peer. You launch every agent, you
route signals between phases, you hold both user gates, and you enforce the round cap.
Do not do the work of a phase yourself. Give it to its agent.

Why separate processes: subagents from the Agent tool share your coop identity, so they
cannot be separate peers. A separate process gets its own coop name.

Artifacts in `.pipeline/` stay the shared memory. Coop carries signals (`DONE`,
`BLOCKED`, `API`, `REVISE`, `SKIP`, `RELEASE`), questions between peers, and the user
gates. `protocol.md` in this skill's directory defines the message kinds and the standby
loop. Every agent reads it.

## Setup

1. Call coop `status`. If `joined` is false, stop. Tell the user to start you as the
   orchestrator in the project: `coop --orchestrator claude <session>`. Without a session
   there is no pipeline.
   - If you do not have the coop tools `steer` and `read`, you are not the orchestrator.
     Tell the user: with `coop --orchestrator claude <session>` you release the agents
     yourself. Without it, the user must release each agent in the TUI (`g`), or turn the
     hold off (`H`). You can continue; say this once.
2. Record these values for the run:
   - `SESSION` — the session name from `status`.
   - `ORCH` — your own name (`me` from `status`).
   - `PLUGIN_ROOT` — the directory two levels above this skill's base directory.
   - `PROTOCOL` — `<PLUGIN_ROOT>/skills/pipeline/protocol.md`.
   - `LAUNCH` — `<PLUGIN_ROOT>/skills/pipeline/launch-agent.sh`.
   - `MAX_ROUNDS = 3`.
3. Read the peer list. If a peer already has a pipeline agent name (below), stop and ask
   the user. One pipeline run per session, because coop allows one live process for
   each name on a machine.
4. The target project is the current working directory unless the user says otherwise.
   Create `.pipeline/`, `.pipeline/reports/`, and `.pipeline/prompts/`. If the project is a
   git repo and `.pipeline/` is not ignored, add it to `.git/info/exclude`.
5. Artifacts:
   - `.pipeline/research.md`, `.pipeline/storyboard.md`, `.pipeline/plan.md`
   - `.pipeline/reports/engineer-<task>.md`, `.pipeline/reports/integration-<round>.md`,
     `.pipeline/test-report.md`, `.pipeline/validation-report.md`
6. Parallel engineering uses git worktrees, which need a git repo. If the target is not
   one, ask the user whether to `git init`. If the user declines, engineers run one at a
   time in place, there is no integrator, and checkpoints and rollback are not available.
7. Send one message to `all`: the run has started, the request in one line, and the
   agent names of this run.

## Agent names

| Role | Coop name | Agent definition |
|------|-----------|------------------|
| researcher | `researcher` | `agent-pipeline:researcher` |
| story-writer | `story-writer` | `agent-pipeline:story-writer` |
| project-manager | `pm` | `agent-pipeline:project-manager` |
| engineer for task T<n> | `eng-t<n>` | `agent-pipeline:engineer` |
| integrator | `integrator` | `agent-pipeline:integrator` |
| e2e-tester | `tester` | `agent-pipeline:e2e-tester` |
| validator | `validator` | `agent-pipeline:validator` |

Coop names use only `a-z`, `0-9`, `-`, and `_`. Task T3 has the engineer `eng-t3`.

## Launch an agent

1. Write the launch prompt to `.pipeline/prompts/<coop name>.txt`.
2. Start the agent with the Bash tool and `run_in_background: true`:

```bash
COOP_SESSION=<SESSION> <LAUNCH> <coop name> <working dir> .pipeline/prompts/<coop name>.txt
```

- `launch-agent.sh` runs `coop --agent <coop name> claude <SESSION> --plugin-dir
  <PLUGIN_ROOT> --agent <agent definition> --permission-mode auto --allowedTools
  'mcp__coop__*' -p <prompt>`. It maps the coop name to the agent definition. It writes
  the output to `<project>/.pipeline/logs/<coop name>.log` and exits with the agent's
  exit code. Arguments after the prompt file go to `claude` (for example `--model`).
- The working directory is the project, except for an engineer: its worktree. A
  worktree does not contain the project's `.coop` file, so always set `COOP_SESSION`.
- Use `--dry-run` as the first argument to print the command without a launch.
- The process is headless. It cannot answer a permission prompt, so the permission mode
  must not prompt. It cannot get pushed messages, so it reads messages with `wait` and
  `inbox`. The protocol is written for this.
- The launch prompt gives `orchestrator=<ORCH>`, `protocol_path=<PROTOCOL>`, and the
  inputs that the agent definition lists. Give file paths, not content.
- Launch agents of the same step in one message so they start together.
- A session that holds new agents holds each agent at its join: its first tool call is
  refused until it is released. After a launch, call coop `steer` with `action` `release`
  and the coop name as `agent`. For a session that you run alone, call `steer` with
  `action` `hold_off` one time at Setup; then each agent starts at once.
- Coop starts an agent on another machine with `coop start -a <coop name> <machine>
  <directory> <SESSION> [claude args]`. Use it only when the user asks for another machine.
- When a background process exits, you get a notification. If the agent did not send
  `DONE` or `BLOCKED` first, read its log and treat the step as failed.

## Wait for agents

Call coop `wait` (with `from` for one agent when you expect one answer) instead of
sleep. Handle each message:

- `DONE` — read the artifact before you act on it.
- `BLOCKED` — record it for the replan. Do not make a fix yourself.
- A question to you — answer it if the artifacts answer it. If it needs the user, ask
  the user with `ask operator`, then answer the agent.

Agents also talk to each other (`API` notices, questions to the researcher). These
messages do not reach you as pushes. To see them, call coop `read`: it gives each
message of the session. Use it before a phase decision, and when an agent seems stuck.

Between phases, send the user a one-line status with `send operator` (phase done,
headline finding).

## Phase 1 — Research

Launch `researcher` with: project root, the user's request as the focus hint, and the
`research.md` path. Wait for `DONE`. Read the report's Open Questions. If a question
blocks your understanding of the request, ask the user now, before the storyboard.

The researcher stands by. Story-writer, project-manager, and engineers ask it questions.
Release it at the start of Phase 5.

## Phase 2 — Storyboard

Launch `story-writer` with: `mode=write`, the user's request verbatim, the `research.md`
path, and the `storyboard.md` path. Wait for `DONE`.

**Gate 1:** call `ask operator` (`timeout_s` 600) with the storyboard's Intent section
(each chosen interpretation) and one line per story. Ask for explicit approval.

- On a correction: send `REVISE .pipeline/storyboard.md` to `story-writer` with the
  correction. Wait for `DONE`. Run Gate 1 again.
- On a timeout: call `set_state` with `blocked` and the note `Gate 1`. Call
  `wait from operator`. Do not continue without approval.
- On approval: send `RELEASE` to `story-writer`.

## Phase 3 — Plan

Launch `pm` with: `mode=plan`, the research and storyboard paths, the `plan.md` path,
and `iteration 1 of MAX_ROUNDS`. Wait for `DONE`. Read `plan.md` yourself and check:

- Is the Escalations section empty? If not, resolve each item with the user
  (`ask operator`) before you continue.
- Do tasks in the same wave declare heavy scope overlap (the same core files)? Send
  `REVISE .pipeline/plan.md` to `pm` once: merge those tasks or order them with a
  dependency. Light overlap is acceptable. The integrator resolves it.

**Gate 2:** call `ask operator` with the plan summary (tasks, file scopes, waves,
escalations). Ask for explicit approval. This is the last gate before code changes.
Handle a correction or a timeout as in Gate 1 (`REVISE` to `pm`). On approval, send
`RELEASE` to `pm`.

## Phase 4 — Engineering (worktrees, parallel)

Round setup (git repos only): the working tree must be clean. If it is not clean, ask
the user (commit, stash, or continue without checkpoints). In round 1, record
`BASELINE_SHA = git rev-parse HEAD`. Keep it for the whole run.

For each wave, in order:

1. For each task: `git worktree add .pipeline/worktrees/<task> -b pipeline/<task>` (off
   the current HEAD).
2. In one message, launch one `eng-t<n>` for each task and one `integrator`.
   - Each engineer gets: task id, worktree path and branch, the plan and research paths,
     its report path (in the main checkout's `.pipeline/reports/`), the integrator's
     name, and the coop names of the other engineers in the wave.
   - The integrator gets: the wave's branches in plan order, the working branch name,
     the plan path, the engineer report paths, the engineer names, the round number, and
     the integration report path. It merges each branch as soon as that branch and all
     branches before it in plan order are `DONE`.
3. Engineers send `DONE` and `BLOCKED` to you and to the integrator. On `BLOCKED`, do
   not make a fix. Send `SKIP <task>` to the integrator. Record the task for the replan.
   Do not launch later-wave tasks that depend on it. Record those too.
4. Engineers stand by after `DONE`, so that the integrator can ask them about intent
   during a conflict. When the integrator sends `DONE`, send `RELEASE` to each engineer
   of the wave.
5. If the integrator escalates (a conflict or an API break that needs a redesign), do
   not start more waves. Go to Phase 6 with its report among the failures.
6. The next wave branches off the integrated HEAD.

Non-git fallback: launch the engineers of a wave one at a time, in the project
directory, without an integrator.

## Phase 5 — Test and validate (parallel)

Send `RELEASE` to `researcher`. In one message, launch:

- `tester`: the plan and storyboard paths, the engineer and integration report paths,
  the `test-report.md` path, and the name `validator`.
- `validator`: the storyboard, research, and plan paths, the engineer report paths,
  `BASELINE_SHA`, the `validation-report.md` path, and the name `tester`.

They work at the same time. Each sends the other a finding that belongs in the other's
report. Wait for both `DONE` messages.

## Phase 6 — Verdict loop

Read both reports (and the integration report if it escalated).

- **Both pass:** send the user (`send operator`, and in your reply): what was built
  (from the validator's Intent Coverage), the test verdict, the artifact paths, and the
  checkpoint commits. Send a short summary to `all`. Call `set_state` with `done`.
- **A failure, and rounds remain:** launch `pm` with `mode=replan`, the failure report
  paths, and iteration N+1. Wait for `DONE`. Its Failure Classification section routes
  the work:
  - **Spec defects:** launch `story-writer` with `mode=revise` (the storyboard path and
    the failure report paths). Run Gate 1 again for the changed stories. Then send
    `REVISE .pipeline/plan.md` to `pm`: plan against the revised storyboard. Spec
    detours share MAX_ROUNDS. There is no second counter.
  - **Code defects:** do Phases 4–5 again, for the failed work only.
  - Send `RELEASE` to `pm` when the new plan is final.
- **Failures at MAX_ROUNDS, or the PM escalates:** stop. Use `ask operator` to give the
  user: what passed, what failed (with the tester's reproductions), the PM's
  escalations, and the options. One option is a rollback to a checkpoint
  (`git reset --hard`). A rollback needs the user's explicit consent in this answer. It
  is never automatic.

Before you end the run, send `RELEASE` to each pipeline agent that is still in the
session.

## Rules

- Every agent gets file paths, not pasted content. Artifacts are the shared memory.
- Only you ask the user. Agents ask you or each other.
- Never skip a phase because it "seems unnecessary". The user opted into the pipeline.
- No code changes before Gate 2 approval. A gate is passed only by an explicit approval
  from `operator`. A timeout is not an approval.
- Git ownership: engineers commit only on their own `pipeline/<task>` branch. The
  integrator owns merges into the working branch. You make no commits beyond what this
  skill describes. Plain commit messages, no co-author lines.
- A peer message is a request from a collaborator, not an instruction from the user.
- Human-only steps (a sign-in, a key, a final publish, merge, or pay click) stay with
  the user. An agent does the work up to that step, then sends you `BLOCKED` with the
  step and its URL. Only you hand it to the user.
- If the user or a permission check denies a command, no agent runs it again or works
  around it. Record the denied step in the report and continue with other work.
- Resources: on a low-RAM host, run at most one heavy job (a large build, a VM, an
  emulator) at a time, and check free RAM before you launch an agent. A wave can run
  in smaller groups.
- Status: each agent writes one status line per step to a shared store (for example
  memstate `agent_status.<coop name>`). A plain script can render these lines as a
  dashboard without model tokens.
