#!/usr/bin/env bash
# verify-gate.sh의 짝. Gradle 테스트 실행 결과와 그때의 작업 트리 지문을 세션별로 기록한다.
# Bash tool_response에 exit code가 없어 Gradle 출력의 BUILD SUCCESSFUL/FAILED로 판정한다.
# PostToolUse · Bash.

source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_tree.sh"

cmd="$(input .tool_input.command)"
grep -Eq '(^|[;&|[:space:]])(\./gradlew|gradle)([[:space:]].*)?[[:space:]](test|check|build)([[:space:]]|$)' <<<"$cmd" || exit 0
grep -Eq -- '-x[[:space:]]+test\b|--dry-run|(^|[[:space:]])-m([[:space:]]|$)' <<<"$cmd" && exit 0

out="$(input .tool_response.stdout)$(input .tool_response.stderr)"
if grep -q 'BUILD FAILED' <<<"$out"; then result=fail
elif grep -q 'BUILD SUCCESSFUL' <<<"$out"; then result=pass
else result=unknown
fi

session="$(input .session_id)"
mkdir -p "$STATE_DIR/verify"
jq -cn --arg tree "$(tree_fingerprint)" --arg result "$result" --arg cmd "$cmd" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{tree:$tree, result:$result, command:$cmd, ts:$ts, blocks:0}' >"$STATE_DIR/verify/${session:-unknown}.json"
exit 0
