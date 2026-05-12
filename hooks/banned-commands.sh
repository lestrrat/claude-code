#!/bin/bash
# Deny banned Bash patterns.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Strip quoted strings to avoid false positives
STRIPPED=$(echo "$COMMAND" | sed -e "s/'[^']*'//g" -e 's/"[^"]*"//g')

# Ban echo "EXIT: $?"
if echo "$COMMAND" | grep -qF 'echo "EXIT: $?"'; then
  deny 'echo "EXIT: $?" is banned.'
fi