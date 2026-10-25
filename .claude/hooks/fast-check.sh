#!/usr/bin/env bash
# 막는 실패: 포맷·문법 오류나 Gateway hot path의 블로킹 호출이 전체 빌드나 리뷰 단계에서야 드러나는 것.
# 근거: 하네스 설계 Layer 3 #4, NFR-11. 파일 하나 기준 수 초 안에 끝나는 검사만 둔다. 전체 테스트는 verify-gate·verifier 몫.
# PostToolUse · Edit|Write. 실패 내용을 decision block + 사유로 돌려준다.

source "$(dirname "$0")/_lib.sh"

file="$(input .tool_input.file_path)"
[ -z "$file" ] || [ ! -f "$file" ] && exit 0
loc="$(repo_locate "$file")"
if [ -n "$loc" ]; then rel="${loc#*$'\t'}"; else rel="$(rel_path "$file")"; fi
problems=""

add() { problems="${problems}$1"$'\n'; }

case "$rel" in
  *.kt|*.kts)
    if command -v ktlint >/dev/null 2>&1; then
      out="$(ktlint --relative "$file" 2>&1)" || add "ktlint:"$'\n'"$out"
    fi
    case "$rel" in
      gatehouse-gateway/src/main/*.kt)
        hits="$(grep -nE '\.block(First|Last|Optional)?\(\)|Thread\.sleep|runBlocking|\bmono[[:space:]]*\{|JdbcTemplate|RestTemplate' "$file")"
        [ -n "$hits" ] && add "Gateway 요청 경로에 블로킹 호출·코루틴 브리지가 있습니다(NFR-11, .claude/rules/gateway-reactive.md):"$'\n'"$hits"
        ;;
    esac
    ;;
  *.sh)
    out="$(bash -n "$file" 2>&1)" || add "bash -n:"$'\n'"$out"
    if command -v shellcheck >/dev/null 2>&1; then
      out="$(shellcheck -S warning "$file" 2>&1)" || add "shellcheck:"$'\n'"$out"
    fi
    ;;
  *.json)
    out="$(jq empty "$file" 2>&1)" || add "JSON 문법 오류: $out"
    ;;
esac

[ -z "$problems" ] && exit 0
hook_log fast-check block "$rel"
jq -cn --arg r "$rel 빠른 검사 실패. 고친 뒤 계속하세요.
$problems" '{decision:"block", reason:$r}'
exit 0
