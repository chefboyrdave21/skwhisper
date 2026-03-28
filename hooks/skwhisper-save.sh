#!/usr/bin/env bash
# SKWhisper Session Save Hook for Claude Code (Linux / macOS)
# Triggers SKWhisper digest after session ends to capture new conversation.
#
# Hook type: SessionEnd
# Input (stdin): JSON with session_id, reason
# Exit 0 always — never block session end
set -euo pipefail

AGENT="${SKCAPSTONE_AGENT:-lumina}"
SKWHISPER_DIR=""

for D in "${HOME}/clawd/projects/skwhisper" "${HOME}/projects/skwhisper" "${HOME}/skwhisper"; do
  [ -f "${D}/skwhisper/__main__.py" ] && SKWHISPER_DIR="$D" && break
done

[ -z "$SKWHISPER_DIR" ] && exit 0

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
REASON=$(echo "$INPUT" | jq -r '.reason // "unknown"' 2>/dev/null || echo "unknown")
SHORT_SID="${SESSION_ID:0:8}"

# Run one digest cycle in background (don't block session exit)
(
  cd "$SKWHISPER_DIR"
  PYTHONPATH="$SKWHISPER_DIR" python3 -m skwhisper digest >/dev/null 2>&1
  PYTHONPATH="$SKWHISPER_DIR" python3 -m skwhisper curate >/dev/null 2>&1
) &

exit 0
