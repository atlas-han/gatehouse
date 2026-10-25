#!/usr/bin/env bash
# 작업 트리 지문과 "검증이 필요한 변경" 판정. record-test.sh와 verify-gate.sh가 같이 쓴다.

# 코드로 보는 경로. 문서·하네스만 바뀐 경우는 테스트를 요구하지 않는다.
CODE_PATH_RE='\.(kt|kts|java|sql|toml|ya?ml|properties|ts|svelte)$|(^|/)gradlew$'
CODE_EXCLUDE_RE='^(docs|\.claude|\.github|evals)/'

# gitignore를 존중하는 현재 작업 트리 전체의 tree hash. 커밋 여부와 무관하게 내용이 같으면 같은 값.
tree_fingerprint() {
  local idx
  idx="$(mktemp)"
  rm -f "$idx"
  cp "$(git -C "$PROJECT_DIR" rev-parse --git-path index 2>/dev/null)" "$idx" 2>/dev/null || true
  GIT_INDEX_FILE="$idx" git -C "$PROJECT_DIR" add -A -- . ':!.claude/state' >/dev/null 2>&1
  GIT_INDEX_FILE="$idx" git -C "$PROJECT_DIR" write-tree 2>/dev/null
  rm -f "$idx"
}

# 기준 브랜치(develop) 대비 바뀐 코드 파일 목록. 커밋된 것과 아직 안 한 것 모두.
changed_code_files() {
  local base
  base="$(git -C "$PROJECT_DIR" merge-base HEAD origin/develop 2>/dev/null ||
          git -C "$PROJECT_DIR" merge-base HEAD develop 2>/dev/null)"
  {
    [ -n "$base" ] && git -C "$PROJECT_DIR" diff --name-only "$base" 2>/dev/null
    git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null
    git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | grep -E "$CODE_PATH_RE" | grep -Ev "$CODE_EXCLUDE_RE"
}
