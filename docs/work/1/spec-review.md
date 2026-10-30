# Spec review: #1 (1회차)
Verdict: REVISE

## Blocking (구현 전에 고쳐야 함)
- [B1] spec "버전 고정 규칙" 3 + AC-7 — Kotlin 선택 규칙이 판정 불가능하고, 실패 시 어떻게 할지 정해져 있지 않다. (a) "Boot가 지원하는 Kotlin 라인"이 무엇인지 정의가 없다. Boot 문서의 최소 Kotlin 버전일 수도 있고, Boot BOM이 관리하는 `kotlin.version`일 수도 있다. `platform(Boot BOM)`을 쓰면 Boot BOM이 import하는 kotlin-bom이 클래스패스의 `kotlin-stdlib` 버전에 함께 작용한다. 그래서 catalog의 KGP 버전과 실제 stdlib 버전이 어긋날 수 있는데, spec은 이 정렬 규칙을 적지 않았다. (b) Boot가 지원하는 Kotlin 라인 중 JVM target 25를 내는 버전이 없을 때의 동작이 없다. Spring Cloud에는 "없으면 멈추고 묻는다"는 조건이 있지만 Kotlin에는 없다. AC-7은 class major 69를 요구하므로, 구현자가 jvmTarget을 낮추거나 Boot 지원 범위 밖의 Kotlin을 쓰는 결정을 혼자 내리게 된다. — 근거: plan §1(Java 25 툴체인, 최신 GA Boot 4.x), INTENT 열린 질문 4 답 — 제안: "Boot가 지원하는"을 "Boot BOM이 관리하는 Kotlin 버전과 같은 minor 라인"처럼 판정 가능한 기준으로 바꾼다. catalog의 `kotlin` 버전과 런타임 `kotlin-stdlib` 버전이 같아야 한다는 조건을 AC로 추가한다(예: `dependencies` 출력에서 확인). 교집합이 비면 Spring Cloud와 마찬가지로 구현을 멈추고 사람에게 묻는다고 명시한다.
- [B2] spec "gatehouse.kotlin-library" 테스트 의존성 + 규칙 5 + AC-4 — JUnit 버전을 어디서 가져오는지 정해져 있지 않다. 규칙 5는 "JUnit은 Boot BOM을 따른다"고 하지만 `gatehouse-common`은 `kotlin-library`만 적용하므로 Boot BOM이 없다. 그러면 JUnit BOM 버전이 catalog에 있어야 하는데 AC-4 목록에 JUnit 키가 없다. 또 Spring 모듈에는 catalog의 JUnit BOM과 Boot BOM이 함께 적용되고, `platform()`끼리는 높은 버전이 이기므로 모듈마다 JUnit 버전이 달라질 수 있다. 덧붙여 Boot 4.x가 관리하는 JUnit은 6.x 라인인데, INTENT·plan §1·CLAUDE.md는 "JUnit5"라고 적고 있다. spec은 둘 중 무엇을 쓸지 밝히지 않았다. — 근거: plan §1 테스트 스택, INTENT 목표 "JUnit5", AC-13·AC-14 — 제안: catalog에 `junit` 버전 키를 두고 그 값을 "고른 Boot BOM이 관리하는 JUnit 버전과 같게" 고정한다고 적는다. 이 키를 AC-4 목록에 넣고, 모든 모듈의 testRuntimeClasspath에서 `junit-jupiter` 버전이 같다는 AC를 추가한다. JUnit 6이 들어오면 plan의 "JUnit5" 표기와 다르다는 점을 spec에 적는다.

