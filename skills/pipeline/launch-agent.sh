#!/usr/bin/env bash
# launch-agent.sh - start one agent-pipeline role as a headless Claude Code
# session in the coop session, via `coop --agent <name> claude`.
#
# usage: launch-agent.sh [--dry-run] <coop-name> <workdir> <prompt-file> [extra claude args...]
#
#   coop-name    researcher | story-writer | pm | eng-t<n> | integrator | tester | validator
#   workdir      directory the agent runs in (eng-t<n>: .pipeline/worktrees/T<n>)
#   prompt-file  launch prompt (key=value lines), passed to claude -p
#   extra args   passed to claude as-is (e.g. --model sonnet)
#
# env:
#   PIPELINE_PLUGIN_ROOT   plugin root (default: two levels above this script)
#   COOP_SESSION           session name (default: COOP_SESSION= line in <project>/.coop)
#   PIPELINE_PROJECT_ROOT  project main checkout (default: from git, else workdir)
#
# Runs in the foreground; exits with claude's exit code. Output goes to
# <project>/.pipeline/logs/<coop-name>.log.
#
# Written for bash 3.2 (macOS) and later.

set -euo pipefail

die() { printf 'launch-agent: %s\n' "$*" >&2; exit 2; }

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then dry_run=1; shift; fi

[ $# -ge 3 ] || die "usage: launch-agent.sh [--dry-run] <coop-name> <workdir> <prompt-file> [extra claude args...]"
name=$1 workdir=$2 prompt_file=$3
shift 3

case $name in
  researcher|story-writer|integrator|validator) definition=$name ;;
  pm) definition="project-manager" ;;
  tester) definition="e2e-tester" ;;
  eng-t[0-9]*)
    case ${name#eng-t} in *[!0-9]*) die "bad engineer name: $name (want eng-t<n>)" ;; esac
    definition=engineer ;;
  *) die "unknown role: $name (want researcher, story-writer, pm, eng-t<n>, integrator, tester, validator)" ;;
esac

command -v coop >/dev/null 2>&1 || die "coop not on PATH"
[ -d "$workdir" ] || die "workdir not found: $workdir"
[ -f "$prompt_file" ] || die "prompt file not found: $prompt_file"
[ -s "$prompt_file" ] || die "prompt file is empty: $prompt_file"

workdir=$(cd "$workdir" && pwd -P)
prompt_file=$(cd "$(dirname "$prompt_file")" && pwd -P)/$(basename "$prompt_file")

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
plugin_root=${PIPELINE_PLUGIN_ROOT:-$(cd "$script_dir/../.." && pwd -P)}
[ -f "$plugin_root/agents/$definition.md" ] || die "agent definition not found: $plugin_root/agents/$definition.md (set PIPELINE_PLUGIN_ROOT)"

# Project main checkout: the parent of the shared .git dir, so a worktree
# under .pipeline/worktrees/ resolves to the main checkout.
project=${PIPELINE_PROJECT_ROOT:-}
if [ -z "$project" ]; then
  if common=$(git -C "$workdir" rev-parse --git-common-dir 2>/dev/null); then
    case $common in /*) ;; *) common=$workdir/$common ;; esac
    project=$(cd "$common/.." && pwd -P)
  else
    project=$workdir
  fi
fi

session=${COOP_SESSION:-}
if [ -z "$session" ] && [ -f "$project/.coop" ]; then
  session=$(sed -n 's/^COOP_SESSION=//p' "$project/.coop" | head -n 1 | tr -d '"'"'"'\r')
fi
[ -n "$session" ] || die "no session: set COOP_SESSION or run 'coop session <name>' in $project"

log_dir=$project/.pipeline/logs
log=$log_dir/$name.log

cmd=(coop --agent "$name" claude "$session"
  --plugin-dir "$plugin_root"
  --agent "agent-pipeline:$definition"
  --permission-mode bypassPermissions
  --allowedTools 'mcp__coop__*'
  "$@"
  -p "$(cat "$prompt_file")")

if [ "$dry_run" = 1 ]; then
  printf 'cd %q\n' "$workdir"
  printf '%q ' "${cmd[@]}"
  printf '</dev/null >>%q 2>&1\n' "$log"
  exit 0
fi

mkdir -p "$log_dir"
printf '=== %s start %s session=%s workdir=%s\n' \
  "$name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$session" "$workdir" >>"$log"

cd "$workdir"
set +e
"${cmd[@]}" </dev/null >>"$log" 2>&1
status=$?
set -e

printf '=== %s exit %d %s\n' "$name" "$status" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$log"
exit "$status"
