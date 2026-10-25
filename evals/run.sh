#!/usr/bin/env bash
# 고정 과제 세트를 headless로 돌려 과제별 통과 여부·비용·시간을 기록한다.
# 사용: evals/run.sh [variants/<변형>.json]
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
MODEL="${EVAL_MODEL:-claude-opus-5-5}"
VARIANT="${1:-}"
name="$(basename "${VARIANT:-baseline}" .json)"
out="$ROOT/evals/runs/$(date +%Y%m%d-%H%M%S)-$name"
mkdir -p "$out"

shopt -s nullglob
tasks=("$ROOT"/evals/tasks/*.json)
[ ${#tasks[@]} -eq 0 ] && { echo "evals/tasks/ 에 과제가 없습니다."; exit 1; }

for t in "${tasks[@]}"; do
  id="$(jq -r .id "$t")"
  wt="$out/wt-$id"
  git -C "$ROOT" worktree add -q --detach "$wt" "$(jq -r .base_ref "$t")" || continue

  args=(-p "$(jq -r .prompt "$t")" --model "$MODEL" --output-format json --permission-mode acceptEdits)
  [ -n "$VARIANT" ] && args+=(--settings "$ROOT/evals/$VARIANT")

  start=$(date +%s)
  (cd "$wt" && claude "${args[@]}") >"$out/$id.claude.json" 2>"$out/$id.claude.err"
  secs=$(( $(date +%s) - start ))

  (cd "$wt" && bash -c "$(jq -r .check "$t")") >"$out/$id.check.log" 2>&1 && passed=true || passed=false

  jq -cn --arg id "$id" --arg variant "$name" --arg model "$MODEL" --argjson passed "$passed" --argjson secs "$secs" \
    --argjson cost "$(jq '.total_cost_usd // null' "$out/$id.claude.json" 2>/dev/null || echo null)" \
    '{id:$id, variant:$variant, model:$model, passed:$passed, seconds:$secs, cost_usd:$cost}' | tee -a "$out/results.jsonl"

  git -C "$ROOT" worktree remove --force "$wt"
done

jq -s '{tasks: length, passed: map(select(.passed)) | length, cost_usd: (map(.cost_usd // 0) | add), seconds: (map(.seconds) | add)}' "$out/results.jsonl"
