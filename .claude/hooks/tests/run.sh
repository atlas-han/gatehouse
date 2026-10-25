#!/usr/bin/env bash
# hook 단위 테스트. cases.json의 차단·허용 사례와 verify-gate·load-context 시나리오를 임시 git 저장소에서 돌린다.
# 사용: bash .claude/hooks/tests/run.sh   (CI: .github/workflows/harness.yml)

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOKS="$(dirname "$HERE")"
FIX="$(mktemp -d "${TMPDIR:-/tmp}/hooktest.XXXXXX")" || { echo "임시 디렉터리를 만들 수 없습니다" >&2; exit 1; }
trap 'rm -rf "$FIX"' EXIT

pass=0 fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && sed 's/^/      /' <<<"$2"; }

# 픽스처 저장소(메인 체크아웃): develop 브랜치에 커밋된 V1 마이그레이션 하나.
# 픽스처를 만들지 못하면 여기서 멈춘다. 이어서 돌면 git 명령이 실제 저장소에 적용된다.
git -C "$FIX" init -q -b develop || exit 1
git -C "$FIX" config user.email t@t && git -C "$FIX" config user.name t
mkdir -p "$FIX/gatehouse-admin-api/src/main/resources/db/migration"
echo "create table client (id bigint);" >"$FIX/gatehouse-admin-api/src/main/resources/db/migration/V1__init.sql"
printf '.claude/state/\n.claude/worktrees/\n' >"$FIX/.gitignore"
git -C "$FIX" add -A && git -C "$FIX" commit -qm init || exit 1
# 사례는 기본으로 linked worktree(EnterWorktree가 만드는 위치)에서 돈다. "in": "main"이면 메인 체크아웃.
WT="$FIX/.claude/worktrees/issue-9"
git -C "$FIX" worktree add -q -b worktree-issue-9 "$WT" || exit 1

run_hook() { # run_hook <hook> <json> → stdout에 "<exit>\n<stdout>\n<stderr>"
  local out err rc
  err="$(mktemp "${TMPDIR:-/tmp}/hookerr.XXXXXX")"
  out="$(CLAUDE_PROJECT_DIR="$FIX" bash "$HOOKS/$1.sh" <<<"$2" 2>"$err")"
  rc=$?
  printf '%s\n%s\n%s' "$rc" "$out" "$(cat "$err")"
  rm -f "$err"
}

classify() { # hook 결과 → block | ask | allow
  local rc out
  rc="$(head -1 <<<"$1")"
  out="$(sed -n '2,$p' <<<"$1")"
  if [ "$rc" = 2 ]; then echo block; return; fi
  local d
  d="$(jq -rs 'map(.hookSpecificOutput.permissionDecision // .decision // empty) | first // empty' <<<"$out" 2>/dev/null)"
  case "$d" in deny|block) echo block ;; ask) echo ask ;; *) echo allow ;; esac
}

n="$(jq length "$HERE/cases.json")"
for i in $(seq 0 $((n - 1))); do
  c="$(jq -c ".[$i]" "$HERE/cases.json")"
  hook="$(jq -r .hook <<<"$c")"
  expect="$(jq -r .expect <<<"$c")"
  file="$(jq -r '.file // empty' <<<"$c")"
  base="$WT"; [ "$(jq -r '.in // empty' <<<"$c")" = main ] && base="$FIX"
  label="$hook: $(jq -r '.cmd // .file' <<<"$c")$([ "$base" = "$FIX" ] && echo ' [main]')"

  if [ -n "$file" ]; then
    if jq -e 'has("content") or has("content_file")' <<<"$c" >/dev/null; then
      mkdir -p "$(dirname "$base/$file")"
      if jq -e 'has("content_file")' <<<"$c" >/dev/null; then
        cp "$HERE/$(jq -r .content_file <<<"$c")" "$base/$file"
      else
        jq -j .content <<<"$c" >"$base/$file"
      fi
    fi
  fi

  input="$(jq -c --arg fix "$base" '
    {session_id:"test", cwd:$fix}
    + (if .cmd then {tool_name:"Bash", tool_input:{command:.cmd}} else {} end)
    + (if .file and (.event | not) then {tool_name:"Edit", tool_input:{file_path:($fix + "/" + .file)}} else {} end)
    + (if .event then .event + {file_path:($fix + "/" + .file)} else {} end)' <<<"$c")"

  result="$(run_hook "$hook" "$input")"
  got="$(classify "$result")"
  if [ "$got" = "$expect" ]; then ok; else bad "$label (expect $expect, got $got)" "$(sed -n '2,$p' <<<"$result")"; fi

  # 내용을 만든 파일은 다음 사례에 영향을 주지 않게 지운다(커밋된 픽스처는 제외).
  if [ -n "$file" ] && jq -e 'has("content") or has("content_file")' <<<"$c" >/dev/null; then rm -f "$base/$file"; fi
