#!/bin/bash
# Deny banned Bash patterns: compound commands and git -C.

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

# Ban multi-line commands
LINE_COUNT=$(echo "$STRIPPED" | wc -l)
if [ "$LINE_COUNT" -gt 1 ]; then
  deny "Multi-line commands are banned. Use separate Bash calls, one command each."
fi

# Ban compound commands
if echo "$STRIPPED" | grep -qE '&&|\|\||;'; then
  deny "Compound commands (&&, ||, ;) are banned. Use separate Bash calls."
fi

# Ban echo "EXIT: $?"
if echo "$COMMAND" | grep -qF 'echo "EXIT: $?"'; then
  deny 'echo "EXIT: $?" is banned.'
fi

# Ban git -C
if echo "$STRIPPED" | grep -qE '^git\s+-C\b'; then
  deny "git -C is banned. Use cd to change directory first, then run git."
fi
