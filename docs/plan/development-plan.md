# Gatehouse 개발 계획 (PRD 초안 2026-10-16 기준)

## Context

지금 서비스 간 인증은 IP allowlist가 중심이고 서비스마다 구현이 달라서, 누가 호출했는지 식별할 수 없다. [PRD](<../prd/MSA API Gateway·인증서버·Admin Tool 요구사항 명세 (초안).md>)는 이 인증을 **Gateway + 인증서버 + Admin Tool**로 일원화한다. 목표는 네 가지다. 인증 일원화, 호출자 식별, 배포 없는 정책 변경, 감사 가능성.

저장소는 아직 비어 있다(PRD, .gitignore, gitleaks pre-push hook뿐). 이 계획은 처음부터 새로 세운다.

**확정된 전제 (사용자 답변)**
- MVP는 **2단계로 나눈다**. Phase 1(5주)은 S2S 경로(Gateway, 인증서버의 토큰 기능, 관리 API)를 만들고 운영은 API로 한다. Phase 2(3주)는 Google SSO, BFF, Console UI, 승인 워크플로를 만든다.
- **Kotlin + Gradle(Kotlin DSL) 멀티모듈 모노레포**로 간다.
- 관측 스택이 아직 없다. 그래서 AD-12 지표와 인증 실패 기록은 **자체 경로(Gateway → Kafka → 관리 API → MySQL 롤업)**로 만든다. Micrometer `/actuator/prometheus`는 나중을 위해 열어 둔다.

일정은 2026-10-26(월)부터 2026-12-18(금)까지 8주다.

---

## 1. 저장소 구조

```
settings.gradle.kts, gradle/libs.versions.toml
build-logic/                 # convention plugin: kotlin-library, kotlin-spring-boot
gatehouse-common/            # Spring 비의존: AuthMethod, AuthLevel, 헤더 상수, 설정 스냅샷 DTO,
                             #   이벤트 스키마, SecretDigester(HMAC-SHA256 + 상수 시간 비교), CIDR 매처
gatehouse-gateway/           # Spring Cloud Gateway Server WebFlux
gatehouse-auth/              # Spring Security 7 내장 Authorization Server
gatehouse-admin-api/         # Spring MVC + Spring Data JPA + Flyway (스키마 소유자)
gatehouse-console/bff/       # Spring Boot, oauth2Login, Spring Session(Redis), web 정적 자원 서빙
gatehouse-console/web/       # SvelteKit (adapter-static, SPA)
deploy/                      # docker-compose(MySQL, Redis, Kafka KRaft), Helm chart
loadtest/                    # k6 시나리오
docs/adr/                    # 주요 결정 기록
```

- 스택: Java 25 LTS 툴체인과 최신 GA Spring Boot 4.x, 그리고 이에 맞는 Spring Cloud 릴리스 트레인을 쓴다. 정확한 버전은 W1에 호환 매트릭스를 보고 고정한다. Spring Boot 4부터 Authorization Server가 Spring Security 7로 통합됐다.
- Gateway의 요청 경로는 **Reactor 스타일**로 쓴다(NFR-11). 코루틴 브리지(`mono {}`)는 hot path에 쓰지 않는다. 관리 API와 BFF는 MVC에 virtual threads를 켠다.
- 테스트는 JUnit5, Kotest assertions, MockK, Testcontainers(MySQL/Redis/Kafka), WireMock(다운스트림 대역)로 한다.

## 2. 핵심 설계 (PRD를 구현 수준으로 구체화)

### 2.1 Gateway 필터 체인 (PRD §3 처리 순서)
SCG가 라우트를 매칭(1단계)한 뒤 `GlobalFilter`를 순서대로 실행한다. Gateway에는 Spring Security를 넣지 않고 직접 만든 필터를 쓴다.

