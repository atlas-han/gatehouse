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
# 사용자 전역 설정의 hooksPath가 픽스처 커밋에 끼어들지 않게 한다(pre-commit은 아래에서 따로 지정해 시험한다).
git -C "$FIX" config core.hooksPath "$FIX/.git/hooks"
# guard-bash의 네트워크 허용 목록은 settings.json에서 읽는다. 실제 설정을 그대로 써서 hook과 설정을 함께 시험한다.
mkdir -p "$FIX/.claude" && cat "$HOOKS/../settings.json" >"$FIX/.claude/settings.json" || exit 1
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
  out="$(CLAUDE_PROJECT_DIR="${HOOK_PROJECT_DIR:-$FIX}" bash "$HOOKS/$1.sh" <<<"$2" 2>"$err")"
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

# 사례가 덮어쓰고 지운 추적 파일(.claude/settings.json 등)을 되돌린다.
git -C "$WT" checkout -q -- . 2>/dev/null

# --- 기록 위치: worktree에서 시작한 세션(PROJECT_DIR=worktree)의 기록도 메인 체크아웃 state/에 쌓인다 ---
HOOK_PROJECT_DIR="$WT" run_hook guard-bash "$(jq -cn --arg cwd "$WT" '{session_id:"wt-session", cwd:$cwd, tool_name:"Bash", tool_input:{command:"rm -rf /"}}')" >/dev/null
if grep -q '"session":"wt-session"' "$FIX/.claude/state/hook-events.jsonl" 2>/dev/null && [ ! -e "$WT/.claude/state" ]; then ok
else bad "_lib: worktree 세션의 hook 기록이 메인 체크아웃 state/에 남는다"; fi

# --- verify-gate·record-test 시나리오 ---
stop_input() { jq -cn --argjson a "${1:-false}" '{session_id:"vg", stop_hook_active:$a}'; }
gradle_input() { gradle_cmd_input "./gradlew check" "$1"; }
gradle_cmd_input() { jq -cn --arg cmd "$1" --arg out "$2" '{session_id:"vg", tool_name:"Bash", tool_input:{command:$cmd}, tool_response:{stdout:$out, stderr:""}}'; }
expect_gate_reason() { # expect_gate_reason <label> <거부 사유에 있어야 할 문자열>
  local res
  res="$(run_hook verify-gate "$(stop_input false)")"
  if [ "$(classify "$res")" = block ] && grep -qF -- "$2" <<<"$res"; then ok; else bad "verify-gate: $1 (block + '$2' 기대)" "$(sed -n '2,$p' <<<"$res")"; fi
}
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
# 범위와 판정 불가: 2026-10-31 issue-1에서 출력을 head로 자른 실행 때문에 gate가 3회 막고 포기했다.
run_hook record-test "$(gradle_cmd_input "./gradlew :gatehouse-gateway:check" 'BUILD SUCCESSFUL in 2s')" >/dev/null
[ "$(jq -r .scope "$FIX/.claude/state/verify/vg.json")" = partial ] && ok || bad "record-test: 모듈 단위 실행을 scope=partial로 기록"
expect_gate_reason "모듈 단위 통과만으로는 끝낼 수 없음" "일부 모듈"
run_hook record-test "$(gradle_cmd_input "./gradlew test --tests '*FooTest'" 'BUILD SUCCESSFUL in 2s')" >/dev/null
expect_gate_reason "--tests로 좁힌 통과만으로는 끝낼 수 없음" "일부 모듈"
run_hook record-test "$(gradle_cmd_input "./gradlew check 2>&1 | grep -v at | head -5" 'Starting a Gradle Daemon')" >/dev/null
expect_gate_reason "출력이 잘려 판정 불가면 이유를 알려 줌" "출력에서 읽지 못했습니다"
run_hook record-test "$(gradle_cmd_input "./gradlew build -x test" 'BUILD SUCCESSFUL in 2s')" >/dev/null
expect_gate_reason "테스트를 뺀 빌드는 기록하지 않음(앞 기록 유지)" "출력에서 읽지 못했습니다"
run_hook record-test "$(gradle_cmd_input "export JAVA_HOME=/x; ./gradlew check 2>&1 | tail -30" 'BUILD SUCCESSFUL in 4s')" >/dev/null
expect_gate "전체 실행을 tail로 본 통과" allow false

# --- load-context 시나리오 ---
mkdir -p "$WT/docs/work/9" && echo "# spec" >"$WT/docs/work/9/spec.md"
ctx="$(sed -n '2,$p' <<<"$(run_hook load-context "$(jq -cn --arg cwd "$WT" '{session_id:"lc", source:"startup", cwd:$cwd}')")")"
grep -q '이슈: #9' <<<"$ctx" && grep -q '\[x\] spec.md' <<<"$ctx" && grep -q '다음 단계: /intent' <<<"$ctx" && ok ||
  bad "load-context: worktree-issue-9 안에서 이슈·단계 인식" "$ctx"
ctx="$(sed -n '2,$p' <<<"$(run_hook load-context "$(jq -cn --arg cwd "$FIX" '{session_id:"lc", source:"startup", cwd:$cwd}')")")"
grep -q '메인 체크아웃' <<<"$ctx" && grep -q 'worktrees/issue-9 (worktree-issue-9)' <<<"$ctx" && ok ||
  bad "load-context: 메인 체크아웃 안내와 기존 worktree 목록" "$ctx"

