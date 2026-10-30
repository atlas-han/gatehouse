# Spec: #1 Gradle 멀티모듈 스캐폴드, build-logic, 버전 고정
관련 요구: 없음 · 관련 결정: D-14 · INTENT: ./INTENT.md

## 범위 (In / Out)

**In**
- 루트: `settings.gradle.kts`, `gradle.properties`(`org.gradle.parallel=true`, `org.gradle.caching=true`, `kotlin.code.style=official`만. configuration cache는 이 이슈에서 켜지 않는다), Gradle wrapper(`gradlew`, `gradlew.bat`, `gradle/wrapper/*`)
- `gradle/libs.versions.toml`: 모든 버전, 라이브러리, 플러그인 좌표
- `build-logic/` included build와 convention plugin 2개: `gatehouse.kotlin-library`, `gatehouse.kotlin-spring-boot`
- 모듈 4개: `gatehouse-common`, `gatehouse-gateway`, `gatehouse-auth`, `gatehouse-admin-api`
- Spring 모듈 3개마다 `@SpringBootApplication` main 클래스, 대표 starter, contextLoads 테스트 (INTENT 열린 질문 2 답)
- `gatehouse-common`에 테스트 기본값이 동작함을 보이는 최소 테스트 1개

**Out**
- `gatehouse-console/*` (Phase 2)
- `deploy/docker-compose.yml`, CI, Flyway V1, W1 ADR 3건 (plan §3 W1의 다른 작업)
- `gatehouse-common`의 실제 타입(AuthMethod, SecretDigester 등)
- admin-api의 JPA, Flyway, DB 드라이버 (INTENT 열린 질문 2 답)
- Testcontainers, WireMock, BlockHound, ArchUnit 의존성. `.claude/rules/gateway-reactive.md`가 BlockHound·ArchUnit을 "W1 스캐폴드에서 추가 예정"이라고 적고 있지만, 이 이슈의 범위에는 없다. 후속 이슈로 만든다(이슈 생성은 사람 확인 후, 번호는 생성 뒤 여기에 적는다).
- Actuator, virtual threads 설정, `application.yml`의 기능 설정
- JDK 자동 프로비저닝(foojay resolver)과 `gradle/gradle-daemon-jvm.properties`. 빌드 환경에 JDK 25가 설치돼 있다고 전제한다. 이 전제는 CI 이슈가 이어받는다.

## 설계

### 모듈과 convention plugin
| 모듈 | 적용 plugin | 대표 의존성 (main) |
| --- | --- | --- |
| `gatehouse-common` | `gatehouse.kotlin-library` | Kotlin stdlib만. Spring 없음 (plan §1) |
| `gatehouse-gateway` | `gatehouse.kotlin-spring-boot` | Spring Cloud Gateway Server WebFlux starter |
| `gatehouse-auth` | `gatehouse.kotlin-spring-boot` | Spring Boot OAuth2 Authorization Server starter (Spring Security 7) |
| `gatehouse-admin-api` | `gatehouse.kotlin-spring-boot` | Spring Boot Web MVC starter |

Spring 모듈은 아직 `gatehouse-common`에 의존하지 않는다. 쓸 타입이 생길 때 추가한다.

**`gatehouse.kotlin-library`**
- Kotlin JVM plugin, `kotlin { jvmToolchain(<catalog java>) }`. 25를 리터럴로 적지 않고 catalog의 `java` 값을 읽어 넘긴다.
- 테스트: `tasks.test { useJUnitPlatform() }`. `testImplementation`에 `platform(JUnit BOM)`(catalog의 `junit` 버전), JUnit Jupiter, Kotest assertions core, MockK. `testRuntimeOnly`에 JUnit Platform launcher
- Kotlin 컴파일러 옵션은 기본값을 쓴다. `-Xjsr305=strict`는 넣지 않는다(Spring Framework 7은 JSpecify 주석을 쓰고, Kotlin 2.x는 JSpecify를 기본으로 strict 처리한다). `allWarningsAsErrors`는 켜지 않는다.