## Non-blocking
- [N1] spec "convention plugin 안에서 버전 카탈로그는 `VersionCatalogsExtension`으로 읽는다" — 이 방식은 convention plugin 본문에서 쓰는 라이브러리 좌표만 해결한다. `build-logic/build.gradle.kts`가 의존할 Kotlin·Spring Boot Gradle plugin 아티팩트의 버전을 어떻게 catalog에서 가져올지는 적혀 있지 않다(예: `build-logic/settings.gradle.kts`에서 `versionCatalogs { create("libs") { from(files("../gradle/libs.versions.toml")) } }`). 이 내용이 없으면 AC-14가 `build-logic/build.gradle.kts`에서 깨지기 쉽다.
- [N2] AC-7 — "또는 빌드 스크립트 출력으로 툴체인 확인"이라는 대안은 PASS/FAIL 기준이 없다. `javap -v`로 각 모듈 main 클래스 하나의 `major version: 69`를 확인하는 방법 하나로 좁힌다.
- [N3] AC-8 "공통 설정 중복이 없다" — 무엇이 중복인지 판정 기준이 없다. "모듈 build 스크립트에는 `plugins { id("gatehouse.…") }`와 `dependencies { }` 블록만 있다"처럼 관찰 가능한 형태로 바꾼다.
- [N4] AC-1 "깨끗한 체크아웃" — foojay를 쓰지 않으므로 이 AC는 로컬 JDK 25가 있어야 성립한다. Gradle daemon을 어느 JDK로 띄우는지도 정하지 않았다. AC에 "JDK 25가 설치된 환경" 같은 전제를 적고, 필요하면 `gradle/gradle-daemon-jvm.properties`를 쓸지도 정한다. CI 이슈가 이 전제를 이어받아야 한다.
- [N5] Out 목록의 BlockHound·ArchUnit — `/Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/.claude/rules/gateway-reactive.md` 17행은 이 항목을 "W1 스캐폴드에서 추가 예정"이라고 적고 있다. spec은 "별도 이슈"라고만 하고 이슈 번호가 없다. 후속 이슈를 만들어 번호를 적어야 추적이 끊기지 않는다. rules 파일은 사람만 고칠 수 있으므로 문구 수정은 diff로 제안한다.
- [N6] "contextLoads가 외부 인프라 없이 뜨는 조건"의 auth 항목 — main `application.yml`에 클라이언트가 없을 때 Authorization Server auto-config가 기동에 실패하면, `bootRun`이 깨진 상태로 남아도 되는지 적혀 있지 않다. 테스트 더미 클라이언트의 secret 표기(`{noop}` 등 DelegatingPasswordEncoder 접두사)도 정해 둔다. 운영 저장 방식(D-xx: HMAC-SHA256, bcrypt 금지)과는 관계없는 테스트 전용 값이라고 명시해 두면 혼동을 막을 수 있다.
- [N7] `-Xjsr305=strict` — Spring Framework 7은 null 주석을 JSpecify로 옮겼고, Kotlin 2.x는 JSpecify를 기본으로 strict 처리한다. 이 옵션이 지금도 필요한지 근거를 적거나 뺀다.
- [N8] AC-5 "주석의 출처 대조" — 사람이 확인하는 기준이다. 주석에 URL과 확인 날짜가 있는지는 grep으로 확인할 수 있다고 적어 두면 자동 검증 범위가 분명해진다.

## ADR 필요
- 없음. 다만 B1을 해결하는 과정에서 JVM target을 25 미만으로 낮추거나 Boot 지원 범위 밖의 Kotlin을 쓰기로 하면 plan §1과 다른 결정이므로 ADR로 남긴다.

검토한 파일:
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/docs/work/1/spec.md
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/docs/work/1/INTENT.md
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/docs/plan/development-plan.md
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/.claude/rules/gateway-reactive.md
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/.claude/rules/secrets-and-identity.md

---

# Spec review: #1 (2회차)
Verdict: APPROVE

## Blocking (구현 전에 고쳐야 함)
없음

