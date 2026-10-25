---
name: spec
description: INTENT.md를 바탕으로 docs/work/<번호>/spec.md(계약·데이터 변경·검증 가능한 수용 기준·ADR 필요 여부)를 쓰고 spec-reviewer로 검토한 뒤 draft PR을 연다. 사람 승인 1번째 지점.
argument-hint: "[이슈 번호] (생략하면 브랜치에서 찾음)"
allowed-tools: Read, Glob, Grep, Edit(docs/work/**), Bash(git status *), Bash(git diff *), Bash(git add docs/work/*), Bash(git commit *)
---
## 작업 컨텍스트
!`git branch --show-current`

## 할 일
이슈 번호는 인자 또는 브랜치 이름(`worktree-issue-<번호>`)에서 정한다. `docs/work/<번호>/INTENT.md`가 없으면 멈추고 `/intent <번호>`를 안내한다. INTENT의 열린 질문이 답 없이 남아 있으면 사람에게 먼저 묻는다.

### 1. spec.md 작성
코드는 쓰지 않는다. 필요한 코드와 문서를 읽고 다음 형식으로 쓴다.

```
# Spec: #<번호> <제목>
관련 요구: ... · 관련 결정: ... · INTENT: ./INTENT.md

## 범위 (In / Out)
## 설계
  필터·컴포넌트 배치, 처리 순서상 위치(PRD §3), 실패·저하 동작(MONITOR, Redis·Kafka·auth 장애)
## 계약
  ### HTTP API   경로, 메서드, 요청·응답, 상태 코드, 오류 {code, message, requestId}
  ### 헤더       읽는 헤더, 지우는 헤더, 주입하는 헤더
  ### 이벤트     토픽, 스키마, 하위 호환 여부
  ### 데이터     Flyway 새 버전, 테이블·컬럼 변경
  (해당 없으면 "변경 없음")
## 수용 기준
- AC-1: <조건> → <관찰 가능한 결과>. 검증: <테스트 종류와 대략의 이름>
## ADR 필요 여부
  PRD §9·plan §4 열린 항목을 정하거나 확정 결정과 다르게 가면 "필요: <주제>". 아니면 "없음".
```

### 2. 검토
`spec-reviewer` subagent를 호출한다. 프롬프트에는 이슈 번호와 파일 경로만 준다(작성 과정이나 의도는 넘기지 않는다).
돌려받은 내용을 `docs/work/<번호>/spec-review.md`에 그대로 저장한다.
Verdict가 REVISE면 Blocking 항목을 반영해 spec.md를 고치고 다시 검토한다. 2회 검토 후에도 REVISE면 멈추고 남은 항목을 사람에게 보여 준다.

### 3. draft PR
APPROVE면 `docs/work/<번호>/`만 커밋한다(`docs(#<번호>): spec`). 그다음 push와 draft PR 생성은 사람 확인을 거친다:
`git push -u origin HEAD` → `gh pr create --draft --base develop --title "#<번호> <제목>" --body "Closes #<번호>\n\nSpec: docs/work/<번호>/spec.md"`

마지막으로 안내한다: "spec을 검토하고 승인하면 PR에 `spec-approved` 라벨을 붙여 주세요. 그 뒤 `/work-plan`."
라벨은 에이전트가 붙이지 않는다.