| 순서 | 필터 | 핵심 |
| --- | --- | --- |
| 2 | `ClientIdentificationFilter` | `X-Client-ID`와 `Client-ID`를 정규화하고, 값이 서로 다르면 400(GW-17). Bearer 토큰이 있으면 **서명 검증 전에** 파싱해서 `client_id`를 얻는다. 헤더 값이 토큰 값과 다르면 거부한다. 레거시 키는 어댑터가 digest로 클라이언트를 찾는다. 찾은 ID로 메모리 캐시를 조회하고, 미등록이거나 비활성이면 401(GW-03) |
| 3 | `IpVerificationFilter` | 신뢰 프록시 CIDR 목록을 기준으로 XFF를 오른쪽부터 따라가 실제 IP를 정한다(NFR-10). 클라이언트에 CIDR이 등록돼 있을 때만 검사한다(GW-04) |
| 4 | `AuthenticationFilter` | `AuthMethod`마다 `CredentialVerifier`로 분기한다. `CLIENT_ID_ONLY`는 내부 진입 경로인지만 본다. `CLIENT_SECRET`은 활성 Secret(최대 2개) digest와 상수 시간으로 비교한다. `JWT`는 서명·만료·aud를 보고 Redis 폐기 목록을 확인한다. `LEGACY_API_KEY`는 플러그인에 맡긴다 |
| 5 | `RouteAuthorizationFilter` | 라우트의 허용 클라이언트와 `minAuthLevel`을 검사한다. 레벨은 IDENTIFIED(ID_ONLY) < LEGACY < AUTHENTICATED(SECRET/JWT)로 둔다 |
| 6 | Rate limit | SCG `RedisRateLimiter`를 쓰고 KeyResolver는 clientId, 한도는 클라이언트 설정에서 가져온다 |
| 7 | `IdentityHeaderNormalizationFilter` | 두 형식의 신원 헤더와 `X-Client-Secret`, 레거시 키 헤더, 외부에서 온 `X-Auth-Method`를 지우고, 검증된 `X-Client-Id`, `X-Auth-Method`를 넣는다 |

- **라우트별 `enforcementMode`를 `MONITOR`/`ENFORCE`로 둔다.** MONITOR에서는 거부할 요청도 통과시키고 지표와 로그만 남긴다. 기존 호출을 깨지 않고 전환할 수 있게 하는 장치이고, 1인 운영에서 롤아웃 위험을 줄이는 핵심이다.
- 거부 응답은 JSON `{code, message, requestId}` 형식으로 통일하고 상세 원인은 노출하지 않는다.
- 라우트는 메모리 설정에 기반한 커스텀 `RouteDefinitionLocator`로 만들고, 설정이 바뀌면 `RefreshRoutesEvent`를 발행한다(GW-01, GW-11).
- JWT 서명은 **RS256**으로 한다. 요청마다 검증해야 하는 부하에서는 RSA 검증이 ES256보다 빠르다. 검증에는 Nimbus를 직접 쓴다.

### 2.2 설정 전파 (GW-11, AD-10, NFR-08)
- 관리 API가 변경을 확정하는 트랜잭션 안에서 `config_version`을 올리고 **outbox**에 기록한다. 퍼블리셔가 이를 Kafka `gatehouse.config.changed`로 보낸다. 페이로드는 `{version, entityType, entityId}`다.
- Gateway는 **notify-then-pull**로 동작한다. 이벤트를 받거나, 5분마다 하는 주기적 버전 비교에서 차이가 나면 관리 API `GET /internal/config/snapshot`으로 전체 스냅샷을 받아 원자적으로 교체한다. 설정이 작아서(클라이언트와 라우트가 수백 개 규모) 전체 교체가 가장 단순하고, 순서가 뒤바뀌거나 이벤트가 빠지는 문제가 생기지 않는다.
- 기동 시 스냅샷을 받기 전까지는 readiness를 내린다. Kafka나 관리 API가 장애일 때는 마지막 스냅샷으로 계속 동작한다.
- 스냅샷에는 Secret digest가 들어간다. 그래서 내부 전용 경로 + NetworkPolicy + 서비스 토큰으로 보호한다.

### 2.3 Secret과 HMAC (AD-04/05, AS-02, NFR-09)
- Secret은 서버가 256비트 랜덤으로 만들고 응답에서 한 번만 보여 준다. 저장하는 값은 `HMAC-SHA256(pepper[keyVersion], secret)`이다.
- Secret 엔트로피가 높으므로 bcrypt 같은 느린 해시는 필요 없다. 20k TPS에서 요청마다 검증하려면 HMAC이어야 한다.
- pepper는 K8s Secret(또는 AWS Secrets Manager)에 두고 admin-api, auth, gateway가 공유한다. `keyVersion` 컬럼을 두어 로테이션에 대비한다.
- 로그와 화면에는 prefix 4자리만 남긴다.

