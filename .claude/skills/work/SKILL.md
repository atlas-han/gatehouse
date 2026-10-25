---
name: work
description: 이슈 하나를 다음 사람 승인 지점까지 진행한다. 이슈 worktree를 자동으로 만들거나 들어간 뒤, docs/work/<번호>/ 상태를 보고 /intent → /spec → /work-plan → /implement ⇄ /work-verify를 이어서 실행한다. "이슈 N 진행해줘", "#N 작업 이어서 해줘"에 쓴다.
argument-hint: <이슈 번호> [--step]
---
## 현재 상태
```!
args="$ARGUMENTS"
n="$(printf '%s' "$args" | grep -Eo '^[0-9]+' || true)"
br="$(git branch --show-current 2>/dev/null)"
[ -z "$n" ] && n="$(printf '%s' "$br" | sed -nE 's#^(.*/)?(worktree-)?(issue-)?([0-9]+)([-_/].*)?$#\4#p')"
gd="$(git rev-parse --path-format=absolute --git-dir)"; cd_="$(git rev-parse --path-format=absolute --git-common-dir)"
main="$(dirname "$cd_")"; root="$(git rev-parse --show-toplevel)"
echo "- 이슈: ${n:-없음} · 인자: ${args:-없음}"
if [ "$gd" = "$cd_" ]; then echo "- 위치: 메인 체크아웃 ($br)"; else echo "- 위치: worktree $root ($br)"; fi
wt="$main/.claude/worktrees/issue-$n"
if [ -n "$n" ] && [ -d "$wt" ]; then echo "- 이슈 worktree: $wt (있음)"; root="$wt"; elif [ -n "$n" ]; then echo "- 이슈 worktree: 없음"; fi
if [ -n "$n" ]; then
  d="$root/docs/work/$n"
  for f in INTENT.md spec.md spec-review.md plan.md verify-report.md; do [ -f "$d/$f" ] && echo "  - [x] $f" || echo "  - [ ] $f"; done
  [ -f "$d/spec-review.md" ] && grep -m1 -E '^Verdict:' "$d/spec-review.md" | sed 's/^/  - spec-review /'
  [ -f "$d/plan.md" ] && echo "  - plan.md 미완료 태스크: $(grep -c '^[[:space:]]*- \[ \]' "$d/plan.md")개"
  [ -f "$d/verify-report.md" ] && grep -E '^(Overall|Base)' "$d/verify-report.md" | sed 's/^/  - verify-report /'
  labels="$(gh pr view "worktree-issue-$n" --json labels,isDraft,number --jq '"#\(.number) draft=\(.isDraft) labels=\([.labels[].name] | join(","))"' 2>/dev/null)"
  echo "- PR: ${labels:-없음 또는 확인 불가(gh 실패)}"
fi
true
```

## 할 일
인자: `$ARGUMENTS`. 이슈 번호가 없으면 멈추고 번호를 묻는다(이슈가 아직 없으면 `/issue`를 안내). `--step`이 있으면 아래 2단계에서 한 단계만 실행하고 멈춘다.

### 1. 이슈 worktree로 이동
변경은 항상 이슈 worktree(`.claude/worktrees/issue-<번호>`, 브랜치 `worktree-issue-<번호>`)에서 한다.

| 위 상태 | 할 일 |
| --- | --- |
| 이미 `worktree-issue-<번호>` 브랜치의 worktree 안 | 그대로 진행 |
| 메인 체크아웃, 이슈 worktree 있음 | `EnterWorktree`에 `path: <이슈 worktree 경로>` |
| 메인 체크아웃, 이슈 worktree 없음 | `EnterWorktree`에 `name: issue-<번호>` |
| 다른 이슈·작업의 worktree 안 | 멈춘다. 사람에게 그 worktree를 정리하거나(ExitWorktree keep) 새 세션에서 `/work <번호>`를 실행하라고 안내 |

새로 만든 경우에는 `git merge-base --is-ancestor origin/develop HEAD`로 develop 기반인지 확인한다. 아니면 멈추고 알린다: "worktree가 develop이 아닌 곳에서 갈라졌습니다. `git remote set-head origin develop` 실행 후 다시 시도하세요." 만든 worktree는 지우지 않는다.

이동한 뒤에는 위 상태를 믿지 말고 worktree 안의 `docs/work/<번호>/`를 다시 확인한다.

### 2. 다음 단계 실행
위에서부터 처음 맞는 행을 실행하고, 끝나면 상태를 다시 확인해 다음 행으로 이어 간다. "멈춤"을 만나면 끝낸다.

| 상태 | 실행 | 끝난 뒤 |
| --- | --- | --- |
| INTENT.md 없음 | `/intent <번호>` | 열린 질문이 있으면 **멈춤** |
| INTENT.md의 열린 질문에 답이 없음 ("없음"이 아니고, 항목 아래 `답:` 뒤가 비어 있음) | — | **멈춤**: 사람에게 질문을 보여 준다 |
| spec.md 없음, spec-review.md 없음, 또는 Verdict: REVISE | `/spec <번호>` | **멈춤**: 사람의 spec 승인(`spec-approved` 라벨) 대기 |
| PR에 `spec-approved` 라벨 없음 (gh 실패로 확인 불가 포함) | — | **멈춤**: spec PR 링크와 함께 승인 요청 |
| plan.md 없음 | `/work-plan <번호>` | 계속 |
| plan.md에 미완료 태스크 | `/implement <번호>`를 태스크마다 한 번씩, 미완료가 0이 될 때까지 | 계속. `/implement`가 멈추면 **멈춤** |
| verify-report.md 없음, 또는 보고서의 Head 이후 코드 커밋이 있음 | `/work-verify <번호>` | PASS → **멈춤**: 사람에게 `/ship` 호출 요청. FAIL → `/implement <번호>`로 FAIL 상세를 고친 뒤 다시 이 행. `/work-verify`가 회차 초과로 멈추면 **멈춤** |
| verify-report.md가 PASS이고 그 뒤 코드 커밋 없음 | — | **멈춤**: 사람에게 `/ship` 호출 요청 |

단계 사이의 상태는 파일과 커밋으로만 넘긴다. 컨텍스트가 압축되거나 세션이 끊기면 `/work <번호>`를 다시 실행하면 이어진다.

### 하지 않는 것
- 사람 승인 지점을 건너뛰지 않는다: 열린 질문 답, `spec-approved` 라벨, `/ship`, PR 병합.
- `spec-approved` 라벨을 붙이지 않는다. `/ship`을 대신 하지 않는다(모델이 호출할 수 없다).
- 하위 skill의 멈춤 조건을 무시하고 다음 단계로 가지 않는다.

### 마지막 보고
실행한 단계 목록, 현재 상태(위 표의 어느 행인지), 사람이 할 일 한 줄, 다시 이어갈 명령(`/work <번호>`).
