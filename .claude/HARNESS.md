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
| `guard-bash.sh` | PreToolUse Bash | 파괴적 삭제, force push, `--no-verify`·hooksPath로 gitleaks 우회, 운영 도구, 비밀 파일 열람, 셸로 하네스 변조, allowlist 밖 네트워크, `spec-approved` 라벨 자가 부여(이슈 생성 포함), 이슈 삭제·이전. 네트워크 허용 호스트는 `settings.json`의 `sandbox.network.allowedDomains`에서 읽는다(목록을 hook에 따로 두지 않는다) | 설계 #1, gitleaks pre-push 보호. 관측: 차단 14건(10/25~10/31) | 없음 |
| `guard-paths.sh` | PreToolUse Edit\|Write | 하네스·보안 경계 파일 수정, 커밋된 Flyway 마이그레이션 수정, 메인 체크아웃에서의 파일 변경 | 설계 #2, plan §2.7, 2026-10-25 develop에 의도치 않은 `init` 커밋(아래 worktree 규칙) | 없음 |
| `scan-secrets.sh` | PostToolUse Edit\|Write | 비밀값이 push 직전에야 발견됨 | 설계 #3, NFR-09 | 6개월간 차단 0회면 pre-push만 남기는 것을 검토 |
| `fast-check.sh` | PostToolUse Edit\|Write | 문법·포맷 오류, Gateway 블로킹 호출이 늦게 발견됨 | 설계 #4, NFR-11 | BlockHound 도입 후 블로킹 grep 제거. ktlint는 Gradle 플러그인 도입 시 재검토 |
| `record-test.sh` + `verify-gate.sh` | PostToolUse Bash + Stop | 테스트 없이·실패한 채로 "완료" 보고. 전체 실행(`./gradlew test\|check\|build`)의 통과만 인정한다. 모듈 단위·`--tests` 실행은 `scope: partial`로 기록하고 통과로 치지 않는다. 거부 사유는 경우별로 다르다(기록 없음, 실패, 일부만 통과, 출력에서 결과를 못 읽음) | 설계 #5. 관측: 거부 7건, 포기 2건(아래 "2026-10-31 verify-gate") | eval에서 `no-verify-gate` 변형과 통과율 차이가 없으면 제거 |
| `load-context.sh` | SessionStart | 재개·압축 뒤 이슈·단계를 잃음. 메인 체크아웃이면 worktree 규칙과 이어갈 worktree 목록 안내. worktree 안이면 `work-status.sh --no-gh` 출력을 그대로 넣는다 | 설계 #6 | 없음(비용 거의 없음) |
| `work-status.sh` | hook 아님. `load-context.sh`와 skill 머리말이 호출 | 단계 판정이 여러 곳에 따로 있어 서로 다른 "다음 단계"를 안내함. worktree의 하네스 사본이 develop보다 낡았거나 커밋 안 된 수정이 있으면 경고 | 관측: issue-1에서 spec-review REVISE + plan.md 있음 상태를 `load-context.sh`와 `/work` 표가 다르게 읽음 | 없음 |
| `guard-config.sh` | ConfigChange | 세션 중 hook 비활성화·권한 완화 | 설계 #7 | 없음 |
| `verifier-bash.sh` | verifier 전용 PreToolUse Bash | 검증자가 코드를 고쳐 통과시킴 | 설계 Layer 4 (subagent `tools`로는 Bash 패턴 제한 불가) | 없음 |

차단·경고 기록: 메인 체크아웃의 `.claude/state/hook-events.jsonl`(gitignore). worktree 안에서 시작한 세션의 기록도 여기에 쌓인다(`_lib.sh`가 git common dir 기준으로 잡는다). 월간 점검 때 `jq -s 'group_by(.hook) | map({hook: .[0].hook, n: length})'`로 집계한다.

git hook(`.githooks/`, `git config core.hooksPath .githooks`로 활성화):

| hook | 막는 실패 | 근거 | 제거 조건 |
| --- | --- | --- | --- |
| `pre-push` | 비밀값이 든 커밋의 push | NFR-09 | 없음 |
| `pre-commit` | Claude Code 세션(`CLAUDECODE=1`)이 메인 체크아웃에 커밋. `guard-bash.sh`가 못 보는 스크립트 안의 커밋과 `git -C <메인> commit`까지 잡는다. 사람의 터미널 커밋은 통과 | 2026-10-25 사고(아래 worktree 규칙)는 스크립트가 실행한 커밋이었다 | 없음 |