### 2.4 인증서버
- **Phase 1**(AS-01~05)
  - `client_credentials`: 커스텀 `RegisteredClientRepository`가 MySQL을 읽기 전용으로 조회한다. 짧은 Caffeine 캐시를 붙여 비활성 클라이언트가 바로 반영되게 한다. Secret 검증은 HMAC `PasswordEncoder`로 한다.
  - TTL은 클라이언트 값이 없으면 24h, 상한도 24h다(D-28).
  - JWKS는 서명 키를 DB(개인키 암호화 저장)에서 관리한다. ACTIVE 키 1개와 RETIRED 키를 함께 공개하고 로테이션 잡을 둔다.
  - 폐기는 `/oauth2/revoke`에서 `revoked:jti:{jti}`를 Redis에 저장하고, TTL을 토큰의 남은 만료 시간으로 잡는다.
- **Phase 2**(AS-06~08)
  - 인증서버가 BFF 앞에서 OIDC Provider로 동작하고, 사용자 로그인은 `oauth2Login`으로 Google에 넘긴다.
  - 커스텀 `OidcUserService`가 `hd`와 `email_verified`를 검증한다.
  - 이메일–역할 매핑과 `gatehouse.auth.bootstrap-admins` 설정을 보고 `OAuth2TokenCustomizer`가 roles 클레임을 넣는다.

### 2.5 Gateway의 JWKS와 Redis 장애 대응 (GW-15/16/18, NFR-03/06/07)
- JWKS는 주기적으로 갱신하고, 모르는 `kid`가 오면 한 번 더 갱신한다. 이 재갱신에는 속도 제한을 둔다. 갱신이 실패하면 **이전 키를 계속 쓴다(stale-on-error)**.
- 인증서버 장애 중에 Gateway가 재시작하는 경우에 대비해, 공개 JWKS를 설정 스냅샷에도 넣는다. auth가 공개키를 공유 DB에 쓰면 admin-api가 스냅샷에 포함한다.
- 폐기 목록은 요청마다 reactive Lettuce로 `GET`한다. 타임아웃은 짧게(약 20ms) 잡고 Resilience4j 서킷브레이커를 붙인다.
- 서킷이 열리면 폐기 목록 확인과 rate limit을 건너뛴다(fail-open). 이때 `gatehouse_redis_degraded` gauge를 올리고 진입·복구 로그를 WARN으로 남긴다.
- W5 부하 테스트에서 지연 예산을 넘으면 폐기 목록을 로컬 메모리 집합으로 바꾸는 안으로 전환한다. Redis pub/sub으로 동기화하는 방식이다.

### 2.6 지표와 인증 실패 기록 (GW-12/13/14, AD-12, NFR-12/13; 관측 스택 없음)
- Gateway는 메모리에서 분 단위로 `(clientId, routeId, authMethod, outcome)` 카운트와 지연 히스토그램을 집계해 Kafka `gatehouse.usage.minutely`로 보낸다.
  - outcome은 `SUCCESS | AUTH_REJECTED | CLIENT_4XX | SERVER_5XX`다.
  - 라벨은 라우트 템플릿 ID만 쓴다. 미등록 ID는 `UNKNOWN`으로 묶는다.
- 인증 실패는 `(분, clientId|UNKNOWN, reason, sourceIp, routeId)` 단위로 묶어서 count와 샘플 1건만 보낸다. 공격 상황에서도 저장량이 일정 범위를 넘지 않게 하려는 것이다.
- admin-api는 위 데이터를 `api_usage_minute`와 `auth_failure_minute`에 upsert한다. 테이블은 일 단위 파티션이고 보존 기간은 1개월이다(PCI 범위가 확인되면 12개월로 바꿀 수 있게 설정값으로 둔다).
- 원본 요청 로그는 JSON stdout으로 남기고 Logback AsyncAppender를 쓴다. Micrometer `/actuator/prometheus`도 열어 둔다.

### 2.7 관리 API와 데이터 모델 (Flyway V1)
`client`(client_id, name, owner_team, auth_method, status, token_ttl_sec, rate_limit_rps, legacy_sunset_date, version), `client_secret`(digest, key_version, prefix, status, created/revoked_at), `client_ip_cidr`, `legacy_credential`(scheme, digest), `route`(route_key, path_pattern, methods, target_uri, min_auth_level, enforcement_mode), `route_allowed_client`, `admin_role_mapping`, `change_request`(Phase 2), `audit_log`(actor, action, target, before/after JSON, approver, change_request_id), `outbox`, `config_version`, `signing_key`(auth), `api_usage_minute`, `auth_failure_minute`.

