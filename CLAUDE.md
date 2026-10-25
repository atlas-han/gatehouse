# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

Gatehouse centralizes service-to-service (East-West) authentication for an internal MSA. It has three parts: an API Gateway, an auth server, and an Admin Tool. The repo has **no code yet**. It holds docs only:

- `docs/prd/MSA API Gateway·인증서버·Admin Tool 요구사항 명세 (초안).md`: the requirements (PRD draft). It's in Korean.
- `docs/plan/development-plan.md`: the implementation plan, schedule, and design decisions. It's in Korean.

Read both before designing or scaffolding anything. Requirement IDs in code, commits, and ADRs follow the PRD: `GW-xx` (gateway), `AS-xx` (auth server), `AD-xx` (admin), `NFR-xx` (non-functional), `D-xx` (confirmed decisions, PRD §8). Open questions are in PRD §9 and plan §4. Don't silently resolve them in code. Record the decision in an ADR under `docs/adr/`.

## Setup

```sh
git config core.hooksPath .githooks   # enables the gitleaks pre-push hook (requires `brew install gitleaks`)
```

The pre-push hook scans only the commits being pushed and blocks the push if it finds a secret. For a false positive, add a `gitleaks:allow` comment on the line or add the fingerprint to `.gitleaksignore`.

Planned build entry point (from W1 of the plan): `./gradlew build`, with local infra (MySQL, Redis, Kafka KRaft) started via `deploy/docker-compose.yml`.

## Planned architecture (plan §1–2)

Kotlin + Gradle (Kotlin DSL) multi-module monorepo. Java 25 toolchain, Spring Boot 4.x, and Spring Security 7, which now includes the Authorization Server. Versions go in `gradle/libs.versions.toml`, and shared build config goes in `build-logic/` convention plugins.

| Module | Role |
| --- | --- |
| `gatehouse-common` | No Spring dependency. AuthMethod/AuthLevel, header constants, config snapshot DTOs, event schemas, `SecretDigester` (HMAC-SHA256 with constant-time compare), CIDR matcher |
| `gatehouse-gateway` | Spring Cloud Gateway (WebFlux). Uses custom `GlobalFilter`s, not Spring Security |
| `gatehouse-auth` | Authorization Server: `client_credentials` and JWKS (Phase 1); OIDC provider in front of Google SSO (Phase 2) |
| `gatehouse-admin-api` | Spring MVC + JPA + Flyway. **Owns the DB schema** and emits config changes through an outbox |
| `gatehouse-console/bff`, `/web` | Phase 2. Spring BFF (oauth2Login, Redis session, token relay) plus a SvelteKit SPA. No tokens in the browser |

Cross-cutting rules that span modules:

- **Gateway hot path is Reactor-style.** It never queries the DB and never uses coroutine bridges (`mono {}`). The MVC services use virtual threads.
- **Gateway filter order follows PRD §3:** route match → client identification (normalize `X-Client-ID`/`Client-ID`; a header that conflicts with the token is rejected) → IP verification (trusted-proxy XFF walk, right to left) → authentication (one `CredentialVerifier` per `AuthMethod`) → route authorization (`minAuthLevel`: IDENTIFIED < LEGACY < AUTHENTICATED) → rate limit → identity header normalization (strip incoming identity and secret headers, inject the verified `X-Client-Id`/`X-Auth-Method`).
- **Per-route `enforcementMode`:** `MONITOR` logs and records metrics without rejecting. `ENFORCE` rejects. Rejections return a uniform JSON body `{code, message, requestId}` with no detailed cause.
- **Config propagation is notify-then-pull.** admin-api bumps `config_version` and writes the outbox in the same transaction. The outbox publishes to Kafka `gatehouse.config.changed`. The gateway pulls the full `GET /internal/config/snapshot` and swaps it in atomically. It also runs a 5-minute version check as a fallback. Readiness stays down until the first snapshot arrives. After that, the gateway keeps serving the last snapshot if Kafka or admin-api is down.
- **Secrets** are 256-bit random values, shown once. Only `HMAC-SHA256(pepper[keyVersion], secret)` is stored, never bcrypt, because of the 20k TPS budget. Logs and UI show only the 4-character prefix.
- **Degraded modes:** JWKS is stale-on-error, and unknown `kid` triggers a rate-limited refresh. Public JWKS is also included in the config snapshot. Redis (revocation list + rate limit) sits behind a short timeout and a circuit breaker and **fails open**, with a `gatehouse_redis_degraded` gauge.
- **Metrics have no external observability stack.** The gateway aggregates per minute and publishes to Kafka `gatehouse.usage.minutely`. admin-api upserts the counts into `api_usage_minute` and `auth_failure_minute`. Metric labels use the route template ID only, and unknown client IDs collapse to `UNKNOWN`.

Testing stack: JUnit5, Kotest assertions, MockK, Testcontainers (MySQL/Redis/Kafka), WireMock, k6 (`loadtest/`), and Playwright (Phase 2). Gateway filters are unit-tested with `MockServerWebExchange`.

## Secrets hygiene

`.gitignore` already excludes `application-local*`, `application-secret*`, `.env*` (except `.env.example`), key and keystore files, and `credentials*.json`/`client_secret*.json`. Put local credentials in those files, not in tracked config.

## Claude Code harness

The project harness lives in `.claude/`. `.claude/HARNESS.md` records why each part exists and when to remove it. Hooks, settings, gitleaks config, and CODEOWNERS are human-edited only, and the guard hooks block agent edits. To change one, propose the diff instead.

Issue workflow (state lives in `docs/work/<issue>/`, see its README):
`/issue` (creates the issue; `--plan W<n>` splits a plan week) → `/work <n>` runs the stages below up to the next human gate: `/intent <n>` → `/spec` → human adds `spec-approved` label → `/work-plan` → `/implement` ⇄ `/work-verify` → `/ship` (human-invoked) → human merges.

- **All changes happen in a git worktree.** The main checkout is read-only. Before you edit, write, or commit anything in the repo, use the EnterWorktree tool: `name: issue-<n>` for issue work, `name: task-<short-name>` for anything else. If `.claude/worktrees/<name>` already exists, pass it as `path` instead. Read-only work (questions, review, research) stays in the main checkout. The guard hooks deny edits and commits in the main checkout.
- Before stopping, if code changed, `./gradlew check` must pass. The Stop hook enforces this.
- Path-scoped rules in `.claude/rules/` load automatically when you touch matching files.
- Hook tests: `bash .claude/hooks/tests/run.sh`.

## Tooling note

`graft/` (a code-index tool) is gitignored but re-admitted for search through `.ignore`. Don't commit it.