### 관측 기록 (2026-10-25 ~ 2026-10-31, `hook-events.jsonl` 38건)

| hook | 건수 | 내용 |
| --- | --- | --- |
| `guard-bash` block | 14 | 보호 브랜치 push 2, 하네스 파일 변조 3, 비밀 파일 접근 2, PR 병합 1, allowlist 밖 호출 4(start.spring.io, spring.io, kotlinlang.org, json.schemastore.org. 모두 W1 버전 조사), 재귀 삭제 오탐 2(조각 단위 판정으로 고침) |
| `guard-paths` ask | 14 | 모두 하네스를 고치던 세션 한 번 |
| `verify-gate` block / give-up | 7 / 2 | 아래 |
| `fast-check` block | 1 | scratchpad의 셸 스크립트 |
| `scan-secrets` | 0 | 코드가 아직 없다 |

**2026-10-31 verify-gate.** issue-1(W1 스캐폴드)에서 에이전트가 `./gradlew check 2>&1 | grep … | head -5`로 출력을 잘랐다. `record-test.sh`가 `BUILD SUCCESSFUL` 줄을 찾지 못해 `result: unknown`으로 기록했고, gate는 "통과한 테스트 기록이 없습니다"라는 사유로 3번 막은 뒤 포기했다. 같은 일이 두 번 반복됐다. 원인은 둘이다. 거부 사유가 실제 원인(출력에서 결과를 못 읽음)을 말하지 않았고, gate 메시지가 권한 `./gradlew :<모듈>:check`는 `record-test.sh`가 아예 기록하지 않았다. 고친 것: 사유를 경우별로 나누고, 모듈 단위 실행은 `partial`로 기록하되 통과로 치지 않고, 메시지와 `/implement`에 "전체 실행을 `tail`로"를 적었다.

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
| `/work <이슈> [--step]` | 이슈 worktree로 이동(없으면 생성) 후 다음 사람 승인 지점까지 아래 단계를 이어서 실행 | 근거 `예상`(단계별 호출을 손으로 이어 붙임). 승인 지점에서 항상 멈춤. 사람 지점이 자주 무시되면 제거하고 단계별 호출로 돌아감. 단계 판정은 `hooks/work-status.sh`가 한다(skill의 표는 그 순서의 설명) |
| `/intent <이슈>` | 이슈 → INTENT.md | 이슈 worktree(`.claude/worktrees/issue-<이슈>`, 브랜치 `worktree-issue-<이슈>`)에서. 없으면 EnterWorktree로 만듦 |
| `/spec` | spec.md + spec-reviewer + draft PR | **사람 승인 1**: PR에 `spec-approved` 라벨. 2회 검토 뒤에도 REVISE인데 사람이 그대로 가기로 하면 spec.md의 `## 검토 후 남긴 항목`에 결정을 적는다(issue-1에서 REVISE인 채 진행했는데 기록할 곳이 없었다). 라벨이 있으면 REVISE여도 진행한다 |
| `/work-plan` | plan.md 태스크 분해 | 내장 `/plan`과 이름이 겹쳐 `work-plan`으로 둠. plan.md 머리의 `Spec: ./spec.md @ <커밋>`으로 승인된 spec 버전을 고정한다. 그 뒤 spec.md가 바뀌면 verifier가 보고서에 적고 `/ship`이 재승인을 요청한다(근거 `예상`: 라벨은 PR에 붙어 spec 변경을 따라가지 못한다) |
| `/implement` | 태스크별 테스트 먼저 → 구현 → 커밋 | 긴 실행은 `/goal` |
| `/work-verify` | verifier 호출, verify-report.md | 내장 `/verify`와 이름이 겹쳐 `work-verify`로 둠. FAIL 3회 초과 시 사람에게 |
| `/ship` | ADR, PR 본문, `gh pr ready` | `disable-model-invocation: true`. **사람 승인 2**: PR 병합 |
| `/adr <주제>` | ADR 작성 | CLAUDE.md의 "열린 항목은 ADR로" 규칙 |

두지 않은 것: `kafka-event-catalog`, `api-drift`(문서화할 이벤트·API가 아직 없다. W3 이후 실제 drift가 관찰되면 추가).

