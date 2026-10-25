---
paths:
  - "gatehouse-gateway/**/*.kt"
---
# Gateway 요청 경로 규칙 (NFR-11, GW-11)

- 요청 경로에서 블로킹 I/O 금지. JDBC, `RestTemplate`, `.block()`, `Thread.sleep`, 동기 파일 I/O를 쓰지 않는다.
- 요청 경로에서 DB를 조회하지 않는다. 클라이언트·라우트 정보는 메모리 스냅샷(`ConfigSource`)에서만 읽는다.
- 코루틴 브리지(`mono {}`, `suspend` 핸들러)를 hot path에 쓰지 않는다. Reactor 연산자로 쓴다.
- 필터 순서는 PRD §3을 따른다. 새 필터는 기존 순서 상수 사이에 넣고, 순서를 바꾸면 ADR을 남긴다.
- 거부 응답은 `{code, message, requestId}` 형식 하나로 통일하고 상세 원인은 응답에 넣지 않는다(로그에만).
- `enforcementMode=MONITOR`인 라우트는 거부 대신 지표·로그만 남기고 통과시킨다. 거부 분기마다 MONITOR 경로 테스트를 함께 쓴다.
- Redis 호출은 짧은 타임아웃과 서킷브레이커 뒤에 두고 실패 시 fail-open 한다(GW-18). fail-close로 바꾸지 않는다.
- 메트릭 라벨에는 라우트 템플릿 ID만 쓴다. 원본 경로나 미등록 Client ID를 라벨로 쓰지 않는다(`UNKNOWN`으로 묶는다, NFR-13).
- 필터 단위 테스트는 `MockServerWebExchange`로 쓴다.

강제: 블로킹 호출은 BlockHound 테스트, 패키지 의존은 ArchUnit 테스트로 잡는다(W1 스캐폴드에서 추가 예정. 추가되면 테스트 이름으로 이 줄을 바꾼다).
