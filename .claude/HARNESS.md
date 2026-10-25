# Gatehouse 하네스 결정 기록

Claude Code 하네스의 구성요소마다 도입 이유, 근거, 제거 조건을 적는다. 월간 점검과 모델 교체 때 이 표를 보고 근거가 사라진 항목을 하나씩 빼고 eval(`evals/`)로 확인한다.

기준 문서: "Claude Code 단독 하네스 설계"(2026-10-25). 원래 결제팀(Kotlin/Go/Kafka)용 설계를 Gatehouse(Kotlin 단일 언어, 1인 개발, 코드 없는 상태)에 맞게 바꿨다. 바꾼 점은 맨 아래 "설계 문서와 다른 점"에 있다.

**근거의 종류.** 아직 코드와 세션 기록이 없어서, 대부분의 항목은 *관찰된 실패*가 아니라 PRD·plan의 확정 결정에서 *예상한 실패*를 근거로 들였다. 이런 항목은 근거 칸에 `예상`으로 표시한다. 3개월 동안 한 번도 동작하지 않으면 제거 후보다. 실제 실패가 관찰되면 이슈 번호로 바꾼다.

## Layer 1 · 메모리와 가이드

| 구성요소 | 막는 실패 | 근거 | 제거 조건 |
| --- | --- | --- | --- |
| `CLAUDE.md` | 아키텍처·횡단 규칙을 모르고 설계 | plan §1–2 | 없음(항상 유지). 100줄 이내 유지 |
| `rules/gateway-reactive.md` | Gateway hot path의 블로킹·DB 조회 | 예상 · NFR-11, GW-11 | BlockHound·ArchUnit 테스트가 생기면 포인터 한 줄로 줄인다 |
| `rules/secrets-and-identity.md` | Secret 평문·비상수 시간 비교·로그 노출, 신원 헤더 누수 | 예상 · NFR-09, GW-10/17 | `SecretDigester`·헤더 정규화 테스트가 생기면 포인터로 줄인다 |
| `rules/kafka-events.md` | 이벤트 스키마 비호환 변경, outbox 우회 | 예상 · AD-10, GW-11 | 직렬화 호환 테스트가 생기면 포인터로 줄인다 |
| `rules/admin-api-schema.md` | 감사 로그·outbox 누락, 커밋된 마이그레이션 수정 | 예상 · AD-09/10 | 통합 테스트로 강제되면 포인터로 줄인다 |

## Layer 2 · 권한과 보안 (`settings.json`)

| 구성요소 | 막는 실패 | 근거 | 제거 조건 |
| --- | --- | --- | --- |
| `Read` deny (.env, application-local/secret/prod, 키·자격 증명 파일, ~/.ssh·~/.aws·~/.kube) | 비밀값 읽기·유출 | NFR-09, .gitignore 목록 | 없음 |
| `Edit` deny (settings, hooks, .githooks, gitleaks 설정, CODEOWNERS) | 에이전트의 하네스 변조 | 설계 Layer 2 | 없음 |
| Bash deny (`gh pr merge`, force push, kubectl·aws·terraform·eksctl·helm 변경) | 사람 승인 없는 병합, 운영 조작 | 설계 Layer 2 | 없음 |
| `disableBypassPermissionsMode` | bypass 모드로 모든 가드 무력화 | 설계 "하지 않을 것" | 조직 관리형 설정이 대신하면 제거 |
| sandbox (filesystem·network allowlist) | `sh -c`·절대 경로로 Bash 규칙 우회 | 설계 Layer 2 | 없음 |

## Layer 3 · Hooks (`hooks/`, 테스트: `hooks/tests/run.sh`)

| hook | 이벤트 | 막는 실패 | 근거 | 제거 조건 |
| --- | --- | --- | --- | --- |
| `guard-bash.sh` | PreToolUse Bash | 파괴적 삭제, force push, `--no-verify`·hooksPath로 gitleaks 우회, 운영 도구, 비밀 파일 열람, 셸로 하네스 변조, allowlist 밖 네트워크, `spec-approved` 라벨 자가 부여(이슈 생성 포함), 이슈 삭제·이전 | 설계 #1, gitleaks pre-push 보호 | 없음 |
| `guard-paths.sh` | PreToolUse Edit\|Write | 하네스·보안 경계 파일 수정, 커밋된 Flyway 마이그레이션 수정, 메인 체크아웃에서의 파일 변경 | 설계 #2, plan §2.7, 2026-10-25 develop에 의도치 않은 `init` 커밋(아래 worktree 규칙) | 없음 |
| `scan-secrets.sh` | PostToolUse Edit\|Write | 비밀값이 push 직전에야 발견됨 | 설계 #3, NFR-09 | 6개월간 차단 0회면 pre-push만 남기는 것을 검토 |
| `fast-check.sh` | PostToolUse Edit\|Write | 문법·포맷 오류, Gateway 블로킹 호출이 늦게 발견됨 | 설계 #4, NFR-11 | BlockHound 도입 후 블로킹 grep 제거. ktlint는 Gradle 플러그인 도입 시 재검토 |
| `record-test.sh` + `verify-gate.sh` | PostToolUse Bash + Stop | 테스트 없이·실패한 채로 "완료" 보고 | 설계 #5 | eval에서 `no-verify-gate` 변형과 통과율 차이가 없으면 제거 |
| `load-context.sh` | SessionStart | 재개·압축 뒤 이슈·단계를 잃음. 메인 체크아웃이면 worktree 규칙과 이어갈 worktree 목록 안내 | 설계 #6 | 없음(비용 거의 없음) |
| `guard-config.sh` | ConfigChange | 세션 중 hook 비활성화·권한 완화 | 설계 #7 | 없음 |
| `verifier-bash.sh` | verifier 전용 PreToolUse Bash | 검증자가 코드를 고쳐 통과시킴 | 설계 Layer 4 (subagent `tools`로는 Bash 패턴 제한 불가) | 없음 |