### worktree 규칙

변경 작업은 모두 git worktree에서 한다. 메인 체크아웃은 읽기 전용이다.

- 이슈 작업은 `EnterWorktree name: issue-<번호>`, 그 밖의 변경은 `name: task-<짧은-이름>`으로 만든다. 이미 있으면 `path`로 들어간다. `/work`, `/intent`는 이를 자동으로 한다.
- 강제: `guard-paths.sh`는 메인 체크아웃 파일의 Edit·Write를 거부하고, `guard-bash.sh`는 메인 체크아웃의 commit·merge·rebase·브랜치 생성을 거부한다. `.githooks/pre-commit`은 세션에서 시작된 메인 체크아웃 커밋을 경로와 상관없이(스크립트 안 포함) 거부한다. CLAUDE.md에 규칙을 적은 이유는 EnterWorktree 도구가 사용자나 CLAUDE.md의 지시가 있을 때만 쓰이기 때문이다.
- worktree의 하네스 사본: worktree는 분기 시점의 `.claude/hooks`·`settings.json`을 갖는다. 메인 체크아웃에서 시작해 EnterWorktree로 들어간 세션은 메인의 하네스를 쓰고, worktree 안에서 시작한 세션은 그 worktree의 사본을 쓴다. 그래서 develop의 하네스 수정은 worktree에 병합해야 반영되고, worktree에서 고친 `settings.json`은 메인에서 시작한 세션에 적용되지 않는다. `work-status.sh`가 두 경우를 경고한다.
- 근거: 2026-10-25 hook 테스트 스크립트가 sandbox의 `mktemp` 실패를 무시하고 메인 체크아웃에서 `git add -A && git commit -m init`을 실행해 develop에 커밋을 만들었다(두 번 발생, 두 번째는 push됨). 사용자 요청.
- 전제: worktree 기본 base는 `origin/<기본 브랜치>`다. 로컬 `origin/HEAD`가 develop을 가리켜야 한다(`git remote set-head origin develop`). `/work`는 새 worktree가 develop 기반인지 확인한다.
- 사람은 hook의 대상이 아니다. 하네스 파일(hooks, settings)은 사람이 메인 체크아웃에서 직접 고친다.
- 제거 조건: 없음.

## Layer 6 · 외부 연결 (`.github/`)

| 구성요소 | 역할 | 비고 |
| --- | --- | --- |
| `workflows/harness.yml` | `.claude/` 변경 시 shellcheck(`.githooks/` 포함) + hook 테스트 + `settings.json` 검사(JSON 문법, 경로를 키 하나로 적은 실수) | Phase 0 통과 기준. 키 검사 근거: issue-1 worktree에서 `"sandbox.network.allowLocalBinding"`을 키로 적어 무시된 수정 |
| `workflows/claude-intent.yml` | 이슈 코멘트 `@claude` → INTENT 초안 코멘트 | `ANTHROPIC_API_KEY` secret 필요. 저장소 소유자 코멘트만 반응 |
| `CODEOWNERS` | `.claude/`, `.githooks/`, `.github/`, gitleaks 설정, CLAUDE.md | 브랜치 보호에서 Code Owners 리뷰를 켜야 효과가 있음 |

GitHub 연동은 `gh` CLI만 쓴다(MCP 없음). 문서 정원 관리 예약 작업은 문서화할 대상이 생긴 뒤(W3 이후) 추가한다.

## Layer 7 · 관측과 평가

- 텔레메트리(OTel): 관측 스택이 없어(plan Context) 보류. Gatehouse 지표 파이프라인과 별개로, 외부 관측 스택이 생기면 `settings.json`의 `env`에 OTel 설정을 넣는다.
- 지금 쓰는 신호: `hook-events.jsonl`, `verify-report.md`의 Run 회차, PR 리뷰 수정 요청 수.
- eval: `evals/`. 병합된 이슈가 쌓이면 과제를 채운다.

## 열린 항목 (Phase 0 통과 기준)

