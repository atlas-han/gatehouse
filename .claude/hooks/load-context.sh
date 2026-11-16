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

# 단계 판정은 work-status.sh 한곳에서 한다(/work와 각 skill 머리말도 같은 스크립트를 쓴다).
# 세션 시작은 빨라야 하므로 PR 라벨은 조회하지 않는다. 라벨이 필요한 지점이면 "확인하지 못했습니다"로 나온다.
here="$(cd "$(dirname "$0")" && pwd)"
(cd "$WORK_DIR" && bash "$here/work-status.sh" --no-gh)
echo "- /work <번호> 로 다음 사람 승인 지점까지 이어서 진행한다."
exit 0
