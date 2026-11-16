#!/usr/bin/env bash
# 막는 실패: 코드를 바꾸고 테스트를 돌리지 않았거나 실패한 채로 "완료"라고 보고하는 것.
# 근거: 하네스 설계 Layer 3 #5. record-test.sh가 남긴 마지막 Gradle 결과의 작업 트리 지문이 지금과 같고 통과였을 때만 종료를 허용한다.
# Stop. 한 턴에서 연속 3회 거부했으면 통과시키고 사람에게 알린다(무한 루프 방지).

source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_tree.sh"

MAX_BLOCKS=3
session="$(input .session_id)"
state="$STATE_DIR/verify/${session:-unknown}.json"

# 아직 Gradle 빌드가 없으면(스캐폴드 전) 검사할 것이 없다.
[ -x "$WORK_DIR/gradlew" ] || exit 0

changed="$(changed_code_files)"
[ -z "$changed" ] && exit 0

tree="$(tree_fingerprint)"
last_tree="" last_result="" last_scope="" blocks=0
if [ -f "$state" ]; then
  last_tree="$(jq -r '.tree // empty' "$state")"
  last_result="$(jq -r '.result // empty' "$state")"
  last_scope="$(jq -r '.scope // "full"' "$state")"
  blocks="$(jq -r '.blocks // 0' "$state")"
fi

# 전체 실행(scope=full)이 통과했고 그 뒤로 작업 트리가 그대로일 때만 끝낼 수 있다.
if [ "$tree" = "$last_tree" ] && [ "$last_result" = pass ] && [ "$last_scope" = full ]; then
  exit 0
fi

# stop_hook_active=false면 이번 턴의 첫 Stop이다. 연속 거부 횟수를 새로 센다.
[ "$(input .stop_hook_active)" = true ] || blocks=0
blocks=$((blocks + 1))
mkdir -p "$STATE_DIR/verify"
if [ -f "$state" ]; then
  jq --argjson b "$blocks" '.blocks = $b' "$state" >"$state.tmp" && mv "$state.tmp" "$state"
else
  jq -cn --argjson b "$blocks" '{tree:"", result:"none", blocks:$b}' >"$state"
fi

if [ "$blocks" -gt "$MAX_BLOCKS" ]; then
  hook_log verify-gate give-up "연속 ${MAX_BLOCKS}회 거부 후 통과"
  jq -cn --arg m "verify-gate: 테스트 통과 기록 없이 ${MAX_BLOCKS}회 종료를 막았지만 해결되지 않아 통과시켰습니다. 사람이 확인해 주세요." \
    '{systemMessage:$m}'
  exit 0
fi

# 거부 사유는 에이전트가 다음에 무엇을 해야 하는지 알 수 있게 경우별로 나눈다.
if [ "$tree" != "$last_tree" ]; then
  why="코드가 바뀐 뒤 통과한 테스트 기록이 없습니다"
elif [ "$last_result" = fail ]; then
  why="마지막 테스트가 실패한 상태입니다"
elif [ "$last_result" = pass ]; then
  why="일부 모듈·테스트만 통과한 상태입니다(전체 실행 기록 없음)"
else
  why="마지막 Gradle 실행의 결과를 출력에서 읽지 못했습니다(BUILD SUCCESSFUL·BUILD FAILED 줄이 없음). 출력을 head·grep으로 자르면 이렇게 됩니다"
fi
hook_log verify-gate block "$why ($blocks/$MAX_BLOCKS)"
jq -cn --arg r "$why ($blocks/$MAX_BLOCKS). 변경된 코드 파일:
$(head -20 <<<"$changed")
전체 검사를 끝부분이 남게 실행해 통과시키고 끝내세요: ./gradlew check 2>&1 | tail -30
모듈 단위(:<모듈>:check)나 --tests 실행은 작업 중 확인용이고, 끝내는 조건은 전체 ./gradlew check 입니다.
고칠 수 없는 실패라면 원인과 재현 명령을 정리해 사람에게 넘기세요." '{decision:"block", reason:$r}'
exit 0
