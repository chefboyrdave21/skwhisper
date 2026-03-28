#!/usr/bin/env bash
# SKWhisper Context Injection Hook for Claude Code (Linux / macOS)
# Injects whisper.md subconscious context on SessionStart.
#
# Hook type: SessionStart (startup, compact, resume)
# Input (stdin): JSON with session_id, source
# Output (stdout): Injected into Claude's context
# Exit 0 always — never block session start
set -euo pipefail

AGENT="${SKCAPSTONE_AGENT:-lumina}"
WHISPER_FILE="${HOME}/.skcapstone/agents/${AGENT}/skwhisper/whisper.md"
SKWHISPER_DIR=""

# Find skwhisper project for on-demand curation
for D in "${HOME}/clawd/projects/skwhisper" "${HOME}/projects/skwhisper" "${HOME}/skwhisper"; do
  [ -f "${D}/skwhisper/__main__.py" ] && SKWHISPER_DIR="$D" && break
done

# If whisper.md is stale (>2h old), try refreshing
if [ -f "$WHISPER_FILE" ]; then
  FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$WHISPER_FILE" 2>/dev/null || stat -f %m "$WHISPER_FILE" 2>/dev/null || echo 0) ))
  if [ "$FILE_AGE" -gt 7200 ] && [ -n "$SKWHISPER_DIR" ]; then
    # Refresh in background — don't block session start
    (cd "$SKWHISPER_DIR" && PYTHONPATH="$SKWHISPER_DIR" python3 -m skwhisper curate >/dev/null 2>&1 &)
  fi
fi

# Output whisper context if available
if [ -f "$WHISPER_FILE" ] && [ -s "$WHISPER_FILE" ]; then
  echo "--- SKWHISPER SUBCONSCIOUS CONTEXT ---"
  echo "Agent: ${AGENT}"
  echo "Source: ${WHISPER_FILE}"
  echo "Updated: $(stat -c %y "$WHISPER_FILE" 2>/dev/null || stat -f '%Sm' "$WHISPER_FILE" 2>/dev/null || echo unknown)"
  echo ""
  cat "$WHISPER_FILE"
  echo ""
  echo "--- END SKWHISPER ---"
else
  echo "--- SKWHISPER: No whisper.md available for agent ${AGENT} ---"
fi

exit 0
