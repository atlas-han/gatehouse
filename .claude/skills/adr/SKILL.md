---
name: adr
description: docs/adr/에 ADR을 새로 쓴다. PRD §9·plan §4의 열린 항목을 정하거나, 확정 결정(D-xx)·plan §2와 다르게 갈 때 쓴다.
argument-hint: <결정 주제>
allowed-tools: Read, Glob, Grep, Edit(docs/adr/**)
---
## 기존 ADR
!`ls docs/adr/ 2>/dev/null | grep -E '^[0-9]{4}-' || echo "(없음)"`

## 할 일
주제: $ARGUMENTS

1. 다음 번호를 정한다(기존 최대 번호 + 1, 4자리). 파일 이름은 `docs/adr/<번호>-<kebab-주제>.md`.
2. PRD, plan, 관련 이슈의 INTENT·spec, 기존 ADR을 읽고 `docs/adr/0000-template.md` 형식으로 쓴다.
3. 결정 내용은 사람이 정한 것만 적는다. 사람이 아직 정하지 않았으면 상태를 `Proposed`로 두고 선택지와 추천만 적는다.
4. 이 ADR이 PRD §9나 plan §4의 항목을 닫는다면 "닫는 열린 항목"에 적는다. PRD·plan 본문은 고치지 않는다.
