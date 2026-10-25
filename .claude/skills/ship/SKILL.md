---
name: ship
description: 검증을 통과한 이슈 브랜치를 마무리한다. 필요한 ADR을 쓰고, push하고, draft PR을 리뷰 가능 상태로 바꾼다. 사람 승인 2번째 지점.
argument-hint: "[이슈 번호]"
disable-model-invocation: true
---
## 상태
!`n=$(git branch --show-current | sed -nE 's#^(.*/)?(worktree-)?(issue-)?([0-9]+)([-_/].*)?$#\4#p'); echo "이슈: ${n:-?}"; grep -m1 -E 'Overall: (PASS|FAIL)' "docs/work/$n/verify-report.md" 2>/dev/null || echo "검증 보고서 없음"; grep -A3 '^## ADR 필요' "docs/work/$n/spec.md" 2>/dev/null || true; git status --short`

## 할 일
1. verify-report.md가 `Overall: PASS`가 아니거나, 그 뒤에 코드 커밋이 더 있으면 멈추고 `/work-verify`를 안내한다.
2. 커밋 안 된 변경이 있으면 멈추고 사람에게 알린다.
3. spec의 "ADR 필요 여부"가 "필요"면 `/adr`로 ADR을 쓰고 커밋한다.
4. PR 본문을 갱신한다: 요약, 관련 요구 ID, 수용 기준별 결과(verify-report 표), ADR 링크, 리뷰어가 볼 위험 지점. `Closes #<번호>`는 유지한다.
5. 다음 명령은 사람 확인을 거쳐 실행한다:
   - `git push`
   - `gh pr edit --body-file <임시 파일>`
   - `gh pr ready`
6. 안내한다: "PR을 리뷰하고 병합해 주세요. 병합 뒤 이 worktree 세션을 종료하면 정리 여부를 묻습니다."

병합(`gh pr merge`)은 하지 않는다. 막혀 있다.
