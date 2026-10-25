#!/usr/bin/env bash
# 막는 실패: Secret·pepper·서명 키·Google OIDC 자격 증명이 소스나 테스트 픽스처에 들어가 push 직전에야 발견되는 것.
# 근거: NFR-09, 하네스 설계 Layer 3 #3. pre-push gitleaks보다 앞에서, 파일을 쓰는 즉시 알려 바로 고치게 한다.
# PostToolUse · Edit|Write. 이미 쓰인 뒤라 막을 수 없으므로 decision block + 사유로 다음 행동을 유도한다.

source "$(dirname "$0")/_lib.sh"

file="$(input .tool_input.file_path)"
[ -z "$file" ] || [ ! -f "$file" ] && exit 0
rel="$(rel_path "$file")"

if ! command -v gitleaks >/dev/null 2>&1; then
  hook_log scan-secrets warn "gitleaks 미설치"
  jq -cn '{systemMessage:"scan-secrets: gitleaks가 없어 비밀값 검사를 건너뛰었습니다 (brew install gitleaks)"}'
  exit 0
fi

report="$(mktemp)"
trap 'rm -f "$report"' EXIT
gitleaks dir "$file" --no-banner --redact --log-level error --exit-code 3 \
  --gitleaks-ignore-path "$PROJECT_DIR" --report-format json --report-path "$report" >/dev/null 2>&1
rc=$?

if [ "$rc" -eq 3 ]; then
  findings="$(jq -r '.[] | "- \(.RuleID) (line \(.StartLine))"' "$report" 2>/dev/null | sort -u)"
  hook_log scan-secrets block "$rel: $(tr '\n' ' ' <<<"$findings")"
  jq -cn --arg r "$rel 에 비밀값으로 보이는 값이 있습니다.
$findings
값을 제거하고 환경 변수나 gitignore된 application-local.yml에서 읽게 바꾸세요. 테스트는 실행 중 생성한 값을 쓰세요.
명백한 더미 값이면 해당 줄에 'gitleaks:allow' 주석을 답니다." '{decision:"block", reason:$r}'
fi
exit 0
