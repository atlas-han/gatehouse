# #1 Gradle 멀티모듈 스캐폴드, build-logic, 버전 고정
관련 요구: 없음 · 관련 결정: D-14 · 일정: plan §3 W1

## 목표
- plan §1 저장소 구조대로 Kotlin + Gradle(Kotlin DSL) 멀티모듈 모노레포 골격을 세운다.
- `settings.gradle.kts`, `gradle/libs.versions.toml`, Gradle wrapper를 둔다.
- `build-logic/`에 convention plugin `kotlin-library`, `kotlin-spring-boot`를 만들어 공통 빌드 설정을 모은다.
- 빈 모듈 4개를 만든다: `gatehouse-common`, `gatehouse-gateway`, `gatehouse-auth`, `gatehouse-admin-api`.
- 호환 매트릭스를 확인해 Java 25 툴체인, Spring Boot 4.x GA, 이에 맞는 Spring Cloud 릴리스 트레인 버전을 고정한다.
- 테스트 의존성 기본값으로 JUnit5, Kotest assertions, MockK를 넣는다.

## 비목표
- `gatehouse-console/bff`, `gatehouse-console/web` 모듈 (Phase 2, 이슈 본문)
- 같은 W1의 다른 작업: `deploy/docker-compose.yml`, CI(빌드·테스트·gitleaks), `gatehouse-common`의 실제 내용(AuthMethod, SecretDigester 등), Flyway V1, ADR 3건(설정 전파, AuthLevel, 진입 경로 판별) (plan §3 W1)
- 각 모듈의 기능 코드(Gateway 필터, 인증서버, 관리 API)
- Testcontainers, WireMock, k6, Playwright 의존성 (plan §1에 있으나 이 이슈의 테스트 기본값 목록에는 없음)

## 제약 (PRD·plan·ADR에서 온 것만, 출처 표기)
- 기술 스택 후보는 Spring Cloud, Spring Security, Svelte, MySQL, Redis, Kafka다. (PRD §8 D-14)
- Kotlin + Gradle(Kotlin DSL) 멀티모듈 모노레포로 간다. (plan Context "확정된 전제")
- Java 25 LTS 툴체인, 최신 GA Spring Boot 4.x, 이에 맞는 Spring Cloud 릴리스 트레인을 쓴다. 정확한 버전은 W1에 호환 매트릭스를 보고 고정한다. (plan §1)
- 버전은 `gradle/libs.versions.toml`에, 공통 빌드 설정은 `build-logic/` convention plugin에 둔다. (plan §1, CLAUDE.md)
- `gatehouse-common`은 Spring에 의존하지 않는다. (plan §1)
- `gatehouse-gateway`는 Spring Cloud Gateway Server WebFlux, `gatehouse-auth`는 Spring Security 7 내장 Authorization Server, `gatehouse-admin-api`는 Spring MVC + Spring Data JPA + Flyway다. (plan §1) 이 이슈에서는 대표 starter와 main 클래스까지 넣고, admin-api의 JPA/Flyway는 뺀다. (열린 질문 2 답)
- 완료 기준은 `./gradlew build` 통과다. (plan §3 W1)
- 코드가 바뀌면 멈추기 전에 `./gradlew check`가 통과해야 한다. (CLAUDE.md, Stop hook)

