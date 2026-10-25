#!/usr/bin/env bash
# 막는 실패: 세션 도중 설정 파일이 바뀌어 hook이 꺼지거나 권한·sandbox가 느슨해진 상태로 작업이 이어지는 것.
# 근거: 하네스 설계 Layer 2 "에이전트의 하네스 변조", Layer 3 #7.
# ConfigChange. exit 2면 변경이 이 세션에 적용되지 않는다(사유는 표시되지 않고 debug 로그에만 남는다).
# policy_settings는 막을 수 없으므로 검사하지 않는다.

source "$(dirname "$0")/_lib.sh"

source_kind="$(input .source)"
file="$(input .file_path)"
case "$source_kind" in user_settings|project_settings|local_settings) ;; *) exit 0 ;; esac
[ -n "$file" ] && [ -f "$file" ] || exit 0

reasons="$(jq -r '
  [ if .disableAllHooks == true then "disableAllHooks" else empty end,
    if (.permissions.defaultMode // "") == "bypassPermissions" then "defaultMode=bypassPermissions" else empty end,
    if (.permissions.disableBypassPermissionsMode // "disable") != "disable" then "disableBypassPermissionsMode 해제" else empty end,
    if .sandbox.enabled == false then "sandbox.enabled=false" else empty end,
    if .sandbox.allowUnsandboxedCommands == true then "allowUnsandboxedCommands=true" else empty end,
    if (.permissions.allow // [] | map(select(test("^Bash(\\(\\*\\))?$|^Bash\\((git push|gh pr merge|kubectl|aws|terraform)"))) | length) > 0
      then "위험 명령 allow" else empty end
  ] | join(", ")' "$file" 2>/dev/null)"

if [ -n "$reasons" ]; then
  hook_log guard-config block "$source_kind $file: $reasons"
  echo "guard-config: 세션 중 하네스 완화 시도 차단 ($reasons). 세션을 끝낸 뒤 사람이 직접 바꾸세요." >&2
  exit 2
fi
exit 0
