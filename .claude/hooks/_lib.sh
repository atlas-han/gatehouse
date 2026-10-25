#!/usr/bin/env bash
# hook 공통 함수. 각 hook이 source 한다.
# 차단·경고 기록은 .claude/state/hook-events.jsonl(gitignore)에 남겨 HARNESS.md 월간 점검에서 집계한다.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
STATE_DIR="$PROJECT_DIR/.claude/state"

# stdin JSON을 한 번만 읽어 둔다.
HOOK_INPUT="$(cat)"

input() { jq -r "$1 // empty" <<<"$HOOK_INPUT"; }

# 세션이 지금 작업 중인 저장소 루트. EnterWorktree로 들어간 worktree면 PROJECT_DIR(hook 위치)과 다르다.
_cwd="$(input .cwd)"
# shellcheck disable=SC2034  # source 하는 hook들이 쓴다
WORK_DIR="$(git -C "${_cwd:-$PROJECT_DIR}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PROJECT_DIR")"

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

# 파일(아직 없어도 됨)을 담은 저장소의 루트와 그 루트 기준 상대 경로. 심볼릭 링크(/tmp → /private/tmp)를 풀어 비교한다.
# 출력: "<root>\t<rel>". 저장소 밖이면 아무것도 출력하지 않는다.
repo_locate() {
  local f="$1" d rest root phys
  d="$(dirname "$f")"
  while [ ! -d "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do d="$(dirname "$d")"; done
  rest="${f#"$d"/}"
  phys="$(cd "$d" 2>/dev/null && pwd -P)" || return 0
  root="$(git -C "$phys" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$root" ] || return 0
  printf '%s\t%s' "$root" "${phys#"$root"}/$rest" | sed -E 's#\t/+#\t#'
}

# 저장소 루트가 git worktree add로 만든 linked worktree인지(메인 체크아웃이 아닌지).
is_linked_worktree() {
  local gd cd
  gd="$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  cd="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  [ -n "$gd" ] && [ "$gd" != "$cd" ]
}
