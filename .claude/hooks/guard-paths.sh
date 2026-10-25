#!/usr/bin/env bash
# 막는 실패: 에이전트가 하네스(설정·hook)를 스스로 완화하는 것, 이미 커밋된 Flyway 마이그레이션을 고쳐
#   운영 DB와 checksum이 어긋나는 것, gitleaks 예외·CODEOWNERS를 몰래 넓히는 것.
# 근거: 하네스 설계 Layer 2·3 (Phase 0 가드레일), admin-api가 스키마 소유자(plan §2.7).
# PreToolUse · Edit|Write|MultiEdit|NotebookEdit. permissionDecision deny(막음) 또는 ask(사람 확인).

source "$(dirname "$0")/_lib.sh"

file="$(input .tool_input.file_path)"
[ -z "$file" ] && file="$(input .tool_input.notebook_path)"
[ -z "$file" ] && exit 0
rel="$(rel_path "$file")"

decide() { # decide <deny|ask> <reason>
  hook_log guard-paths "$1" "$rel: $2"
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}'
  exit 0
}

case "$rel" in
  .claude/settings.json|.claude/settings.local.json|.claude/hooks/*|.githooks/*)
    decide deny "하네스 설정·hook($rel)은 에이전트가 고치지 않습니다. 필요한 변경을 diff로 제안하면 사람이 반영합니다." ;;
  .gitleaksignore|.gitleaks.toml|.github/CODEOWNERS|CODEOWNERS)
    decide deny "$rel 은 보안 예외·리뷰 경계를 정합니다. 사람이 직접 수정합니다." ;;
  .claude/*|.github/workflows/*|CLAUDE.md)
    decide ask "$rel 은 하네스·CI 구성입니다. 변경 이유를 확인한 뒤 승인하세요." ;;
esac

# 이미 커밋된 Flyway 버전 마이그레이션은 불변. 새 버전 파일만 허용.
if grep -Eq '(^|/)db/migration/V[0-9][^/]*__[^/]+\.sql$' <<<"$rel"; then
  if git -C "$PROJECT_DIR" cat-file -e "HEAD:$rel" 2>/dev/null; then
    decide deny "$rel 은 이미 커밋된 Flyway 마이그레이션입니다. 수정하지 말고 다음 버전(V<n+1>__...)을 새로 만드세요."
  fi
fi

exit 0