차단·경고 기록: `.claude/state/hook-events.jsonl`(gitignore). 월간 점검 때 `jq -s 'group_by(.hook) | map({hook: .[0].hook, n: length})'`로 집계한다.

## Layer 4 · Subagents (`agents/`)

| 구성요소 | 역할 | 근거 | 제거·변경 조건 |
| --- | --- | --- | --- |
| `spec-reviewer` | spec의 빈틈·결정 충돌·검증 불가 기준 지적 (읽기 전용) | 설계 Layer 4 | spec PR에서 사람이 고친 지점을 놓친 비율이 높으면 프롬프트 수정 |
| `verifier` | 구현을 보지 않은 컨텍스트에서 수용 기준별 PASS/FAIL | 설계 Layer 4 (생성·검증의 컨텍스트 분리) | 판정이 사람과 어긋난 사례를 모아 프롬프트에 반영. `isolation` 미사용(기본 baseRef가 원격 기본 브랜치라 구현이 없음) |

두지 않은 것: planner(사람의 INTENT·spec 단계와 plan 모드로 충분), security-reviewer(verifier 체크리스트에 흡수, eval에서 이득이 확인되면 분리).

## Layer 5 · 워크플로 (`skills/`, 상태: `docs/work/<이슈>/`)

| skill | 하는 일 | 비고 |
| --- | --- | --- |
| `/issue <설명>` · `/issue --plan W<n>` | 대화의 작업·plan §3 주차 → GitHub 이슈(`/intent` 입력 형식) | 근거 `예상`(이슈를 손으로 옮겨 적음). `gh issue create`·`gh label create`는 allowed-tools에 넣지 않아 settings `ask`로 매번 사람이 확인 |
| `/work <이슈> [--step]` | 이슈 worktree로 이동(없으면 생성) 후 다음 사람 승인 지점까지 아래 단계를 이어서 실행 | 근거 `예상`(단계별 호출을 손으로 이어 붙임). 승인 지점에서 항상 멈춤. 사람 지점이 자주 무시되면 제거하고 단계별 호출로 돌아감 |
| `/intent <이슈>` | 이슈 → INTENT.md | 이슈 worktree(`.claude/worktrees/issue-<이슈>`, 브랜치 `worktree-issue-<이슈>`)에서. 없으면 EnterWorktree로 만듦 |
| `/spec` | spec.md + spec-reviewer + draft PR | **사람 승인 1**: PR에 `spec-approved` 라벨 |
| `/work-plan` | plan.md 태스크 분해 | 내장 `/plan`과 이름이 겹쳐 `work-plan`으로 둠 |
| `/implement` | 태스크별 테스트 먼저 → 구현 → 커밋 | 긴 실행은 `/goal` |
| `/work-verify` | verifier 호출, verify-report.md | 내장 `/verify`와 이름이 겹쳐 `work-verify`로 둠. FAIL 3회 초과 시 사람에게 |
| `/ship` | ADR, PR 본문, `gh pr ready` | `disable-model-invocation: true`. **사람 승인 2**: PR 병합 |
| `/adr <주제>` | ADR 작성 | CLAUDE.md의 "열린 항목은 ADR로" 규칙 |

두지 않은 것: `kafka-event-catalog`, `api-drift`(문서화할 이벤트·API가 아직 없다. W3 이후 실제 drift가 관찰되면 추가).

### worktree 규칙

변경 작업은 모두 git worktree에서 한다. 메인 체크아웃은 읽기 전용이다.

- 이슈 작업은 `EnterWorktree name: issue-<번호>`, 그 밖의 변경은 `name: task-<짧은-이름>`으로 만든다. 이미 있으면 `path`로 들어간다. `/work`, `/intent`는 이를 자동으로 한다.
- 강제: `guard-paths.sh`는 메인 체크아웃 파일의 Edit·Write를 거부하고, `guard-bash.sh`는 메인 체크아웃의 commit·merge·rebase·브랜치 생성을 거부한다. CLAUDE.md에 규칙을 적은 이유는 EnterWorktree 도구가 사용자나 CLAUDE.md의 지시가 있을 때만 쓰이기 때문이다.
- 근거: 2026-10-25 hook 테스트 스크립트가 sandbox의 `mktemp` 실패를 무시하고 메인 체크아웃에서 `git add -A && git commit -m init`을 실행해 develop에 커밋을 만들었다(두 번 발생, 두 번째는 push됨). 사용자 요청.
- 전제: worktree 기본 base는 `origin/<기본 브랜치>`다. 로컬 `origin/HEAD`가 develop을 가리켜야 한다(`git remote set-head origin develop`). `/work`는 새 worktree가 develop 기반인지 확인한다.
- 사람은 hook의 대상이 아니다. 하네스 파일(hooks, settings)은 사람이 메인 체크아웃에서 직접 고친다.
- 제거 조건: 없음.

