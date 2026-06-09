#!/usr/bin/env bash
set -euo pipefail

AFFECTED_JSON="${AFFECTED_JSON:-docs/affected_docs.json}"
MODE="${MODE:-schedule}"
MAX_BYTES="${DOC_AUDIT_MAX_BYTES:-50000}"
MODEL="${DOC_AUDIT_MODEL:-deepseek-chat}"
API_URL="${DOC_AUDIT_API_URL:-https://api.deepseek.com/chat/completions}"

mkdir -p docs

if [ ! -s "$AFFECTED_JSON" ] || [ "$(jq 'length' "$AFFECTED_JSON" 2>/dev/null || echo 0)" = "0" ]; then
  echo '{"stale":[],"current":[]}' > docs/stale_docs.json
  echo "No affected docs; skipping AI gate."
  exit 0
fi

DIFF_BYTES=$(printf "%s" "${DIFFS:-}" | wc -c | tr -d ' ')
if [ "$DIFF_BYTES" -gt "$MAX_BYTES" ]; then
  jq -n --argjson bytes "$DIFF_BYTES" \
    '{"too_large":true,"diff_bytes":$bytes,"stale":[],"current":[]}' > docs/stale_docs.json
  echo "Diff is too large for automatic doc audit (${DIFF_BYTES} bytes)."
  [ "$MODE" = "release_gate" ] && exit 1 || exit 0
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
  jq -n '{"missing_api_key":true,"stale":[],"current":[]}' > docs/stale_docs.json
  echo "No LLM API key configured; doc audit skipped."
  [ "$MODE" = "release_gate" ] && exit 1 || exit 0
fi

TOKEN="${DEEPSEEK_API_KEY:-${OPENAI_API_KEY:-}}"

PROMPT=$(cat <<'PROMPT_EOF'
You are a documentation freshness auditor.

You are given:
1. Source code changes as a unified diff.
2. A repository-controlled mapping from those source files to documentation targets.

For each documentation target, determine whether it is STALE because of the code changes.

Return strict JSON only:
{
  "stale": [
    {"doc": "path", "section": "Section Name or null", "critical": true, "reason": "short reason"}
  ],
  "current": [
    {"doc": "path", "section": "Section Name or null"}
  ]
}
PROMPT_EOF
)

FULL_PROMPT="${PROMPT}

CODE DIFFS:
${DIFFS:-}

AFFECTED DOC TARGETS:
$(cat "$AFFECTED_JSON")
"

RESPONSE=$(curl -sS "$API_URL" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg model "$MODEL" --arg prompt "$FULL_PROMPT" '{
    model: $model,
    messages: [{"role": "user", "content": $prompt}],
    temperature: 0.1,
    response_format: {"type": "json_object"}
  }')")

CONTENT=$(printf "%s" "$RESPONSE" | jq -r '.choices[0].message.content // empty')
if [ -z "$CONTENT" ] || ! printf "%s" "$CONTENT" | jq empty >/dev/null 2>&1; then
  printf "%s\n" "$RESPONSE" > docs/stale_docs.raw.json
  jq -n '{"invalid_response":true,"stale":[],"current":[]}' > docs/stale_docs.json
  echo "LLM response was missing or invalid JSON."
  [ "$MODE" = "release_gate" ] && exit 1 || exit 0
fi

printf "%s\n" "$CONTENT" > docs/stale_docs.json
STALE_COUNT=$(jq '.stale | length' docs/stale_docs.json)

if [ "$MODE" = "schedule" ]; then
  echo "Schedule mode: ${STALE_COUNT} stale docs (warning only)."
  exit 0
fi

CRITICAL_STALE=$(jq '[.stale[]? | select(.critical == true)] | length' docs/stale_docs.json)
if [ "$CRITICAL_STALE" -gt 0 ]; then
  echo "Critical stale docs detected in release gate mode."
  jq -r '.stale[]? | select(.critical == true) | "- \(.doc) \(.section // ""): \(.reason)"' docs/stale_docs.json
  exit 1
fi

echo "Doc gate passed in release mode."
