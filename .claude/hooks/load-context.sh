#!/usr/bin/env bash
# 막는 실패: 세션을 새로 열거나 컨텍스트가 압축된 뒤, 어떤 이슈의 어느 단계였는지 잃고 처음부터 다시 조사하는 것.
# 근거: 하네스 설계 Layer 3 #6, Layer 5(단계 상태는 docs/work/<이슈>/ 파일로 남긴다).
# SessionStart. stdout이 컨텍스트로 들어간다.

source "$(dirname "$0")/_lib.sh"

branch="$(git -C "$WORK_DIR" branch --show-current 2>/dev/null)"

echo "## Gatehouse 작업 컨텍스트"
echo "- 브랜치: ${branch:-detached}"

if ! is_linked_worktree "$WORK_DIR"; then
  echo "- 위치: 메인 체크아웃(읽기 전용). 파일을 바꾸는 작업은 EnterWorktree로 worktree를 만든 뒤 한다(이슈: name issue-<번호>, 그 밖: name task-<짧은-이름>). /work <번호>는 이를 자동으로 한다."
  wts="$(git -C "$WORK_DIR" worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{p=$2} /^branch /{sub("refs/heads/","",$2); if (p ~ /\/\.claude\/worktrees\//) print "  - " p " (" $2 ")"}')"
  if [ -n "$wts" ]; then
    echo "- 이어서 할 수 있는 worktree (EnterWorktree path로 들어간다):"
    echo "$wts"
  fi
  exit 0
fi

# issue-123, worktree-issue-123, feat/123-foo, 123-foo 형식에서 이슈 번호를 찾는다.
issue="$(sed -nE 's#^(.*/)?(worktree-)?(issue-)?([0-9]+)([-_/].*)?$#\4#p' <<<"$branch")"
echo "- 위치: worktree $WORK_DIR"
if [ -z "$issue" ]; then
  echo "- 연결된 이슈: 없음"
  exit 0
fi

dir="docs/work/$issue"
echo "- 이슈: #$issue · 작업 폴더: $dir/"
next=""
for step in INTENT.md:/intent spec.md:/spec spec-review.md:/spec plan.md:/work-plan verify-report.md:/work-verify; do
  f="${step%%:*}"
  if [ -f "$WORK_DIR/$dir/$f" ]; then
    echo "  - [x] $f"
  else
    echo "  - [ ] $f"
    [ -z "$next" ] && next="${step#*:}"
  fi
done
if [ -f "$WORK_DIR/$dir/plan.md" ]; then
  open_tasks="$(grep -c '^[[:space:]]*- \[ \]' "$WORK_DIR/$dir/plan.md" 2>/dev/null)"
  echo "- plan.md 남은 태스크: ${open_tasks:-0}개"
  [ "${open_tasks:-0}" -gt 0 ] && [ "$next" = /work-verify ] && next=/implement
fi
if [ -f "$WORK_DIR/$dir/verify-report.md" ]; then
  verdict="$(grep -m1 -Eo 'Overall: (PASS|FAIL)' "$WORK_DIR/$dir/verify-report.md")"
  echo "- 마지막 검증: ${verdict:-판정 없음}"
  [ "$verdict" = "Overall: FAIL" ] && next=/implement
  [ "$verdict" = "Overall: PASS" ] && next="/ship (사람이 호출)"
fi
echo "- 다음 단계: ${next:-/intent $issue} (또는 /work $issue 로 다음 사람 승인 지점까지 진행)"
exit 0
