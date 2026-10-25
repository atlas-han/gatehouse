---
paths:
  - "gatehouse-common/**/event/**"
  - "**/*Event*.kt"
  - "**/*Outbox*.kt"
  - "**/kafka/**/*.kt"
---
# Kafka 이벤트 규칙 (GW-11, AD-10, GW-14)

- 토픽은 `gatehouse.<도메인>.<이벤트>` 형식이다. 현재 토픽: `gatehouse.config.changed`, `gatehouse.usage.minutely`.
- 이벤트 스키마는 `gatehouse-common`에만 정의하고 producer와 consumer가 같은 클래스를 쓴다.
- 스키마는 하위 호환으로만 바꾼다: 필드 추가는 nullable 또는 기본값과 함께, 필드 삭제·이름 변경·타입 변경은 금지. 깨지는 변경이 필요하면 새 토픽과 ADR.
- `config.changed`는 알림만 담는다(`{version, entityType, entityId}`). 설정 본문을 싣지 않는다. Gateway는 받은 뒤 스냅샷을 pull 한다.
- 설정 변경 이벤트는 outbox로만 보낸다. 변경 트랜잭션 안에서 `config_version` 증가와 outbox insert를 같이 하고, 트랜잭션 밖에서 Kafka로 직접 보내지 않는다(AD-10).
- consumer는 중복·순서 뒤바뀜을 견뎌야 한다. 받은 version이 현재보다 크지 않으면 무시한다.
- producer는 idempotent 설정(`enable.idempotence=true`, `acks=all`)을 쓴다.

강제: 스키마 호환은 직렬화 왕복 테스트로 잡는다(W3에서 추가 예정).
