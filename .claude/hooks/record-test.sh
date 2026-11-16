#!/usr/bin/env bash
# verify-gate.sh의 짝. Gradle 테스트 실행 결과와 그때의 작업 트리 지문을 세션별로 기록한다.
# Bash tool_response에 exit code가 없어 Gradle 출력의 BUILD SUCCESSFUL/FAILED로 판정한다.
# 범위(scope)도 남긴다. full은 전체 test/check/build, partial은 모듈 단위(:모듈:check)나 --tests로 좁힌 실행이다.
# verify-gate는 full만 통과로 본다.
# PostToolUse · Bash.

source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_tree.sh"

cmd="$(input .tool_input.command)"

# 명령 안의 Gradle 호출 조각(다음 ; & | 앞까지)마다 범위를 본다. 하나라도 full이면 full.
scope=""
while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  grep -Eq -- '-x[[:space:]]+test\b|--dry-run|(^|[[:space:]])-m([[:space:]]|$)' <<<"$seg" && continue
  if grep -Eq '[[:space:]](test|check|build)([[:space:]]|$)' <<<"$seg" && ! grep -Eq -- '--tests([[:space:]=]|$)' <<<"$seg"; then
    scope=full
  elif grep -Eq '[[:space:]]:?([A-Za-z0-9_.-]+:)*(test|check|build)([[:space:]]|$)' <<<"$seg"; then
    [ -z "$scope" ] && scope=partial
  fi
done < <(grep -Eo '(^|[;&|[:space:]])(\./gradlew|gradle)[[:space:]][^;&|]*' <<<"$cmd")
[ -n "$scope" ] || exit 0

out="$(input .tool_response.stdout)$(input .tool_response.stderr)"
if grep -q 'BUILD FAILED' <<<"$out"; then result=fail
elif grep -q 'BUILD SUCCESSFUL' <<<"$out"; then result=pass
else result=unknown
fi

session="$(input .session_id)"
mkdir -p "$STATE_DIR/verify"
jq -cn --arg tree "$(tree_fingerprint)" --arg result "$result" --arg scope "$scope" --arg cmd "$cmd" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{tree:$tree, result:$result, scope:$scope, command:$cmd, ts:$ts, blocks:0}' >"$STATE_DIR/verify/${session:-unknown}.json"
exit 0
