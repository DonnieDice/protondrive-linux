1|#!/usr/bin/env bash
2|set -euo pipefail
3|
4|AFFECTED_JSON="${AFFECTED_JSON:-docs/affected_docs.json}"
5|STALE_JSON="${STALE_JSON:-docs/stale_docs.json}"
6|MODEL="${DOC_AUDIT_MODEL:-deepseek-chat}"
7|API_URL="${DOC_AUDIT_API_URL:-https://api.deepseek.com/chat/completions}"
8|
9|if [ ! -s "$AFFECTED_JSON" ] || [ "$(jq 'length' "$AFFECTED_JSON" 2>/dev/null || echo 0)" = "0" ]; then
10|  echo "No affected docs for update."
11|  exit 0
12|fi
13|
14|if [ -z "${DEEPSEEK_API_KEY:-}" ] && [ -z "${OPENAI_API_KEY:-}" ]; then
15|  echo "No LLM API key configured; doc update skipped."
16|  exit 0
17|fi
18|
19|TOKEN="${DEEPSEEK_API_KEY:-${OPENAI_API_KEY:-}}"
20|WORK_ITEMS=$(mktemp)
21|
22|if [ -s "$STALE_JSON" ] && jq -e '.stale | length > 0' "$STALE_JSON" >/dev/null 2>&1; then
23|  jq -c '.stale[] | {path:.doc, section:.section, critical:(.critical // false), update_mode:"section"}' "$STALE_JSON" > "$WORK_ITEMS"
24|else
25|  jq -c '[.[]][] | {path:.path, section:(.section // null), critical:(.critical // false), update_mode:(.update_mode // "section")} | select(.path != null)' "$AFFECTED_JSON" |
26|    sort -u > "$WORK_ITEMS"
27|fi
28|
29|while IFS= read -r target; do
30|  DOC_PATH=$(printf "%s" "$target" | jq -r '.path')
31|  SECTION=$(printf "%s" "$target" | jq -r '.section // empty')
32|  UPDATE_MODE=$(printf "%s" "$target" | jq -r '.update_mode // "section"')
33|
34|  if [ ! -f "$DOC_PATH" ]; then
35|    echo "Skipping missing doc target: $DOC_PATH"
36|    continue
37|  fi
38|
39|  if [ "$UPDATE_MODE" != "file" ] && [ -n "$SECTION" ]; then
40|    if ! grep -Fq "<!-- BEGIN SECTION: ${SECTION} -->" "$DOC_PATH" ||
41|       ! grep -Fq "<!-- END SECTION: ${SECTION} -->" "$DOC_PATH"; then
42|      echo "Skipping $DOC_PATH section '$SECTION': section markers are not present."
43|      continue
44|    fi
45|  fi
46|
47|  DOC_CONTENT=$(cat "$DOC_PATH")
48|  PROMPT=$(cat <<PROMPT_EOF
49|You are updating repository documentation.
50|
51|Return only the updated Markdown content inside one fenced markdown block.
52|Do not include explanation outside the fenced block.
53|
54|Scope:
55|- file: ${DOC_PATH}
56|- section: ${SECTION:-<entire file>}
57|- update_mode: ${UPDATE_MODE}
58|
59|Use the code diff and mapping context below. Preserve the existing tone and avoid adding claims not supported by the diff.
60|
61|CODE DIFFS:
62|${DIFFS:-}
63|
64|MAPPING TARGET:
65|${target}
66|
67|CURRENT DOCUMENT CONTENT:
68|${DOC_CONTENT}
69|PROMPT_EOF
70|)
71|
72|  RESPONSE=$(curl -sS "$API_URL" \
73|    -H "Authorization: Bearer ${TOKEN} \
74|    -H "Content-Type: application/json" \
75|    -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" '{
76|      model: $model,
77|      messages: [{"role": "user", "content": $prompt}],
78|      temperature: 0.1
79|    }')")
80|
81|  CONTENT=$(printf "%s" "$RESPONSE" | jq -r '.choices[0].message.content // empty')
82|  if [ -z "$CONTENT" ]; then
83|    echo "Skipping $DOC_PATH: empty LLM response"
84|    continue
85|  fi
86|
87|  MARKDOWN=$(printf "%s" "$CONTENT" | python3 -c '
88|import re, sys
89|text = sys.stdin.read()
90|match = re.search(r"```(?:markdown|md)?\s*\n(.*?)\n```", text, re.S)
91|print((match.group(1) if match else text).rstrip())
92|')
93|
94|  if [ "$UPDATE_MODE" = "file" ] || [ -z "$SECTION" ]; then
95|    printf "%s\n" "$MARKDOWN" | python3 scripts/ci/apply-doc-patch.py --path "$DOC_PATH" --mode file
96|  else
97|    printf "%s\n" "$MARKDOWN" | python3 scripts/ci/apply-doc-patch.py --path "$DOC_PATH" --mode section --section "$SECTION"
98|  fi
99|done < "$WORK_ITEMS"
100|
101|rm -f "$WORK_ITEMS"
102|