**`gatehouse.kotlin-spring-boot`**
- `gatehouse.kotlin-library`를 적용한 뒤 Spring Boot plugin과 Kotlin Spring(all-open) plugin을 적용
- Spring Boot BOM과 Spring Cloud BOM을 Gradle `platform()`으로 가져온다. `io.spring.dependency-management` plugin은 쓰지 않는다.
- `implementation`에 `kotlin-reflect`(Spring의 Kotlin 지원이 요구한다). 버전은 규칙 3의 Kotlin과 같다.
- `testImplementation`에 Spring Boot test starter

**`build-logic`과 catalog 연결**
- `build-logic/settings.gradle.kts`에서 `versionCatalogs { create("libs") { from(files("../gradle/libs.versions.toml")) } }`로 루트 catalog를 공유한다.
- `build-logic/build.gradle.kts`는 `kotlin-dsl` plugin을 쓰고, Kotlin Gradle plugin·Spring Boot Gradle plugin·Kotlin all-open plugin 아티팩트를 `libs.…` 접근자로 `implementation`에 넣는다(catalog `[libraries]`에 plugin 아티팩트 좌표를 `version.ref`로 둔다).
- convention plugin 본문에서는 `VersionCatalogsExtension`으로 `libs`를 읽는다.
- 이렇게 해서 `build-logic/`과 모듈 build 스크립트 어디에도 버전 문자열이 없다.

### 버전 고정 규칙 (plan §1, INTENT 열린 질문 3·4 답)
구현 시점에 공식 문서를 보고 아래 순서로 정한다. 각 단계에서 조건을 만족하는 버전이 없으면 **구현을 멈추고 사람에게 묻는다**. jvmTarget을 25 미만으로 낮추거나 아래 기준 밖의 버전을 쓰는 결정은 혼자 내리지 않는다(그런 결정을 하게 되면 plan §1과 다르므로 ADR 대상이다).
1. **Spring Cloud**: Spring Boot 4.x를 지원하는 릴리스 트레인 중 최신 **GA**(서비스 릴리스 포함). RC, M, SNAPSHOT은 쓰지 않는다.
2. **Spring Boot**: 1에서 고른 트레인이 지원하는 Boot 4.x 라인의 최신 GA 패치. 최신 Boot GA가 그 트레인의 지원 범위 밖이면 Boot를 지원 범위로 낮춘다.
3. **Kotlin**: 2의 Boot BOM(`spring-boot-dependencies`)이 관리하는 `kotlin.version`과 **정확히 같은 버전**. 이 버전이 JVM target 25를 지원하지 않으면 멈추고 묻는다. catalog의 `kotlin`(KGP)과 런타임 `kotlin-stdlib`가 같은 버전이 된다.
4. **Gradle**: 2의 Boot Gradle plugin과 3의 Kotlin Gradle plugin이 지원하고, Java 25 툴체인을 지원하며, Gradle 자체가 JDK 25 위에서 실행되는 최신 stable. wrapper에 `distributionSha256Sum`을 함께 적는다.
5. **JUnit**: 2의 Boot BOM이 관리하는 JUnit 버전과 **정확히 같은 값**을 catalog `junit`에 둔다. 그래서 Boot BOM이 없는 `gatehouse-common`과 Spring 모듈의 JUnit 버전이 같다. Boot 4.x BOM이 JUnit 6 라인을 관리하면 JUnit 6을 쓴다. plan §1·CLAUDE.md의 "JUnit5"는 JUnit Platform·Jupiter API 기반 테스트 스택을 뜻하는 것으로 보고, 테스트 작성 방식(Jupiter `@Test`, JUnit Platform)은 같다. 이 차이는 PR 설명에 적는다.
6. **Kotest, MockK**: Boot BOM이 관리하지 않으므로 3의 Kotlin과 호환되는 최신 stable. 단, 끌어오는 `kotlin-stdlib`가 3의 Kotlin보다 높지 않아야 한다(AC-15).

