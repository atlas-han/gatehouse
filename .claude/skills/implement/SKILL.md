---
name: implement
description: docs/work/<번호>/plan.md의 다음 미완료 태스크를 테스트 먼저 구현하고 커밋한다. verify-report.md가 FAIL이면 그 FAIL 항목부터 고친다.
argument-hint: "[이슈 번호] [태스크 ID]"
---
## 작업 상태
!`bash .claude/hooks/work-status.sh $ARGUMENTS --no-gh 2>&1 || echo "(work-status.sh를 실행하지 못했습니다)"`

## 다음 미완료 태스크
!`n=$(git branch --show-current | sed -nE 's#^(.*/)?(worktree-)?(issue-)?([0-9]+)([-_/].*)?$#\4#p'); grep -n '^- \[ \]' "docs/work/$n/plan.md" 2>/dev/null | head -5 || true`

## 할 일
plan.md가 없으면 멈추고 `/work-plan`을 안내한다.

verify-report.md가 `Overall: FAIL`이면 새 태스크보다 "FAIL 상세" 항목을 먼저 처리한다. 고친 항목마다 회귀 테스트를 더한다.

태스크 하나마다:
1. 태스크의 테스트를 먼저 쓰고 실행해 **실패하는 것을 확인**한다. (`./gradlew :<모듈>:test --tests '<이름>'`)
2. 테스트를 통과시키는 최소 구현을 한다. 경로별 규칙(`.claude/rules/`)이 자동으로 로드되니 따른다.
3. hook 피드백(fast-check, scan-secrets)이 오면 바로 고친다. 무시하거나 우회하지 않는다.
4. `./gradlew :<모듈>:check`를 통과시킨다. 이것은 태스크 중 확인용이다.
5. plan.md의 해당 체크박스를 `[x]`로 바꾸고, plan.md에 적은 커밋 메시지로 커밋한다. 커밋 하나에 태스크 하나.

턴을 끝내기 전에는 전체 `./gradlew check 2>&1 | tail -30`을 통과시킨다. Stop hook(verify-gate)은 전체 실행의 통과만 인정하고, 출력에서 `BUILD SUCCESSFUL` 줄을 읽는다. 출력을 `head`나 `grep`으로 자르면 통과해도 인식하지 못하니 `tail`로 끝부분을 남긴다.

멈추고 사람에게 물을 때:
- spec에 없는 계약(API, 헤더, 이벤트, 스키마)을 바꿔야 할 때
- PRD §9·plan §4 열린 항목을 정해야 할 때 (ADR 후보로 기록)
- 같은 테스트 실패를 3번 고쳐도 해결되지 않을 때

spec.md를 고쳐야 하면 멈추고 사람에게 알린다. 승인된 spec(plan.md 머리의 `Spec: ./spec.md @ <커밋>`)이 바뀌면 재승인이 필요하다.

모든 태스크가 체크되면 `./gradlew check` 전체를 돌리고 `/work-verify`를 안내한다.
