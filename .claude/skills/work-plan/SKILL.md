---
name: work-plan
description: 승인된 spec.md를 태스크로 나눠 docs/work/<번호>/plan.md 체크박스 목록을 만든다. 태스크마다 테스트 1개 이상과 커밋 1개. spec 승인 뒤, 구현 전에 쓴다.
argument-hint: "[이슈 번호]"
allowed-tools: Read, Glob, Grep, Edit(docs/work/**), Bash(gh pr view *), Bash(git branch *)
---
## spec 승인 상태
!`gh pr view --json number,labels,isDraft --jq '"PR #\(.number) draft=\(.isDraft) labels=\([.labels[].name] | join(","))"' 2>/dev/null || echo "열린 PR 없음"`

## 할 일
1. 위 결과에 `spec-approved` 라벨이 없으면 멈추고 사람에게 spec 승인을 요청한다. 라벨을 직접 붙이지 않는다.
2. `docs/work/<번호>/spec.md`와 관련 코드를 읽는다.
3. `docs/work/<번호>/plan.md`를 쓴다.

```
# Plan: #<번호>
Spec: ./spec.md

- [ ] T1: <한 줄 목표> — AC-1
  - 테스트: <먼저 쓸 실패 테스트 이름과 위치>
  - 변경: <파일·모듈>
  - 커밋: `<type>(<scope>): <요약> (<요구 ID>)`
- [ ] T2: ...
- [ ] T-last: ./gradlew check 전체 통과
```

규칙:
- 모든 AC가 하나 이상의 태스크에 연결돼야 한다. 연결 안 된 AC가 있으면 plan.md 끝에 적고 멈춘다.
- 태스크는 하나의 커밋으로 끝낼 수 있는 크기로 자른다(대략 파일 5개, diff 300줄 이내).
- 순서는 의존 관계대로. `gatehouse-common` → 각 서비스 모듈 순.
- 서로 독립적인 태스크가 많아도 병렬 실행은 제안만 하고 기본은 순차로 둔다.

끝나면 태스크 수를 알리고 `/implement`를 안내한다. 긴 구현이면 다음 형식의 `/goal`을 제안한다:
`/goal docs/work/<번호>/plan.md의 모든 태스크가 체크되고 ./gradlew check가 통과할 때까지`