## 수용 기준 초안
- [ ] 깨끗한 체크아웃에서 `./gradlew build`가 exit 0으로 끝난다. (plan §3 W1)
- [ ] `./gradlew projects`가 `gatehouse-common`, `gatehouse-gateway`, `gatehouse-auth`, `gatehouse-admin-api` 네 개를 보여주고, `gatehouse-console`은 없다. (plan §1, 이슈 본문)
- [ ] `gradle/libs.versions.toml`에 Java 25, Spring Boot 4.x GA, Spring Cloud 릴리스 트레인 버전이 범위나 `+`가 아닌 고정 값으로 적혀 있다. (plan §1)
- [ ] 각 모듈의 컴파일 툴체인이 Java 25다. (예: `./gradlew :gatehouse-common:javaToolchains`나 빌드 로그로 확인)
- [ ] `build-logic/`에 `kotlin-library`, `kotlin-spring-boot` convention plugin이 있다. `gatehouse-common`은 `kotlin-library`를, 나머지 세 모듈은 `kotlin-spring-boot`를 적용한다.
- [ ] `gatehouse-common`의 런타임 의존성 트리(`dependencies --configuration runtimeClasspath`)에 `org.springframework` 그룹이 없다. (plan §1)
- [ ] 모든 모듈의 테스트 클래스패스에 JUnit5, Kotest assertions, MockK가 있고, 모듈마다 테스트가 JUnit Platform에서 1개 이상 실행된다. (이슈 본문)
- [ ] 모듈 build 스크립트에 버전 문자열을 직접 적지 않는다. 모든 버전은 `libs.versions.toml`에서 온다.
- [ ] 고정한 Spring Boot·Spring Cloud 버전이 모두 GA다(RC, M, SNAPSHOT 아님). Boot 버전은 그 Spring Cloud GA가 지원하는 범위 안이다. (열린 질문 3 답)
- [ ] Kotlin 버전은 `libs.versions.toml`에, Gradle 버전은 `gradle/wrapper/gradle-wrapper.properties`에 고정 값으로 있고, 둘 다 Java 25 툴체인을 지원한다. (열린 질문 4 답)
- [ ] `libs.versions.toml`에 버전 조합의 근거(호환 매트릭스 출처)가 주석으로 있다. 별도 ADR은 없다. (열린 질문 1 답)
- [ ] `gatehouse-gateway`, `gatehouse-auth`, `gatehouse-admin-api`에 각각 `@SpringBootApplication` main 클래스와 contextLoads 테스트가 있고, 그 테스트가 외부 인프라(DB, Redis, Kafka) 없이 통과한다. (열린 질문 2 답)
- [ ] 대표 starter: gateway는 Spring Cloud Gateway Server WebFlux, auth는 Spring Security Authorization Server, admin-api는 Spring Web MVC를 쓴다. admin-api의 런타임 의존성 트리에 JPA(`spring-boot-starter-data-jpa`)와 Flyway가 없다. (plan §1, 열린 질문 2 답)

## 열린 질문
- 고정한 버전 조합의 근거(호환 매트릭스)를 ADR로 남길까, 아니면 `libs.versions.toml` 주석과 PR 설명으로 충분할까? (이슈 열린 항목, plan §1)
  답: ADR은 쓰지 않는다. `libs.versions.toml` 주석과 PR 설명으로 충분하다.
- 빈 Spring 모듈(gateway, auth, admin-api)을 어디까지 채울까? (a) convention plugin만 적용하고 소스는 두지 않음, (b) `@SpringBootApplication` main 클래스, 각 모듈의 대표 starter(plan §1의 Gateway Server WebFlux, Security Authorization Server, Web MVC + JPA + Flyway), contextLoads 테스트까지 넣음. (b)라면 admin-api의 JPA/Flyway는 DB 없이 뜨지 않으므로 이번에는 빼거나 auto-config를 끌지도 같이 정해야 한다. (이슈 본문 "빈 모듈", plan §1)
  답: (b). admin-api의 JPA/Flyway는 뺀다.
- 고정할 버전 조합 중 Spring Boot 4.x GA와 맞는 Spring Cloud 릴리스 트레인이 아직 GA가 아니면(RC/마일스톤만 있으면) 어떻게 할까? Boot 버전을 Spring Cloud GA에 맞춰 낮출지, Spring Cloud 프리릴리스를 받아들일지. (plan §1 "W1에 호환 매트릭스를 보고 고정")
  답: Spring Cloud GA에 맞춰 Spring Boot 버전을 낮춘다. 프리릴리스는 쓰지 않는다.
- Kotlin과 Gradle 버전도 이 이슈에서 함께 고정한다고 보면 될까? 이슈와 plan에는 Java·Spring Boot·Spring Cloud만 적혀 있다. Java 25 툴체인을 지원하는 Kotlin·Gradle 최소 버전이 기준이 된다. (이슈 완료 기준, plan §1)
  답: 예. Kotlin과 Gradle 버전도 이 이슈에서 고정한다.
