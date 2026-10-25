---
name: issue
description: 대화에서 나온 작업이나 plan §3의 주차 일정을 /intent가 바로 읽을 수 있는 GitHub 이슈로 만든다. 이슈 작업 흐름의 시작점. 생성은 매번 사람이 확인한다.
argument-hint: "<설명> | --plan W<n>"
allowed-tools: Read, Glob, Grep, Bash(gh issue list *), Bash(gh issue view *), Bash(gh label list *)
---
## 저장소 라벨
!`gh label list --limit 100 || echo "(라벨을 불러오지 못했습니다. gh 로그인과 sandbox 설정을 확인하세요)"`

## 열린 이슈 (중복 검사용)
!`gh issue list --state open --limit 100 --json number,title,labels || echo "(이슈 목록을 불러오지 못했습니다)"`

## 할 일
인자: `$ARGUMENTS`. `--plan W<n>`이면 일괄 모드, 아니면 단건 모드다. 인자가 비어 있으면 대화에서 이슈로 만들 작업을 정리해 단건 모드로 진행한다.

### 단건 모드
1. PRD(`docs/prd/`)와 개발 계획(`docs/plan/development-plan.md`)에서 관련 요구 ID(GW-xx, AS-xx, AD-xx, NFR-xx), 확정 결정(D-xx), 일정 주차(plan §3 W<n>)를 찾는다.
2. 위 열린 이슈와 제목이나 요구 ID가 겹치면 멈추고 기존 이슈 번호를 알린다.
3. 아래 템플릿으로 본문을 `$TMPDIR/issue-<짧은 이름>.md`에 쓰고, 제목·라벨과 함께 사용자에게 보여 준다.
4. `gh issue create --title "<제목>" --body-file <파일> --label <라벨>,...`를 실행한다. 이 명령은 권한 확인을 거친다.
5. 만든 이슈 URL과 다음 단계 `claude -w issue-<번호>` → `/intent <번호>`를 안내한다.

### 일괄 모드 (`--plan W<n>`)
1. plan §3의 W<n> 행(작업, 완료 기준)과 관련 §2 설계를 읽는다.
2. 작업을 이슈 하나가 PR 하나가 되는 독립 단위로 나눈다. 주당 3~8개를 목표로 한다. 선후 관계가 있으면 본문 "관련"에 `선행: <제목>`으로 적는다.
3. 표(제목, 요구 ID, 완료 기준, 라벨)로 미리 보여 주고 멈춘다. 이미 있는 이슈와 겹치는 행은 표시한다.
4. 사람이 확인하면(빼거나 고친 행 반영) 한 건씩 단건 모드 3~4단계로 만든다. 선행 이슈를 먼저 만들고, 뒤 이슈 본문에서 `선행: #<번호>`로 바꾼다.
5. 만든 이슈 번호 목록과 `claude -w issue-<번호>` 안내로 끝낸다.

### 본문 템플릿
```
## 배경
<왜 필요한가. 대화·plan에서 온 맥락>

## 할 일
- <작업 단위>

## 완료 기준
- [ ] <관찰 가능한 결과> (출처: plan §3 W<n> / PRD GW-xx)

## 관련
요구: GW-xx, ... · 결정: D-xx, ... · 일정: plan §3 W<n>

## 열린 항목
- <PRD §9·plan §4에 걸리는 항목. 없으면 "없음">
```

완료 기준과 요구는 PRD·plan에 있는 것만 쓰고 출처를 단다. 없는 요구는 지어내지 말고 "열린 항목"에 질문으로 남긴다.

### 라벨
- 영역 하나: `area:gateway`, `area:auth`, `area:admin`, `area:common`, `area:console`, `area:harness`, `area:infra`
- 일정 하나(해당할 때): `W1`~`W8`

필요한 라벨이 위 저장소 라벨에 없으면 `gh label create <이름>`을 먼저 제안한다(권한 확인을 거친다).

### 하지 않는 것
- `spec-approved` 라벨을 붙이지 않는다. spec 승인은 사람이 한다.
- assignee, milestone, project를 지정하지 않는다.
- 이슈를 닫거나 수정하거나 지우지 않는다.
