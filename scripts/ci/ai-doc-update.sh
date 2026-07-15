#!/usr/bin/env bash
set -euo pipefail

AFFECTED_JSON="${AFFECTED_JSON:-docs/affected_docs.json}"
STALE_JSON="${STALE_JSON:-docs/stale_docs.json}"
MODEL="${DOC_AUDIT_MODEL:-deepseek-chat}"
API_URL="${DOC_AUDIT_API_URL:-https://api.deepseek.com/chat/completions}"

if [ ! -s "$AFFECTED_JSON" ] || [ "$(jq 'length' "$AFFECTED_JSON" 2>/dev/null || echo 0)" = "0" ]; then
  echo "No affected docs for update."
  exit 0
fi

if [ -z "${DEEPSEEK_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "No LLM API key configured; doc update skipped."
  exit 0
fi

TOKEN="${DEEPSEEK_API_KEY:-${OPENAI_API_KEY:-}}"
WORK_ITEMS=$(mktemp)

if [ -s "$STALE_JSON" ] && jq -e '.stale | length > 0' "$STALE_JSON" >/dev/null 2>&1; then
  jq -c '.stale[] | {path:.doc, section:.section, critical:(.critical // false), update_mode:"section"}' "$STALE_JSON" > "$WORK_ITEMS"
else
  jq -c '[.[]][] | {path:.path, section:(.section // null), critical:(.critical // false), update_mode:(.update_mode // "section")} | select(.path != null)' "$AFFECTED_JSON" |
    sort -u > "$WORK_ITEMS"
fi

while IFS= read -r target; do
  DOC_PATH=$(printf "%s" "$target" | jq -r '.path')
  SECTION=$(printf "%s" "$target" | jq -r '.section // empty')
  UPDATE_MODE=$(printf "%s" "$target" | jq -r '.update_mode // "section"')

  if [ ! -f "$DOC_PATH" ]; then
    echo "Skipping missing doc target: $DOC_PATH"
    continue
  fi

  if [ "$UPDATE_MODE" != "file" ] && [ -n "$SECTION" ]; then
    if ! grep -Fq "<!-- BEGIN SECTION: ${SECTION} -->" "$DOC_PATH" ||
       ! grep -Fq "<!-- END SECTION: ${SECTION} -->" "$DOC_PATH"; then
      echo "Skipping $DOC_PATH section '$SECTION': section markers are not present."
      continue
    fi
  fi

  DOC_CONTENT=$(cat "$DOC_PATH")
  PROMPT=$(cat <<PROMPT_EOF
You are updating repository documentation.

Return only the updated Markdown content inside one fenced markdown block.
Do not include explanation outside the fenced block.

Scope:
- file: ${DOC_PATH}
- section: ${SECTION:-<entire file>}
- update_mode: ${UPDATE_MODE}

Use the code diff and mapping context below. Preserve the existing tone and avoid adding claims not supported by the diff.

CODE DIFFS:
${DIFFS:-}

MAPPING TARGET:
${target}

CURRENT DOCUMENT CONTENT:
${DOC_CONTENT}
PROMPT_EOF
)

  RESPONSE=$(curl -sS "$API_URL" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{
      model: $model,
      messages: [{"role": "user", "content": $prompt}],
      temperature: 0.1
    }')")

  CONTENT=$(printf "%s" "$RESPONSE" | jq -r '.choices[0].message.content // empty')
  if [ -z "$CONTENT" ]; then
    echo "Skipping $DOC_PATH: empty LLM response"
    continue
  fi

  MARKDOWN=$(printf "%s" "$CONTENT" | python3 -c '
import re, sys
text = sys.stdin.read()
match = re.search(r"```(?:markdown|md)?\s*\n(.*?)\n```", text, re.S)
print((match.group(1) if match else text).rstrip())
')

  if [ "$UPDATE_MODE" = "file" ] || [ -z "$SECTION" ]; then
    printf "%s\n" "$MARKDOWN" | python3 scripts/ci/apply-doc-patch.py --path "$DOC_PATH" --mode file
  else
    printf "%s\n" "$MARKDOWN" | python3 scripts/ci/apply-doc-patch.py --path "$DOC_PATH" --mode section --section "$SECTION"
  fi
done < "$WORK_ITEMS"

rm -f "$WORK_ITEMS"