`libs.versions.toml` 맨 위 주석에 고른 조합과 근거(호환 매트릭스·BOM 문서 URL, 확인 날짜 `YYYY-MM-DD`)를 적는다. ADR은 쓰지 않는다(INTENT 열린 질문 1 답).

### contextLoads가 외부 인프라 없이 뜨는 조건
- gateway: 라우트 설정 없이 뜬다. Redis·Kafka 의존성이 없으므로 연결 시도도 없다.
- auth: Authorization Server가 기동에 등록 클라이언트를 요구하면, `src/test/resources/application.yml`에만 테스트용 더미 클라이언트를 둔다. secret은 `{noop}` 접두사의 명백한 더미 값에 `gitleaks:allow`를 붙인다(`.claude/rules/secrets-and-identity.md`). 이 값은 contextLoads 전용이며, 클라이언트 Secret 저장 방식(HMAC-SHA256, plan §2.3)과는 관계없다. main `application.yml`에는 클라이언트를 넣지 않는다. 그 때문에 main 설정만으로 `bootRun`이 실패하더라도 이 이슈에서는 허용한다(실제 클라이언트 등록은 W4 AS-01~05에서 한다).
- admin-api: JPA·Flyway·DataSource가 없으므로 DB 없이 뜬다.
- 세 모듈 모두 `@SpringBootTest`의 `webEnvironment = MOCK`(기본값)을 쓴다. 실제 포트를 열지 않는다.

### 실패·저하 동작
해당 없음. 요청 경로와 런타임 동작이 없는 스캐폴드다.

## 계약
### HTTP API
변경 없음
### 헤더
변경 없음
### 이벤트
변경 없음
### 데이터
변경 없음 (Flyway 없음)

## 수용 기준
전제: 모든 AC는 JDK 25가 설치된 환경에서 확인한다.