## Non-blocking
- [N1] 설계 "`gatehouse.kotlin-library`"의 `jvmToolchain(25)`와 AC-4의 `java`(25) 키 — catalog에 `java = "25"`를 두라고 하면서 convention plugin에는 25를 리터럴로 적게 되어 있다. 이러면 같은 값이 두 곳에 있다. AC-16은 Maven 좌표와 `version "x.y.z"`만 검사하므로 이 중복을 잡지 못한다. 제안: convention plugin은 `VersionCatalogsExtension`에서 `java` 값을 읽어 `jvmToolchain(...)`에 넘긴다고 적는다. 아니면 catalog의 `java` 키를 빼고 AC-4를 고친다.
- [N2] 버전 고정 규칙 3·4 — Kotlin과 Gradle 규칙에 "멈추고 묻는다" 분기는 이미 있다. 다만 실제로 그 분기를 탈 가능성이 높다. Boot 4.0.x BOM이 관리하는 Kotlin은 2.2 라인으로 알고 있고, JVM target 25는 Kotlin 2.3 이후에 들어간 것으로 안다. 이 내용은 구현 시점에 공식 문서로 확인해야 한다. 이 경우 구현이 곧바로 멈추므로, 사람이 어느 쪽을 고를지 미리 정해 두면 대기 시간이 줄어든다. 선택지는 Boot BOM의 `kotlin.version`을 덮어쓰기, Boot 버전 올리기, jvmTarget 낮추기다. 셋 다 plan §1과 다르므로 ADR 대상이다.
- [N3] 규칙 4 Gradle — 조건이 "Java 25 툴체인을 지원"으로만 적혀 있다. spec은 foojay도 daemon JVM 설정도 쓰지 않고 JDK 25가 설치된 환경을 전제한다. 그러면 Gradle daemon도 JDK 25 위에서 돌 가능성이 크다. 그래서 툴체인 지원과 별개로 "Gradle 자체가 Java 25 위에서 실행 가능"이라는 조건도 함께 적는 편이 판정하기 쉽다.
- [N4] 설계 "`gatehouse.kotlin-spring-boot`" — `kotlin-reflect`를 언급하지 않는다. Spring Framework의 Kotlin 지원 문서는 `kotlin-stdlib`와 함께 `kotlin-reflect`가 클래스패스에 있어야 한다고 적고 있다. contextLoads는 통과하더라도 이후 `@ConfigurationProperties`나 Kotlin 생성자 바인딩에서 문제가 드러날 수 있다. convention plugin에 `kotlin-reflect`를 넣을지 정한다. 넣는다면 버전은 규칙 3과 같은 Kotlin 버전으로 맞추고, AC-15와 같은 방식으로 확인한다.
- [N5] AC-15는 `runtimeClasspath`만 검사한다. Kotest와 MockK(규칙 6, "최신 stable")가 더 높은 `kotlin-stdlib`를 끌어오면 Boot BOM이 없는 `gatehouse-common`의 `testRuntimeClasspath`에서 stdlib 버전이 올라갈 수 있다. 이건 AC-15로 잡히지 않는다. 규칙 6에 "Kotest와 MockK가 요구하는 kotlin-stdlib가 3의 Kotlin 이하일 것"이라는 조건을 넣는다. 아니면 AC-15의 검사 범위를 `testRuntimeClasspath`까지 넓힌다.
- [N6] AC-8 "`plugins { }` 블록과 `dependencies { }` 블록만" — `gatehouse-common`은 main 의존성이 없으므로 `dependencies` 블록이 비거나 아예 없을 수 있다. "블록만 있다"가 두 블록이 꼭 있어야 한다는 뜻인지, 그 밖의 블록이 없어야 한다는 뜻인지 분명하지 않다. "이 두 블록 외의 최상위 블록이 없다"로 바꾼다.
- [N7] In 목록의 `gradle.properties` — 무엇을 넣는지 적혀 있지 않다. 예를 들면 `org.gradle.caching`, `org.gradle.configuration-cache`, `org.gradle.parallel`, `kotlin.code.style` 같은 항목이다. configuration cache를 켜는지는 convention plugin을 어떻게 짤지에 영향을 준다. 넣을 키를 나열하거나, 비워 둔다고 명시한다.
- [N8] Out 목록의 BlockHound·ArchUnit 후속 이슈 — 번호가 아직 비어 있다. spec 승인 전이나 `/work-plan` 전에 이슈를 만들고 번호를 적는다. `/Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/.claude/rules/gateway-reactive.md`의 "W1 스캐폴드에서 추가 예정" 문구는 사람만 고칠 수 있다. 수정은 diff로 제안해야 한다.

## ADR 필요
- 없음. 다만 N2처럼 Kotlin과 JVM target 25 조합이 없어서 jvmTarget을 낮추거나 Boot BOM과 다른 Kotlin을 쓰게 되면, spec 103행에 적힌 대로 그때 ADR을 쓴다.

검토한 파일:
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/docs/work/1/spec.md
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/docs/work/1/INTENT.md
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/docs/work/1/spec-review.md (이전 리뷰: B1과 B2는 규칙 3·5와 AC-14·15로 해결됐다. N1~N8도 모두 반영됐고, N5만 이슈 번호가 아직 비어 있다)
- /Users/hannamil/Workspace/gatehouse/.claude/worktrees/issue-1/docs/plan/development-plan.md (§1, §3 W1)
