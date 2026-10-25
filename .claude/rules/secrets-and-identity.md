---
paths:
  - "gatehouse-*/src/**/*.kt"
  - "gatehouse-console/**/*.{kt,ts,svelte}"
---
# Secret·신원 헤더 규칙 (NFR-09, GW-10, GW-17, AD-04)

- Secret 저장값은 `SecretDigester`(HMAC-SHA256 + pepper[keyVersion])로만 만든다. bcrypt·평문·단순 SHA 저장 금지.
- Secret 비교는 `SecretDigester`의 상수 시간 비교만 쓴다. `==`, `equals`, `contentEquals`로 비교하지 않는다.
- 로그·예외 메시지·응답·화면에는 Secret, 토큰, pepper, 레거시 키 원문을 남기지 않는다. 식별이 필요하면 prefix 4자리만 쓴다.
- Secret은 발급 응답에서 한 번만 보여 준다. 조회 API가 Secret 원문이나 digest를 돌려주지 않는다.
- 신원 헤더 이름은 `gatehouse-common`의 상수만 쓴다. `X-Client-ID`/`Client-ID`, `X-Client-Secret`/`Client-Secret`은 같은 항목이고 값이 다르면 거부한다.
- 다운스트림으로 나가는 요청에는 외부에서 들어온 신원·Secret·레거시 키 헤더가 남지 않아야 한다. 검증된 `X-Client-Id`, `X-Auth-Method`만 주입한다.
- 테스트 픽스처의 Secret은 실행 중 생성하거나, 명백한 더미 값에 `gitleaks:allow`를 붙인다.

강제: 커밋 전 gitleaks(pre-push hook, PostToolUse `scan-secrets.sh`). 상수 시간 비교와 헤더 제거는 `SecretDigester`·`IdentityHeaderNormalizationFilter` 테스트가 잡는다(W1~W2에서 추가 예정).
