#!/usr/bin/env bash
# 이슈 하나의 진행 단계를 판정해 출력한다. 판정 순서는 /work(skills/work/SKILL.md) 표의 "상태" 열과 같다.
# 막는 실패: 단계 판정이 load-context.sh, /work 머리말, 각 skill 머리말에 따로 있어 서로 다른 "다음 단계"를 안내하는 것.
#   2026-10-31 issue-1에서 spec-review가 REVISE인데 plan.md가 있는 상태를 load-context와 /work 표가 다르게 읽었다.
# 사용: work-status.sh [이슈 번호] [--no-gh]   번호를 생략하면 브랜치 이름에서 찾는다. 숫자가 아닌 인자는 무시한다.
#   --no-gh: PR 라벨을 조회하지 않는다(SessionStart처럼 빨라야 하는 곳).
# hook이 아니다. stdin을 읽지 않고, 파일과 git 상태를 읽기만 한다.

set -uo pipefail
source "$(dirname "$0")/_tree.sh" # CODE_PATH_RE, CODE_EXCLUDE_RE

n="" use_gh=1
for a in "$@"; do
  case "$a" in
    --no-gh) use_gh=0 ;;
    *[!0-9]*|'') ;;
    *) [ -z "$n" ] && n="$a" ;;
  esac
done

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "- git 저장소가 아닙니다"; exit 0; }
br="$(git branch --show-current 2>/dev/null)"
[ -z "$n" ] && n="$(sed -nE 's#^(.*/)?(worktree-)?(issue-)?([0-9]+)([-_/].*)?$#\4#p' <<<"$br")"
gd="$(git rev-parse --path-format=absolute --git-dir)"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
main="${common%/.git}"

if [ "$gd" = "$common" ]; then
  echo "- 위치: 메인 체크아웃 (${br:-detached})"
else
  echo "- 위치: worktree $root (${br:-detached})"
fi

# 이슈 worktree가 따로 있으면 그 안의 상태를 본다(메인 체크아웃에서 /work <번호>를 부른 경우).
if [ -n "$n" ]; then
  wt="$main/.claude/worktrees/issue-$n"
  if [ -d "$wt" ]; then echo "- 이슈 worktree: $wt (있음)"; root="$wt"; else echo "- 이슈 worktree: 없음"; fi
fi
g() { git -C "$root" "$@"; }

# worktree는 분기 시점의 hook·settings 사본을 갖는다. develop의 하네스 수정이 빠져 있으면 알린다.
if [ "$root" != "$main" ]; then
  if g rev-parse -q --verify origin/develop >/dev/null 2>&1 &&
     ! g diff --quiet origin/develop HEAD -- .claude/hooks .claude/settings.json .githooks 2>/dev/null; then
    echo "- 경고: 이 worktree의 하네스(hook·settings)가 origin/develop과 다릅니다. develop을 병합하세요(하네스를 고치는 브랜치면 무시)."
  fi
  if ! g diff --quiet HEAD -- .claude/hooks .claude/settings.json .githooks 2>/dev/null; then
    echo "- 경고: 커밋되지 않은 하네스 수정이 worktree에 있습니다. 메인 체크아웃에서 시작한 세션에는 적용되지 않습니다."
  fi
fi

if [ -z "$n" ]; then
  echo "- 연결된 이슈: 없음"
  exit 0
fi

rel="docs/work/$n"
d="$root/$rel"
echo "- 이슈: #$n · 작업 폴더: $rel/"
for f in INTENT.md spec.md spec-review.md plan.md verify-report.md; do
  if [ -f "$d/$f" ]; then echo "  - [x] $f"; else echo "  - [ ] $f"; fi
done

# INTENT.md "## 열린 질문" 아래에서 "답:" 뒤가 빈 줄의 수.
unanswered=0
if [ -f "$d/INTENT.md" ]; then
  unanswered="$(awk '/^## /{s=($0 ~ /^## 열린 질문/)} s && /^[[:space:]]*답:[[:space:]]*$/{c++} END{print c+0}' "$d/INTENT.md")"
  echo "- INTENT 답 없는 열린 질문: ${unanswered}개"
fi

verdict="" carried=0
if [ -f "$d/spec-review.md" ]; then
  verdict="$(sed -nE 's/^Verdict:[[:space:]]*([A-Z]+).*/\1/p' "$d/spec-review.md" | head -1)"
  [ -f "$d/spec.md" ] && grep -q '^## 검토 후 남긴 항목' "$d/spec.md" && carried=1
  echo "- spec-review: ${verdict:-판정 없음}$([ "$carried" = 1 ] && echo ' (spec.md에 "검토 후 남긴 항목" 있음)')"
fi

