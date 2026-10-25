---
name: intent
description: GitHub 이슈를 읽어 docs/work/<번호>/INTENT.md 초안(목표·비목표·제약·수용 기준 초안·열린 질문)을 만든다. 이슈 작업의 첫 단계.
argument-hint: <이슈 번호>
allowed-tools: Bash(gh issue view *), Read, Glob, Grep, Edit(docs/work/**)
---
## 이슈 원문
!`gh issue view $0 --comments || echo "(이슈 #$0 을 불러오지 못했습니다. 번호와 gh 로그인을 확인하세요)"`

## 현재 브랜치
!`git branch --show-current`

## 할 일
1. 이슈 worktree 안이 아니면 먼저 들어간다. `.claude/worktrees/issue-$0`이 있으면 `EnterWorktree`에 `path`로, 없으면 `name: issue-$0`으로 만든다. 다른 이슈의 worktree 안이면 멈추고 안내한다.
2. PRD(`docs/prd/`)와 개발 계획(`docs/plan/development-plan.md`)에서 이 이슈와 관련된 요구 ID(GW-xx, AS-xx, AD-xx, NFR-xx)와 확정 결정(D-xx)을 찾는다.
3. `docs/work/$0/INTENT.md`를 아래 형식으로 쓴다.

```
# #<번호> <이슈 제목>
관련 요구: GW-xx, ... · 관련 결정: D-xx, ... · 일정: plan §3 W<n>

## 목표
## 비목표
## 제약 (PRD·plan·ADR에서 온 것만, 출처 표기)
## 수용 기준 초안
- [ ] 관찰 가능한 결과로 쓴다 (예: "X-Client-ID와 Client-ID 값이 다르면 400과 {code,message,requestId}")
## 열린 질문
- <질문> (출처)
  답:
```
열린 질문이 없으면 섹션에 "없음"이라고 쓴다. 사람은 각 질문 아래 `답:`을 채운다. `/work`는 답이 빈 질문이 있으면 멈춘다.

이슈와 PRD에 없는 요구는 지어내지 말고 열린 질문으로 남긴다. PRD §9·plan §4의 열린 항목에 걸리면 열린 질문에 그 항목을 적는다.
끝나면 INTENT.md 경로와 열린 질문 수를 알리고, 사람이 열린 질문에 답한 뒤 `/spec`으로 넘어가라고 안내한다.