done

# --- verify-gate·record-test 시나리오 ---
stop_input() { jq -cn --argjson a "${1:-false}" '{session_id:"vg", stop_hook_active:$a}'; }
gradle_input() { jq -cn --arg out "$1" '{session_id:"vg", tool_name:"Bash", tool_input:{command:"./gradlew check"}, tool_response:{stdout:$out, stderr:""}}'; }
expect_gate() { # expect_gate <label> <expect> <stop_hook_active>
  local got
  got="$(classify "$(run_hook verify-gate "$(stop_input "$3")")")"
  if [ "$got" = "$2" ]; then ok; else bad "verify-gate: $1 (expect $2, got $got)"; fi
}

expect_gate "gradlew 없음" allow false
printf '#!/bin/sh\n' >"$FIX/gradlew" && chmod +x "$FIX/gradlew"
git -C "$FIX" add -A && git -C "$FIX" commit -qm gradlew && git -C "$FIX" branch -q base
git -C "$FIX" checkout -qb worktree-issue-7
git -C "$FIX" branch -qf develop base
expect_gate "코드 변경 없음" allow false
mkdir -p "$FIX/docs/work/7" && echo "# spec" >"$FIX/docs/work/7/spec.md"
expect_gate "문서만 변경" allow false
mkdir -p "$FIX/gatehouse-gateway/src/main/kotlin" && echo "class A" >"$FIX/gatehouse-gateway/src/main/kotlin/A.kt"
expect_gate "코드 변경, 테스트 안 함" block false
run_hook record-test "$(gradle_input $'> Task :test FAILED\nBUILD FAILED in 3s')" >/dev/null
expect_gate "테스트 실패" block false
run_hook record-test "$(gradle_input 'BUILD SUCCESSFUL in 4s')" >/dev/null
expect_gate "테스트 통과" allow false
git -C "$FIX" add -A && git -C "$FIX" commit -qm wip
expect_gate "통과 후 커밋만 함(내용 동일)" allow false
echo "class B" >>"$FIX/gatehouse-gateway/src/main/kotlin/A.kt"
expect_gate "통과 후 다시 수정" block false
expect_gate "재진입 2회째" block true
expect_gate "재진입 3회째" block true
expect_gate "재진입 4회째 → 사람에게 넘김" allow true
expect_gate "다음 턴 첫 Stop은 다시 검사" block false

# --- load-context 시나리오 ---
mkdir -p "$WT/docs/work/9" && echo "# spec" >"$WT/docs/work/9/spec.md"
ctx="$(sed -n '2,$p' <<<"$(run_hook load-context "$(jq -cn --arg cwd "$WT" '{session_id:"lc", source:"startup", cwd:$cwd}')")")"
grep -q '이슈: #9' <<<"$ctx" && grep -q '\[x\] spec.md' <<<"$ctx" && grep -q '다음 단계: /intent' <<<"$ctx" && ok ||
  bad "load-context: worktree-issue-9 안에서 이슈·단계 인식" "$ctx"
ctx="$(sed -n '2,$p' <<<"$(run_hook load-context "$(jq -cn --arg cwd "$FIX" '{session_id:"lc", source:"startup", cwd:$cwd}')")")"
grep -q '메인 체크아웃' <<<"$ctx" && grep -q 'worktrees/issue-9 (worktree-issue-9)' <<<"$ctx" && ok ||
  bad "load-context: 메인 체크아웃 안내와 기존 worktree 목록" "$ctx"

total=$((pass + fail))
echo "hook tests: $pass/$total passed"
[ "$fail" -eq 0 ]
