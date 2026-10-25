# 하네스 eval

하네스 구성요소(hook, rule, subagent, skill)가 실제로 도움이 되는지 고정 과제 세트로 측정한다. 하네스 설계 Layer 7.

## 과제 세트 (`tasks/*.json`)

지난 이슈·버그 중 20~30개를 골라 과제로 만든다. 아직 병합된 이슈가 없으므로 비어 있다. Phase 1 진행 중 병합되는 이슈에서 채운다.

```json
{
  "id": "gw-17-header-conflict",
  "base_ref": "<과제 시작 커밋 SHA>",
  "prompt": "이슈 본문 또는 /implement 에 넣을 지시",
  "check": "./gradlew :gatehouse-gateway:test --tests '*ClientIdentificationFilterTest'",
  "reference_pr": 12,
  "human_verdict": "PASS"
}
```

- `base_ref`: 정답 PR이 병합되기 직전 커밋. 정답 테스트는 `check`가 가리키는 테스트로, 정답 PR에서 가져와 둔다.
- `human_verdict`: 사람이 정답 PR을 리뷰한 판정. verifier 판정과의 일치율을 잰다.

## 실행

```sh
evals/run.sh                       # 기본 하네스
evals/run.sh variants/no-verify-gate.json   # 구성요소 하나를 뺀 변형
```

모델은 `EVAL_MODEL`(기본 `claude-opus-5-5`)로 고정한다. 결과는 `evals/runs/<시각>-<변형>/results.jsonl`(gitignore)에 남는다.
측정: 과제별 `check` 통과 여부, 비용(`total_cost_usd`), 소요 시간. 변형끼리 비교해 효과 없는 구성요소를 `.claude/HARNESS.md`에 기록한다.

## 변형 (`variants/*.json`)

`claude --settings`로 덧씌울 설정 조각이다. 한 번에 구성요소 하나만 바꾼다.