- Phase 1에서 admin-api는 인증서버가 발급한 JWT(ops 클라이언트, `gatehouse.admin` scope)로 보호하고, 감사 로그의 actor에는 ops 클라이언트 ID를 남긴다. 민감 변경은 바로 반영되지만 감사 로그에는 남는다. 이 기간에는 운영자가 개발자 1명뿐이라 감수할 수 있는 위험으로 본다.
- Phase 2에서는 민감 변경(IP, 인증 방식, 라우트 허용 클라이언트, 역할)이 `change_request PENDING`으로 들어간다. **요청자가 아닌** ADMIN이 승인하면 하나의 트랜잭션으로 반영, 감사 로그 기록, outbox 기록까지 한다(AD-08/09/10).

### 2.8 Console (Phase 2)
- BFF는 인증서버에 대해 `oauth2Login`을 하고, 세션은 Spring Session Redis에 둔다. 쿠키는 `HttpOnly; Secure; SameSite=Lax`이고 CSRF 토큰을 쓴다. `/api/**`는 토큰 릴레이로 admin-api에 프록시한다. 브라우저에는 토큰이 남지 않는다(AD-01).
- admin-api는 resource server로서 roles 클레임으로 인가한다(AD-02).
- SvelteKit 화면: 로그인, 클라이언트 목록·상세·등록, Secret 발급(1회 표시 모달), 라우트, 역할 매핑, 승인함, 감사 로그, 클라이언트별 API·성공·실패율. UI 라이브러리(shadcn-svelte 등)를 써서 화면 작업 시간을 줄인다.

## 3. 일정

### Phase 1: S2S 경로 (10/26 ~ 11/27)
| 주 | 기간 | 작업 | 완료 기준 |
| --- | --- | --- | --- |
| W1 | 10/26–10/30 | **열린 항목 확인**: 파일럿 대상 클라이언트 인벤토리, 인프라 사실관계(Gateway 앞단 LB/ingress, XFF 동작, 내부 진입 경로를 어떻게 구분할지, MySQL/Redis/Kafka 프로비저닝, CI/CD·배포 표준, 시크릿 저장소), 버전 고정. 스캐폴드: Gradle 멀티모듈, build-logic, docker-compose, CI(빌드, 테스트, gitleaks), `gatehouse-common`, Flyway V1, ADR 3건(설정 전파, AuthLevel, 진입 경로 판별) | `./gradlew build` 통과, compose로 인프라 기동 |
| W2 | 11/2–11/6 | Gateway 코어: 동적 라우트, 2.1의 필터 전부(`CLIENT_ID_ONLY`/`CLIENT_SECRET`), 헤더 규칙, 신뢰 프록시 IP, 라우트 인가, MONITOR 모드, 오류 포맷, 접근 로그, 분 단위 집계기. 설정 소스는 `ConfigSource` 인터페이스 뒤에 파일 스텁으로 둔다 | 필터별 단위 테스트, WireMock E2E |
| W3 | 11/9–11/13 | admin-api: 클라이언트, Secret(복수 활성), IP, 라우트 CRUD, 감사 로그, outbox → Kafka, 스냅샷 API. Gateway 설정 동기화: 스냅샷, 이벤트, 주기 비교, readiness | 변경이 재배포 없이 Gateway에 반영되는 통합 테스트 |
| W4 | 11/16–11/20 | 인증서버 AS-01~05. Gateway: JWT verifier, JWKS stale 캐시, 폐기 확인, Redis 서킷 fail-open, rate limit, 레거시 어댑터(W1 인벤토리에서 고른 방식 1개). 지표 파이프라인: usage/failure Kafka → MySQL과 조회 API | 토큰 발급 → 호출 → 폐기 → 거부 E2E 통과 |
| W5 | 11/23–11/27 | **하드닝과 파일럿**: k6 20k TPS로 p99 추가 지연을 측정하고 NFR-02/03/04 수치를 정한다. 장애 훈련(auth, Redis, Kafka, admin-api 다운). 보안 테스트. Helm, HPA, PDB, 다중 AZ. 런북. 파일럿 라우트 MONITOR 배포 | **M1**: 파일럿 트래픽에서 호출자가 식별되고 기록됨 |

