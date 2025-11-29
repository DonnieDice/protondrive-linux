#!/usr/bin/env bash

# Arguments: command as a string
COMMAND="$*"
LOG_FILE="./logs/command-$(date +%s).json"

# Create logs directory if it doesn't exist
mkdir -p logs

# Run command
# Use setsid to prevent SIGHUP termination and run in a new session
# The output of the command is captured first
OUTPUT=$(setsid bash -c "$COMMAND" 2>&1)
EXIT_CODE=$?

# Write JSON log
# Use python to correctly escape the output string for JSON
JSON_OUTPUT=$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<< "$OUTPUT")

# Check for manual intervention required condition: non-zero exit code and empty output
if [[ $EXIT_CODE -ne 0 && -z "$OUTPUT" ]]; then
    echo "{\"command\": \"$COMMAND\", \"exit_code\": $EXIT_CODE, \"output\": $JSON_OUTPUT, \"manual_intervention_required\": true}" > "$LOG_FILE"
else
    echo "{\"command\": \"$COMMAND\", \"exit_code\": $EXIT_CODE, \"output\": $JSON_OUTPUT}" > "$LOG_FILE"
fi

# Exit with the command's original exit code
exit $EXIT_CODE