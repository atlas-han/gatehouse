---
name: work-verify
description: verifier subagent로 구현 브랜치를 spec 수용 기준에 대해 검증하고 docs/work/<번호>/verify-report.md를 남긴다. FAIL이면 구현으로 돌아가고 3회를 넘기면 사람에게 넘긴다.
argument-hint: "[이슈 번호]"
allowed-tools: Read, Edit(docs/work/**), Bash(git add docs/work/*), Bash(git commit *)
---
## 이전 검증
!`n=$(git branch --show-current | sed -nE 's#^(.*/)?(worktree-)?(issue-)?([0-9]+)([-_/].*)?$#\4#p'); grep -E '^(Overall|Base)' "docs/work/$n/verify-report.md" 2>/dev/null || echo "이전 보고서 없음"`

## 할 일
1. plan.md에 미완료 태스크가 있으면 멈추고 `/implement`를 안내한다.
2. 이전 보고서의 `Run: <n>회차`를 읽는다. 이번이 4회차 이상이면 검증을 돌리지 말고 멈춘다. 지난 FAIL 항목들과 반복된 원인을 요약해 사람에게 넘긴다.
3. `verifier` subagent를 호출한다. 프롬프트에는 **이슈 번호, spec 경로, 회차만** 넣는다. 구현 과정, 고민한 점, "이건 의도된 것" 같은 설명은 넣지 않는다.
4. 돌려받은 보고서를 수정 없이 `docs/work/<번호>/verify-report.md`에 저장하고 커밋한다(`docs(#<번호>): verify report run <n>`).
5. 결과에 따라:
   - `Overall: PASS` → 사람에게 결과를 요약하고 `/ship`을 직접 호출하라고 안내한다.
   - `Overall: FAIL` → FAIL 상세를 보여 주고 `/implement`로 돌아간다.

verifier 판정이 틀렸다고 생각되면 보고서를 고치지 말고 사람에게 이의를 알린다. 판정이 사람과 어긋난 사례는 `.claude/HARNESS.md`의 verifier 항목 개선에 쓰인다.