## Layer 6 · 외부 연결 (`.github/`)

| 구성요소 | 역할 | 비고 |
| --- | --- | --- |
| `workflows/harness.yml` | `.claude/` 변경 시 shellcheck + hook 테스트 | Phase 0 통과 기준 |
| `workflows/claude-intent.yml` | 이슈 코멘트 `@claude` → INTENT 초안 코멘트 | `ANTHROPIC_API_KEY` secret 필요. 저장소 소유자 코멘트만 반응 |
| `CODEOWNERS` | `.claude/`, `.githooks/`, `.github/`, gitleaks 설정, CLAUDE.md | 브랜치 보호에서 Code Owners 리뷰를 켜야 효과가 있음 |

GitHub 연동은 `gh` CLI만 쓴다(MCP 없음). 문서 정원 관리 예약 작업은 문서화할 대상이 생긴 뒤(W3 이후) 추가한다.

## Layer 7 · 관측과 평가

- 텔레메트리(OTel): 관측 스택이 없어(plan Context) 보류. Gatehouse 지표 파이프라인과 별개로, 외부 관측 스택이 생기면 `settings.json`의 `env`에 OTel 설정을 넣는다.
- 지금 쓰는 신호: `hook-events.jsonl`, `verify-report.md`의 Run 회차, PR 리뷰 수정 요청 수.
- eval: `evals/`. 병합된 이슈가 쌓이면 과제를 채운다.

## 열린 항목 (Phase 0 통과 기준)

- [ ] **Testcontainers와 sandbox**: Docker 소켓 접근이 sandbox와 충돌한다. 선택지: (a) `sandbox.network.allowUnixSockets`에 Docker 소켓 추가 + `allowLocalBinding`, (b) Testcontainers 테스트를 별도 태스크(`integrationTest`)로 나눠 CI에서만, (c) `excludedCommands`에 `./gradlew *`. W1 스캐폴드 때 실제로 돌려 보고 정한다.
- [ ] **sandbox에서 Gradle·gh·git push 동작 확인**: `~/.gradle` 쓰기는 `allowWrite`로 열었다. `gh`(키체인 토큰)와 SSH push(`~/.ssh` denyRead)는 sandbox에서 실패할 수 있어 `excludedCommands`로 뺐다. 실제 동작을 확인한다. 확인 결과(2026-10-25): `excludedCommands`를 비운 뒤로 sandbox 안의 `gh`는 `~/.config/gh/config.yml: operation not permitted`로 실패한다(`Read(~/.config/gh/**)` deny가 sandbox denyRead에 반영됨). `/intent`·`/issue`가 쓰는 gh 하위 명령만 `excludedCommands`에 좁게 다시 넣는 안을 제안했다.
- [ ] **브랜치 보호**(사람이 GitHub에서 설정): `main`, `develop`에 PR 필수, `harness` 체크 필수, Code Owners 리뷰, force push 금지. 1인 저장소라 "승인 1명 이상"은 본인 PR에 적용할 수 없으므로 켜지 않는다.
- [ ] `spec-approved` 라벨을 저장소에 만든다.

## 설계 문서와 다른 점

| 설계 문서 | Gatehouse | 이유 |
| --- | --- | --- |
| rules 4개: kotlin-webflux, go, kafka-events, payment-domain | gateway-reactive, secrets-and-identity, kafka-events, admin-api-schema | Go 없음. 결제 도메인 대신 인증 도메인 규칙 |
| scan-secrets의 Luhn 카드번호 검사 | 없음 | 카드 데이터를 다루지 않는다 |
| `/plan`, `/verify` | `/work-plan`, `/work-verify` | 내장 명령과 이름이 겹친다. 같은 이름이면 프로젝트 skill이 내장 명령을 가린다 |
| spec PR과 구현 PR 2개, 필수 리뷰 1인 | PR 1개(draft), spec 승인은 `spec-approved` 라벨 | 1인 개발. GitHub에서는 본인 PR을 승인할 수 없다 |
| `.claudeignore` | 쓰지 않음 | 공식 지원이 없다. `Read` deny와 sandbox `denyRead`로 대체 |
| hook 7개 | 7개 + `record-test.sh`, `verifier-bash.sh` | Bash tool_response에 exit code가 없어 테스트 결과를 따로 기록. subagent `tools`는 Bash를 패턴으로 제한할 수 없음 |
| OTel → Prometheus·Grafana | 보류 | 관측 스택 없음 |
