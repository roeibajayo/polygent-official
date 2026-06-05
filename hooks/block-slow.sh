#!/bin/bash
# PreToolUse:Bash hook that blocks slow find+exec patterns.
# Detects: find ... -exec <anything>

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Detect: any "find" command used as the main command (not as part of grep/rg)
if echo "$CMD" | grep -qE '(^|&&\s*|;\s*|\|\s*)\s*find\s+'; then
  REASON="Blocked: find command is slow. Use dedicated tools (Grep, Glob) instead."

  jq -n \
    --arg reason "$REASON" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }'
  exit 0
fi

# Detect: grep -r without --exclude-dir=node_modules
if echo "$CMD" | grep -qE '\bgrep\s+.*-r' && ! echo "$CMD" | grep -q -- '--exclude-dir=node_modules'; then
  REASON="Blocked: grep -r without --exclude-dir=node_modules is very slow. Use the Grep tool instead."

  jq -n \
    --arg reason "$REASON" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": $reason
      }
    }'
  exit 0
fi

exit 0
