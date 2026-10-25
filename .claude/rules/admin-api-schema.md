---
paths:
  - "gatehouse-admin-api/**"
  - "**/db/migration/**"
---
# admin-api·스키마 규칙 (AD-08, AD-09, AD-10)

- DB 스키마의 소유자는 admin-api뿐이다. 다른 모듈은 Flyway 마이그레이션을 두지 않는다.
- 이미 커밋된 Flyway 마이그레이션(`V*__*.sql`)은 고치지 않는다. 변경은 새 버전 파일로 한다. `guard-paths.sh`가 수정을 막는다.
- 설정을 바꾸는 모든 쓰기는 같은 트랜잭션에서 감사 로그(`audit_log`, before/after JSON), `config_version` 증가, outbox insert를 함께 한다.
- 민감 변경(IP, 인증 방식, 라우트 허용 클라이언트, 역할)은 Phase 2부터 `change_request`를 거친다. 요청자 본인은 승인할 수 없다.
- `GET /internal/config/snapshot`은 Secret digest를 담으므로 내부 전용 인증 뒤에 둔다. 공개 API에 digest를 노출하지 않는다.
- 클라이언트 토큰 TTL은 24시간 이하만 허용하고, 미입력 시 24시간이다(D-28).

강제: 마이그레이션 불변은 `guard-paths.sh`. 트랜잭션 묶음은 Testcontainers 통합 테스트로 잡는다(W3에서 추가 예정).