# --- work-status 시나리오: /work 표의 행을 위에서부터 하나씩 지난다 ---
W9="$WT/docs/work/9"
mkdir -p "$FIX/bin" && printf '#!/bin/sh\n[ -n "$GH_STUB" ] && echo "$GH_STUB" || exit 1\n' >"$FIX/bin/gh" && chmod +x "$FIX/bin/gh"
expect_next() { # expect_next <label> <"다음 단계" 줄에 있어야 할 문자열> [gh가 돌려줄 PR 줄, 없으면 --no-gh]
  local out
  if [ $# -ge 3 ]; then out="$(cd "$WT" && PATH="$FIX/bin:$PATH" GH_STUB="$3" bash "$HOOKS/work-status.sh" 9)"
  else out="$(cd "$WT" && bash "$HOOKS/work-status.sh" --no-gh 9)"; fi
  if grep '^- 다음 단계: ' <<<"$out" | grep -qF -- "$2"; then ok; else bad "work-status: $1 ('$2' 기대)" "$out"; fi
}
printf '# #9\n## 목표\n## 열린 질문\n- 질문 하나 (출처)\n  답:\n- 질문 둘\n  답: 예\n' >"$W9/INTENT.md"
expect_next "답 없는 열린 질문" "열린 질문 1개"
printf '# #9\n## 목표\n## 열린 질문\n- 질문 하나 (출처)\n  답: 아니오\n' >"$W9/INTENT.md"
expect_next "spec-review 없음" "/spec 9"
printf '# Spec review: #9\nVerdict: REVISE\n\n## Blocking\n- [B1] x\n' >"$W9/spec-review.md"
expect_next "REVISE면 spec으로" "/spec 9 — spec-review가 REVISE"
expect_next "REVISE여도 사람이 라벨로 승인했으면 진행" "/work-plan 9" "#3 draft=true labels=area:gateway,spec-approved"
printf '# spec\n## 검토 후 남긴 항목\n- B1: 그대로 둔다\n' >"$W9/spec.md"
expect_next "남긴 항목을 적었으면 승인 대기(라벨 없음)" "PR에 spec-approved 라벨이 없습니다" "#3 draft=true labels=area:gateway"
expect_next "남긴 항목을 적었으면 승인 대기(확인 불가)" "확인하지 못했습니다"
printf '# Spec review: #9\nVerdict: APPROVE\n' >"$W9/spec-review.md"
expect_next "APPROVE + 라벨" "/work-plan 9" "#3 draft=true labels=spec-approved"
printf '# Spec review: #9\nVerdict: REVISE\n' >"$W9/spec-review.md"
git -C "$WT" add -A && git -C "$WT" commit -qm "docs(#9): spec"
pin="$(git -C "$WT" rev-parse --short HEAD)"
printf '# Plan: #9\nSpec: ./spec.md @ %s\n\n- [x] T1: a\n- [ ] T2: b\n- [ ] T-last: check\n' "$pin" >"$W9/plan.md"
expect_next "plan.md가 있으면 승인된 것으로 보고 구현(issue-1 상태)" "/implement 9 — 미완료 태스크 2개"
expect_next "라벨이 빠졌으면 plan.md가 있어도 승인 대기" "PR에 spec-approved 라벨이 없습니다" "#3 draft=true labels="
sed 's/- \[ \]/- [x]/' "$W9/plan.md" >"$W9/plan.tmp" && mv "$W9/plan.tmp" "$W9/plan.md"
expect_next "태스크 완료, 보고서 없음" "/work-verify 9"
mkdir -p "$WT/gatehouse-gateway/src/main/kotlin" && echo "class A" >"$WT/gatehouse-gateway/src/main/kotlin/A.kt"
git -C "$WT" add -A && git -C "$WT" commit -qm "feat: a"
head9="$(git -C "$WT" rev-parse --short HEAD)"
report() { printf '# Verify report: #9\nOverall: %s\nBase: %s · Head: %s · Run: 1회차\n' "$1" "$pin" "$head9" >"$W9/verify-report.md"; }
report PASS
git -C "$WT" add -A && git -C "$WT" commit -qm "docs(#9): verify report run 1"
expect_next "PASS, 보고서 커밋만 뒤따름" "사람이 /ship"
echo "class B" >"$WT/gatehouse-gateway/src/main/kotlin/B.kt"
expect_next "검증 뒤 코드 변경" "/work-verify 9 — 마지막 검증 뒤"
rm -f "$WT/gatehouse-gateway/src/main/kotlin/B.kt"
report FAIL
expect_next "FAIL이면 구현으로" "/implement 9 — verify-report.md의 FAIL"
report PASS
echo "- AC-9: 추가" >>"$W9/spec.md"
expect_next "승인 뒤 spec 변경" "재승인"

# --- pre-commit: Claude Code 세션은 메인 체크아웃에 커밋하지 못한다. 스크립트 안의 커밋도 같다 ---
GITHOOKS="$(cd "$HOOKS/../.." && pwd)/.githooks"
try_commit() { # try_commit <dir> <CLAUDECODE 값, 빈 문자열이면 없음>
  (cd "$1" && if [ -n "$2" ]; then export CLAUDECODE="$2"; else unset CLAUDECODE; fi
   git -c core.hooksPath="$GITHOOKS" commit -q --allow-empty -m probe) >/dev/null 2>&1
}
if [ -x "$GITHOOKS/pre-commit" ]; then
  try_commit "$FIX" 1 && bad "pre-commit: 세션의 메인 체크아웃 커밋을 막는다" || ok
  try_commit "$WT" 1 && ok || bad "pre-commit: worktree 커밋은 허용한다"
  try_commit "$FIX" "" && ok || bad "pre-commit: 사람(CLAUDECODE 없음)의 메인 체크아웃 커밋은 허용한다"
else
  bad "pre-commit: $GITHOOKS/pre-commit 이 없거나 실행 권한이 없다"
fi

total=$((pass + fail))
echo "hook tests: $pass/$total passed"
[ "$fail" -eq 0 ]