- [ ] **Testcontainers와 sandbox**: Docker 소켓 접근이 sandbox와 충돌한다. 선택지: (a) `sandbox.network.allowUnixSockets`에 Docker 소켓 추가 + `allowLocalBinding`, (b) Testcontainers 테스트를 별도 태스크(`integrationTest`)로 나눠 CI에서만, (c) `excludedCommands`에 `./gradlew *`. W1 스캐폴드 때 실제로 돌려 보고 정한다.
- [ ] **sandbox에서 Gradle·gh·git push 동작 확인**: `~/.gradle` 쓰기는 `allowWrite`로 열었다. `gh`(키체인 토큰)와 SSH push(`~/.ssh` denyRead)는 sandbox에서 실패할 수 있어 `excludedCommands`로 뺐다. 실제 동작을 확인한다. 확인 결과(2026-10-25): `excludedCommands`를 비운 뒤로 sandbox 안의 `gh`는 `~/.config/gh/config.yml: operation not permitted`로 실패한다(`Read(~/.config/gh/**)` deny가 sandbox denyRead에 반영됨). `/intent`·`/issue`가 쓰는 gh 하위 명령만 `excludedCommands`에 좁게 다시 넣는 안을 제안했다. 재확인(2026-11-16): 지금 `settings.json`에는 `Read(~/.config/gh/**)` allow가 있지만 sandbox 안의 `gh`는 여전히 실패한다. 원인은 둘이다. (1) 원격이 SSH 별칭(`git@chris:`)인데 `~/.ssh`가 읽기 금지라 `gh`가 저장소를 찾지 못한다(`none of the git remotes … point to a known GitHub host`). `GH_REPO=atlas-han/gatehouse`로 넘어갈 수 있다. (2) 그래도 TLS 검증이 실패한다(`x509: OSStatus -26276`). 그래서 `/intent`·`/issue`·`/work`·`/work-plan`의 `gh` 조회가 모두 실패하고, `work-status.sh`는 승인 여부를 `unknown`으로 낸다. 결정(2026-11-16, 사용자): `gh`는 읽기·쓰기 모두 sandbox 밖에서 실행한다. `excludedCommands: ["gh *"]`, `env.GH_REPO`. 쓰기 명령은 여전히 permissions `ask`를 거치고, `gh pr merge`·`spec-approved` 라벨·`gh api DELETE/PUT`은 `guard-bash.sh`가 막는다. 남은 확인: 적용 뒤 새 세션에서 `gh pr view worktree-issue-1 --json labels`가 성공하는지, `git push`(SSH 별칭, sandbox 안)가 되는지.
- [x] **`sandbox.network.allowLocalBinding`**: `settings.json`의 `sandbox.network` 아래에 넣었다(2026-11-16). issue-1 worktree에는 `sandbox` 아래 문자열 키로 잘못 넣은 수정이 커밋 안 된 채 있었고, 효과가 없어 되돌린다.
- [ ] **문서 사이트 조회**: W1 버전 조사에서 `curl`이 4번 막혔다. spring.io·kotlinlang.org를 `allowedDomains`에 넣을지, WebFetch로만 볼지 정한다. 지금 차단 메시지는 WebFetch를 안내한다.
- [ ] **eval 변형이 구성요소를 실제로 빼는지 확인**: hook 설정은 여러 출처가 합쳐진다. `--settings`로 준 `"Stop": []`가 프로젝트의 Stop hook을 끄는지 확인되지 않았다. 꺼지지 않으면 hook이 읽는 환경 변수 스위치로 바꾼다.
- [ ] **eval이 과거 하네스를 측정한다**: `evals/run.sh`는 과제를 `base_ref` worktree에서 돌리므로 `.claude/`도 그 시점 것이다. 현재 하네스를 재려면 worktree에 현재 `.claude/`를 덮어써야 한다. 과제를 처음 채울 때 고친다.
- [ ] `JAVA_HOME`: 세션이 Gradle 명령마다 `export JAVA_HOME=…`을 붙이고 있다. `settings.local.json`의 `env`에 둔다(기기마다 다르므로 커밋하지 않는다).
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
| hook 7개 | 7개 + `record-test.sh`, `verifier-bash.sh`, `work-status.sh`(hook 아님), git `pre-commit` | Bash tool_response에 exit code가 없어 테스트 결과를 따로 기록. subagent `tools`는 Bash를 패턴으로 제한할 수 없음. 단계 판정을 한곳에 둠. 스크립트 안의 커밋은 Claude Code hook이 못 봄 |
| OTel → Prometheus·Grafana | 보류 | 관측 스택 없음 |
