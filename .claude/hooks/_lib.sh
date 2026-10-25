#!/usr/bin/env bash
# hook 공통 함수. 각 hook이 source 한다.
# 차단·경고 기록은 .claude/state/hook-events.jsonl(gitignore)에 남겨 HARNESS.md 월간 점검에서 집계한다.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_DIR="$PROJECT_DIR/.claude/state"

# stdin JSON을 한 번만 읽어 둔다.
HOOK_INPUT="$(cat)"

input() { jq -r "$1 // empty" <<<"$HOOK_INPUT"; }

hook_log() { # hook_log <hook> <decision> <detail>
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  jq -cn --arg hook "$1" --arg decision "$2" --arg detail "$3" \
    --arg session "$(input .session_id)" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{ts:$ts, session:$session, hook:$hook, decision:$decision, detail:$detail}' \
    >>"$STATE_DIR/hook-events.jsonl" 2>/dev/null || true
}

# 프로젝트 루트 기준 상대 경로로 바꾼다. 루트 밖이면 절대 경로 그대로.
rel_path() {
  local p="$1"
  case "$p" in
    "$PROJECT_DIR"/*) printf '%s' "${p#"$PROJECT_DIR"/}" ;;
    /*) printf '%s' "$p" ;;
    *) printf '%s' "${p#./}" ;;
  esac
}