### Phase 2: 관리 화면과 거버넌스 (11/30 ~ 12/18)
| 주 | 기간 | 작업 | 완료 기준 |
| --- | --- | --- | --- |
| W6 | 11/30–12/4 | 인증서버 AS-06~08(OIDC Provider, Google, hd/email_verified, 역할, 부트스트랩). admin-api resource server, 역할 기반 인가, 승인 워크플로(AD-08), 역할 매핑 API(AD-07). BFF 로그인, 세션, 프록시 | Google 로그인 → 승인 요청 → 다른 관리자 승인 → 반영 E2E |
| W7 | 12/7–12/11 | Console 화면 전부(2.8) | 운영 작업 전부를 UI로 할 수 있음 |
| W8 | 12/14–12/18 | AD-12 화면 마무리, Playwright E2E, 운영 배포, 파일럿 라우트 MONITOR → ENFORCE, 호출 팀용 전환 가이드, 버퍼 | **M2**: 1차 오픈 |

**2차 이후(Should)**: AD-11 레거시 전환 현황 화면, 추가 레거시 플러그인, 폐기 목록 로컬화(필요할 때), 외부 관측 스택 연동.

## 4. 진행하며 확정할 항목

PRD §9 항목과, 이 계획에서 기본값을 정해 둔 항목이다.
- **내부 진입 경로의 정의(GW-06)**: 외부 진입이 없는 환경에서 "내부 진입 경로"가 같은 클러스터의 ClusterIP 경유를 뜻하는지(타 클러스터 NLB는 제외), 다른 기준인지 확인해야 한다. 기본안은 진입 프록시의 소스 CIDR 또는 ingress가 넣는 헤더로 판별하는 것이다. W1 ADR에서 정한다.
- AuthLevel 순서(LEGACY < SECRET = JWT), 요청자 본인 승인 금지, 서명 키 저장 위치(DB 암호화 vs KMS).
- D-16 "짧은 TTL"과 D-28 "기본값 24h"가 서로 어긋난다. 폐기 목록이 있으니 동작에는 문제가 없지만 문서 표현을 맞춰야 한다.
- 비기능 수치(NFR-02/04/05)는 W5 측정값을 근거로 제안하고 확정한다. 비교 기준선은 p99 추가 지연 ≤ 10ms, 설정 반영 ≤ 10s다.
- PCI-DSS 범위(보존 1개월 vs 12개월)와 관리자 외 역할 세트(AD-02)는 Phase 2 착수 전에 확정한다.

## 5. 주요 위험과 대응
| 위험 | 대응 |
| --- | --- |
| 모든 East-West 호출이 Gateway를 지나므로 Gateway가 핵심 장애점이 된다 | 다중 AZ, HPA, PDB, 요청 경로에서 DB 조회 금지, 의존성마다 fail-open/stale 동작, MONITOR 모드로 단계 전환 |
| 1인 일정이 밀린다 | W8 버퍼, Phase 2 화면은 UI 라이브러리로, Should 항목은 과감히 뒤로 미룬다 |
| 레거시 방식을 모른다 | W1 인벤토리에서 가장 많이 쓰는 방식 1개만 MVP에 넣고, 나머지는 플러그인으로 추가한다 |
| 다른 클러스터에서 Pod IP가 바뀐다 | CIDR을 서브넷 단위로 등록하고, MONITOR 기간에 실제 출발 IP를 수집해 검증한다 |

## 6. 검증 방법
- **단위**: 필터마다 `MockServerWebExchange`로 검증한다. 헤더 충돌, XFF 위조, 미등록·비활성 ID, 레벨 미달, MONITOR 통과, 신원 헤더 제거와 주입을 확인한다.
- **통합**(Testcontainers): admin-api 변경 → Kafka → Gateway 반영과 반영 시간, 토큰 발급·폐기·거부, Redis를 멈췄을 때 fail-open과 알림 로그, 인증서버를 멈췄을 때 기존 토큰이 통과하는지, Kafka를 멈췄을 때 마지막 설정으로 동작하는지 확인한다.
- **E2E**: `deploy/docker-compose.yml`로 전체를 띄우고 스모크 스크립트를 돌린다(클라이언트 등록 → Secret 발급 → 호출 → 지표 조회). Phase 2에서는 Playwright로 로그인, 승인, Secret 1회 표시를 확인한다.
- **부하**: `loadtest/`의 k6로 20k TPS 혼합 시나리오(ID_ONLY, SECRET, JWT 비율은 인벤토리에 따른다)를 돌리고, Gateway 유무에 따른 p99 차이를 측정한다.
- **보안**: 로그와 응답에 Secret이 마스킹되는지, 다운스트림에 `X-Client-Secret`이나 위조 신원 헤더가 전달되지 않는지 확인한다. pre-push에서 gitleaks를 돌린다.