# spec 승인: yes | no | unknown(조회 실패·생략). plan.md가 있으면 /work-plan이 그때 라벨을 확인한 것이므로 inferred.
approved=unknown pr=""
if [ "$use_gh" = 1 ] && [ -f "$d/spec.md" ]; then
  pr="$(gh pr view "$(g branch --show-current)" --json number,isDraft,labels \
    --jq '"#\(.number) draft=\(.isDraft) labels=\([.labels[].name] | join(","))"' 2>/dev/null)"
  if [ -n "$pr" ]; then
    if grep -Eq 'labels=(.*,)?spec-approved(,|$)' <<<"$pr"; then approved=yes; else approved=no; fi
  fi
  echo "- PR: ${pr:-없음 또는 확인 불가(gh 실패)}"
fi
[ "$approved" = unknown ] && [ -f "$d/plan.md" ] && approved=inferred
[ -f "$d/spec.md" ] && echo "- spec 승인: $approved"

open_tasks=0 pin="" spec_changed=0
if [ -f "$d/plan.md" ]; then
  open_tasks="$(grep -c '^[[:space:]]*- \[ \]' "$d/plan.md")"
  echo "- plan.md 미완료 태스크: ${open_tasks}개"
  # plan.md 머리의 "Spec: ./spec.md @ <커밋>"이 승인된 spec 버전이다.
  pin="$(sed -nE 's/^Spec:.*@[[:space:]]*([0-9a-f]{7,40}).*/\1/p' "$d/plan.md" | head -1)"
  if [ -n "$pin" ] && g cat-file -e "$pin^{commit}" 2>/dev/null; then
    g diff --quiet "$pin" -- "$rel/spec.md" 2>/dev/null || spec_changed=1
    [ "$spec_changed" = 1 ] && echo "- 경고: 승인된 버전($pin) 뒤에 spec.md가 바뀌었습니다. 사람의 재승인이 필요합니다."
  fi
fi

overall="" head="" code_after=0
if [ -f "$d/verify-report.md" ]; then
  overall="$(grep -m1 -Eo 'Overall: (PASS|FAIL)' "$d/verify-report.md" | sed 's/Overall: //')"
  head="$(sed -nE 's/^Base:.*Head:[[:space:]]*([0-9a-f]{7,40}).*/\1/p' "$d/verify-report.md" | head -1)"
  run="$(sed -nE 's/^Base:.*Run:[[:space:]]*([0-9]+).*/\1/p' "$d/verify-report.md" | head -1)"
  if [ -n "$head" ] && g cat-file -e "$head^{commit}" 2>/dev/null; then
    code_after="$({ g diff --name-only "$head" 2>/dev/null; g ls-files --others --exclude-standard 2>/dev/null; } |
      sort -u | grep -E "$CODE_PATH_RE" | grep -Evc "$CODE_EXCLUDE_RE")"
  else
    code_after=-1 # 보고서의 Head를 읽을 수 없으면 다시 검증한다
  fi
  echo "- 마지막 검증: ${overall:-판정 없음} · Run ${run:-?}회차 · Head ${head:-?} 뒤 바뀐 코드 파일: $([ "$code_after" -lt 0 ] && echo '알 수 없음' || echo "${code_after}개")"
fi

if [ ! -f "$d/INTENT.md" ]; then
  next="/intent $n"
elif [ "$unanswered" -gt 0 ]; then
  next="멈춤 — INTENT.md 열린 질문 ${unanswered}개에 사람이 답해야 합니다"
elif [ ! -f "$d/spec.md" ] || [ ! -f "$d/spec-review.md" ]; then
  next="/spec $n"
elif [ "$approved" = no ] || [ "$approved" = unknown ]; then
  if [ "$verdict" = REVISE ] && [ "$carried" = 0 ]; then
    next="/spec $n — spec-review가 REVISE입니다"
  elif [ "$approved" = unknown ]; then
    next="멈춤 — spec 승인 대기. spec-approved 라벨을 확인하지 못했습니다(gh 실패 또는 PR 없음)"
  else
    next="멈춤 — spec 승인 대기. PR에 spec-approved 라벨이 없습니다"
  fi
elif [ ! -f "$d/plan.md" ]; then
  next="/work-plan $n"
elif [ "$open_tasks" -gt 0 ]; then
  next="/implement $n — 미완료 태스크 ${open_tasks}개"
elif [ ! -f "$d/verify-report.md" ]; then
  next="/work-verify $n"
elif [ "$code_after" -ne 0 ]; then
  next="/work-verify $n — 마지막 검증 뒤 코드가 바뀌었습니다"
elif [ "$overall" = FAIL ]; then
  next="/implement $n — verify-report.md의 FAIL 상세부터"
elif [ "$overall" = PASS ] && [ "$spec_changed" = 1 ]; then
  next="멈춤 — 승인 뒤 spec.md가 바뀌었습니다. 사람의 재승인 뒤 /ship"
elif [ "$overall" = PASS ]; then
  next="멈춤 — 검증 통과. 사람이 /ship 을 호출합니다"
else
  next="/work-verify $n — 보고서에 판정이 없습니다"
fi
echo "- 다음 단계: $next"
exit 0