- AC-1: 깨끗한 체크아웃에서 `./gradlew build` 실행 → exit 0. 검증: 명령 실행
- AC-2: `./gradlew check` 실행 → exit 0. 검증: 명령 실행 (Stop hook과 같은 명령)
- AC-3: `./gradlew projects` 실행 → 하위 프로젝트가 정확히 `gatehouse-common`, `gatehouse-gateway`, `gatehouse-auth`, `gatehouse-admin-api` 넷이고 `gatehouse-console`이 없다. 검증: 명령 출력 확인
- AC-4: `gradle/libs.versions.toml`의 `[versions]`에 `java`(25), `spring-boot`, `spring-cloud`, `kotlin`, `junit`, `kotest`, `mockk` 항목이 있고, 모두 범위·`+`·`latest`가 아닌 고정 값이다. 검증: 파일 확인
- AC-5: 고정한 `spring-boot`, `spring-cloud`, `kotlin`, `junit` 버전에 `-RC`, `-M`, `-SNAPSHOT`, `-Beta`, `-alpha` 접미사가 없고, `spring-boot`가 `4.`으로 시작한다. `libs.versions.toml` 주석에 호환 매트릭스 URL(`https://`)과 확인 날짜(`YYYY-MM-DD`)가 있다. 검증: 파일 확인과 grep. 매트릭스상 그 Spring Cloud 트레인이 그 Boot 버전을 지원하는지는 PR 리뷰에서 사람이 대조한다.
- AC-6: `gradle/wrapper/gradle-wrapper.properties`의 `distributionUrl`이 고정된 stable Gradle 배포판을 가리키고 `distributionSha256Sum`이 있다. 검증: 파일 확인
- AC-7: 각 모듈의 main 클래스 파일 하나(common은 테스트를 위해 둔 클래스 또는 main 소스의 아무 클래스, Spring 모듈은 Application 클래스)에 대해 `javap -v`의 `major version`이 69다. 검증: 명령 실행
- AC-8: `gatehouse-common`은 `gatehouse.kotlin-library`를, 나머지 세 모듈은 `gatehouse.kotlin-spring-boot`를 적용한다. 각 모듈 `build.gradle.kts`에는 `plugins { id("gatehouse.…") }` 블록과 `dependencies { }` 블록 외의 최상위 블록이 없다(`dependencies`는 생략 가능). 검증: 파일 확인
- AC-9: `./gradlew :gatehouse-common:dependencies --configuration runtimeClasspath` 출력에 `org.springframework` 그룹이 없다. 검증: 명령 출력 확인
- AC-10: `./gradlew :gatehouse-admin-api:dependencies --configuration runtimeClasspath` 출력에 `spring-boot-starter-data-jpa`, `org.flywaydb`, `org.hibernate`가 없다. 검증: 명령 출력 확인
- AC-11: gateway의 runtimeClasspath에 Spring Cloud Gateway Server WebFlux가, auth에 Spring Security OAuth2 Authorization Server가, admin-api에 `spring-webmvc`가 있다. 검증: 각 모듈 `dependencies` 출력 확인
- AC-12: 세 Spring 모듈에 각각 `@SpringBootApplication` main 클래스와 `@SpringBootTest` contextLoads 테스트가 있고, MySQL·Redis·Kafka가 떠 있지 않은 환경에서 `./gradlew test`로 통과한다. 검증: `GatewayApplicationTest`, `AuthApplicationTest`, `AdminApiApplicationTest` (이름은 구현 시 확정)
- AC-13: 모든 모듈의 testRuntimeClasspath에 JUnit Jupiter, Kotest assertions, MockK가 있고, 각 모듈에서 테스트가 JUnit Platform으로 1개 이상 실행된다(`build/test-results/test/*.xml`이 모듈마다 존재하고 tests ≥ 1). `gatehouse-common`의 테스트는 Kotest assertion과 MockK를 각각 1회 이상 쓴다. 검증: 명령 실행과 결과 파일 확인
- AC-14: 네 모듈의 testRuntimeClasspath에서 `org.junit.jupiter:junit-jupiter-api`의 해결 버전이 모두 같고 catalog `junit` 값과 같다. 검증: 각 모듈 `dependencyInsight --dependency junit-jupiter-api --configuration testRuntimeClasspath` 출력
- AC-15: 네 모듈의 runtimeClasspath와 testRuntimeClasspath에서 `org.jetbrains.kotlin:kotlin-stdlib`의 해결 버전이, Spring 모듈에서는 `kotlin-reflect`의 해결 버전도, 모두 catalog `kotlin` 값과 같다. 그 값은 고른 Boot BOM의 `kotlin.version`과 같다. 검증: 각 모듈·configuration별 `dependencyInsight --dependency kotlin-stdlib`(Spring 모듈은 `kotlin-reflect`도) 출력과 BOM 대조
- AC-16: 모듈 build 스크립트, `build-logic/build.gradle.kts`, `build-logic/settings.gradle.kts`, `build-logic/src/` 어디에도 Maven 좌표의 버전 문자열(`"group:name:1.2.3"` 형태)이나 `version "x.y.z"`가 없다. 검증: `grep`
- AC-17: 커밋된 파일에 실제 Secret이 없다. auth 테스트용 더미 Secret이 있으면 `gitleaks:allow`가 붙어 있다. 검증: `gitleaks detect` 또는 pre-push hook 통과

## ADR 필요 여부
없음. 버전 고정은 PRD §9·plan §4의 열린 항목이 아니고 plan §1의 범위 안에서 정한다. 근거는 `libs.versions.toml` 주석에 둔다(INTENT 열린 질문 1 답). 버전 고정 규칙에서 멈추는 경우가 생겨 jvmTarget 하향이나 Boot BOM과 다른 Kotlin을 쓰기로 하면 그때 ADR을 쓴다.
