#!/usr/bin/env bash
# 막는 실패: 파괴적 삭제, force push, gitleaks 우회(--no-verify, hooksPath 변경), 운영 도구 호출,
#   비밀 파일 열람, allowlist 밖 네트워크 호출, 셸 명령으로 하네스 파일 변조.
# 근거: 하네스 설계 Layer 2·3 (Phase 0 가드레일). permissions deny는 sh -c 등으로 우회되므로 hook으로 한 번 더 막는다.
# PreToolUse · Bash. 차단은 exit 2 + stderr 사유.

source "$(dirname "$0")/_lib.sh"

cmd="$(input .tool_input.command)"
[ -z "$cmd" ] && exit 0

block() {
  hook_log guard-bash block "$1"
  echo "guard-bash: 차단 — $1" >&2
  echo "필요한 작업이면 사람이 직접 실행하도록 명령과 이유를 알려 주세요." >&2
  exit 2
}

has() { grep -Eq -- "$1" <<<"$cmd"; }

# 1. 파괴적 삭제: 재귀 rm의 대상이 루트·홈·상위·현재 디렉터리 전체·.git이면 차단. rm -rf build/ 는 허용.
if has '(^|[;&|[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)'; then
  if has '[[:space:]](/|/\*|~|~/|~/\*|\$HOME/?|\.\.?/?|\*|\.git/?)([[:space:];&|]|$)'; then
    block "재귀 삭제 대상이 루트·홈·현재 디렉터리 전체·.git 입니다: $cmd"
  fi
fi
has '(^|[;&|[:space:]])git[[:space:]]+clean[[:space:]]+[^;&|]*-[a-zA-Z]*x' &&
  block "git clean -x 는 gitignore된 로컬 설정(.env, application-local*)까지 지웁니다"

# 2. force push, 보호 브랜치 직접 push, gitleaks 우회
if has '(^|[;&|[:space:]])git[[:space:]]+push'; then
  has '[[:space:]](--force|--force-with-lease|-f)([[:space:]=]|$)|[[:space:]]\+[^[:space:]]+' &&
    block "force push"
  has '[[:space:]](origin[[:space:]]+)?(HEAD:)?(refs/heads/)?(main|develop)([[:space:]]|$)' &&
    block "main·develop 브랜치에 직접 push — PR로 병합하세요"
fi
has '(^|[;&|[:space:]])git[[:space:]]+(commit|push|merge|rebase)[[:space:]][^;&|]*--no-verify' &&
  block "--no-verify 는 gitleaks pre-push hook을 건너뜁니다"
has 'core\.hooksPath' && has 'git[[:space:]]+config' && ! has 'git[[:space:]]+config[[:space:]]+(--get[[:space:]]+)?core\.hooksPath[[:space:]]*($|[;&|])' &&
  block "core.hooksPath 변경은 gitleaks hook을 끕니다"

# 3. GitHub의 되돌리기 어려운 작업
has '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge' && block "PR 병합은 사람이 합니다"
has '(^|[;&|[:space:]])gh[[:space:]]+(pr|issue)[[:space:]]+edit[[:space:]].*spec-approved' &&
  block "spec-approved 라벨은 사람이 spec을 승인할 때 붙입니다"
has '(^|[;&|[:space:]])gh[[:space:]]+(repo[[:space:]]+delete|release[[:space:]]+delete|secret|variable)' &&
  block "저장소 삭제·secret·variable 변경"
has '(^|[;&|[:space:]])gh[[:space:]]+api[[:space:]].*(-X|--method)[[:space:]]*(DELETE|PUT)' &&
  block "gh api DELETE·PUT (브랜치 보호 등 저장소 설정 변경)"

# 4. 운영 도구
has '(^|[;&|[:space:](/])(kubectl|aws|terraform|eksctl|helm)([[:space:]]|$)' && ! has 'helm[[:space:]]+(lint|template)([[:space:]]|$)' &&
  block "운영 도구(kubectl·aws·terraform·eksctl·helm). helm lint/template 만 허용"

# 5. 비밀 파일 열람 (Read deny 규칙을 셸로 우회하는 경우)
if has '(^|[[:space:]/"'"'"'=])\.env(\.[A-Za-z0-9_-]+)?([[:space:]"'"'"';&|]|$)' && ! has '\.env\.example'; then
  block ".env 파일 접근"
fi
has '(application-(local|secret|prod)[A-Za-z0-9_-]*\.(ya?ml|properties))|(~|\$HOME)/\.(ssh|aws|kube)|(credentials|client_secret)[A-Za-z0-9_-]*\.json' &&
  block "비밀 설정·자격 증명 파일 접근"

# 6. 셸로 하네스 파일 변조 (Edit deny 우회)
protected='\.claude/(settings(\.local)?\.json|hooks/)|\.githooks/|CODEOWNERS|\.gitleaks(ignore|\.toml)'
if has "$protected"; then
  if has '(^|[;&|[:space:]])(sed|perl)[[:space:]][^;&|]*-i|(^|[;&|[:space:]])(tee|mv|cp|rm|chmod|chown|truncate|ln|install|dd|unlink)[[:space:]]' ||
     has ">>?[[:space:]]*[\"']?[^[:space:]]*($protected)"; then
    block "셸 명령으로 하네스 보호 파일 변경"
  fi
fi

# 7. 네트워크: 원격 스크립트 실행, allowlist 밖 호출
has '(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh' && block "원격 스크립트를 바로 실행"
if has '(^|[;&|[:space:](])(curl|wget|http|https|nc|ncat)[[:space:]]'; then
  allowed='^(localhost|127\.0\.0\.1|\[::1\]|github\.com|api\.github\.com|[a-z0-9.-]+\.githubusercontent\.com|repo\.maven\.apache\.org|repo1\.maven\.org|plugins\.gradle\.org|services\.gradle\.org|registry\.npmjs\.org|code\.claude\.com|docs\.spring\.io)$'
  for host in $(grep -Eo 'https?://[^/[:space:]"'"'"'?#]+' <<<"$cmd" | sed -E 's#^https?://##; s#^.*@##; s#:[0-9]+$##' | tr 'A-Z' 'a-z'); do
    grep -Eq "$allowed" <<<"$host" || block "allowlist 밖 네트워크 호출: $host"
  done
fi

exit 0
