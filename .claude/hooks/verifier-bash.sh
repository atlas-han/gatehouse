#!/usr/bin/env bash
# 막는 실패: 검증자가 테스트를 통과시키려고 코드를 고치거나 상태를 바꾸는 것(생성과 검증의 분리가 깨짐).
# 근거: 하네스 설계 Layer 4. subagent tools 필드로는 Bash 명령을 패턴으로 제한할 수 없어 hook으로 제한한다.
# verifier subagent 전용 PreToolUse · Bash. 허용 목록 밖이면 exit 2.

source "$(dirname "$0")/_lib.sh"

cmd="$(input .tool_input.command)"
[ -z "$cmd" ] && exit 0

# 파이프·연결로 다른 명령을 끼워 넣지 못하게 한다. 출력 리다이렉트도 금지(2>&1만 허용).
stripped="${cmd//2>&1/}"
if grep -Eq '[;&`]|\$\(|>|[[:space:]]-(delete|exec|execdir|ok)([[:space:]]|$)|--output' <<<"$stripped"; then
  hook_log verifier-bash block "$cmd"
  echo "verifier-bash: 명령 연결·치환·리다이렉트는 쓸 수 없습니다. 명령을 하나씩 실행하세요. (파이프는 grep/head/tail/wc로만)" >&2
  exit 2
fi

ok_segment() {
  grep -Eq '^[[:space:]]*(\./gradlew[[:space:]]+[^[:space:]]*(test|check|build|dependencies|tasks)[^[:space:]]*([[:space:]]|$)|git[[:space:]]+(diff|log|show|status|rev-parse|merge-base|ls-files|blame)([[:space:]]|$)|(grep|head|tail|wc|ls|cat|find)([[:space:]]|$))' <<<"$1"
}

IFS='|' read -r -a segments <<<"$stripped"
for seg in "${segments[@]}"; do
  if ! ok_segment "$seg"; then
    hook_log verifier-bash block "$cmd"
    echo "verifier-bash: verifier는 ./gradlew test/check/build, 읽기 전용 git, grep/head/tail/wc/ls/cat/find만 실행합니다: $seg" >&2
    exit 2
  fi
done
exit 0
