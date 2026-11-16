---
name: work
description: 이슈 하나를 다음 사람 승인 지점까지 진행한다. 이슈 worktree를 자동으로 만들거나 들어간 뒤, docs/work/<번호>/ 상태를 보고 /intent → /spec → /work-plan → /implement ⇄ /work-verify를 이어서 실행한다. "이슈 N 진행해줘", "#N 작업 이어서 해줘"에 쓴다.
argument-hint: <이슈 번호> [--step]
---
## 현재 상태
!`bash .claude/hooks/work-status.sh $ARGUMENTS 2>&1 || echo "(work-status.sh를 실행하지 못했습니다. 이 worktree에 develop의 하네스가 병합됐는지 확인하세요)"`

## 할 일
인자: `$ARGUMENTS`. 이슈 번호가 없으면 멈추고 번호를 묻는다(이슈가 아직 없으면 `/issue`를 안내). `--step`이 있으면 아래 2단계에서 한 단계만 실행하고 멈춘다.

위 상태에 "경고" 줄이 있으면 진행하기 전에 사람에게 먼저 알린다.

### 1. 이슈 worktree로 이동
변경은 항상 이슈 worktree(`.claude/worktrees/issue-<번호>`, 브랜치 `worktree-issue-<번호>`)에서 한다.

| 위 상태 | 할 일 |
| --- | --- |
| 이미 `worktree-issue-<번호>` 브랜치의 worktree 안 | 그대로 진행 |
| 메인 체크아웃, 이슈 worktree 있음 | `EnterWorktree`에 `path: <이슈 worktree 경로>` |
| 메인 체크아웃, 이슈 worktree 없음 | `EnterWorktree`에 `name: issue-<번호>` |
| 다른 이슈·작업의 worktree 안 | 멈춘다. 사람에게 그 worktree를 정리하거나(ExitWorktree keep) 새 세션에서 `/work <번호>`를 실행하라고 안내 |

새로 만든 경우에는 `git merge-base --is-ancestor origin/develop HEAD`로 develop 기반인지 확인한다. 아니면 멈추고 알린다: "worktree가 develop이 아닌 곳에서 갈라졌습니다. `git remote set-head origin develop` 실행 후 다시 시도하세요." 만든 worktree는 지우지 않는다.

### 2. 다음 단계 실행
단계 판정은 `bash .claude/hooks/work-status.sh <번호>`의 "다음 단계" 줄이 한다. 스스로 파일을 보고 다시 판정하지 않는다. 한 단계가 끝날 때마다 이 명령을 다시 실행해 다음 행으로 이어 가고, "멈춤"이 나오면 끝낸다.

아래 표는 그 판정의 순서와 뜻이다. 위에서부터 처음 맞는 행이 "다음 단계"가 된다.

| 상태 | 다음 단계 | 끝난 뒤 |
| --- | --- | --- |
| INTENT.md 없음 | `/intent <번호>` | 열린 질문이 있으면 **멈춤** |
| INTENT.md의 열린 질문에 답이 없음 (항목 아래 `답:` 뒤가 비어 있음) | **멈춤** | 사람에게 질문을 보여 준다 |
| spec.md 또는 spec-review.md 없음 | `/spec <번호>` | **멈춤**: 사람의 spec 승인 대기 |
| spec 승인 없음, Verdict가 REVISE이고 spec.md에 "검토 후 남긴 항목"이 없음 | `/spec <번호>` | **멈춤**: 사람의 spec 승인 대기 |
| spec 승인 없음 (라벨이 없거나, gh 실패로 확인하지 못함) | **멈춤** | spec PR 링크와 함께 승인 요청. 확인하지 못한 경우에는 사람에게 라벨 상태를 묻는다 |
| plan.md 없음 | `/work-plan <번호>` | 계속 |
| plan.md에 미완료 태스크 | `/implement <번호>`를 태스크마다 한 번씩 | 계속. `/implement`가 멈추면 **멈춤** |
| verify-report.md 없음, 또는 보고서의 Head 뒤에 코드가 바뀜 | `/work-verify <번호>` | 계속. `/work-verify`가 회차 초과로 멈추면 **멈춤** |
| verify-report.md가 FAIL | `/implement <번호>`로 FAIL 상세를 고친다 | 계속(다시 `/work-verify`) |
| verify-report.md가 PASS인데 승인 뒤 spec.md가 바뀜 | **멈춤** | 사람에게 바뀐 내용을 보여 주고 재승인을 요청 |
| verify-report.md가 PASS | **멈춤** | 사람에게 `/ship` 호출 요청 |

spec 승인은 PR의 `spec-approved` 라벨이다. 라벨이 있으면 spec-review가 REVISE여도 진행한다(사람이 남은 지적을 받아들인 것이다). plan.md가 이미 있으면 `/work-plan`이 그때 라벨을 확인한 것이므로, 라벨을 지금 확인하지 못해도 승인된 것으로 본다(`spec 승인: inferred`).

단계 사이의 상태는 파일과 커밋으로만 넘긴다. 컨텍스트가 압축되거나 세션이 끊기면 `/work <번호>`를 다시 실행하면 이어진다.

### 하지 않는 것
- 사람 승인 지점을 건너뛰지 않는다: 열린 질문 답, `spec-approved` 라벨, `/ship`, PR 병합.
- `spec-approved` 라벨을 붙이지 않는다. `/ship`을 대신 하지 않는다(모델이 호출할 수 없다).
- 하위 skill의 멈춤 조건을 무시하고 다음 단계로 가지 않는다.

### 마지막 보고
실행한 단계 목록, 현재 상태(`work-status.sh`의 "다음 단계" 줄), 사람이 할 일 한 줄, 다시 이어갈 명령(`/work <번호>`).
