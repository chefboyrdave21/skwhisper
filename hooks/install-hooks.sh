#!/usr/bin/env bash
# Install SKWhisper hooks into Claude Code settings.json
# Works on Linux and macOS. For Windows, run install-hooks.ps1 instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SETTINGS="${HOME}/.claude/settings.json"

echo "═══ SKWhisper Hook Installer (Linux/macOS) ═══"
echo ""

# Make hooks executable
chmod +x "${SCRIPT_DIR}/skwhisper-inject.sh"
chmod +x "${SCRIPT_DIR}/skwhisper-save.sh"
echo "✓ Hooks marked executable"

# Verify Claude Code settings exist
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  echo "✗ Claude Code settings not found at ${CLAUDE_SETTINGS}"
  echo "  Run 'claude' at least once first, or create the file manually."
  exit 1
fi

# Backup current settings
cp "$CLAUDE_SETTINGS" "${CLAUDE_SETTINGS}.bak.$(date +%Y%m%d%H%M)"
echo "✓ Backed up current settings"

# Use Python for reliable JSON manipulation
python3 << PYEOF
import json
import sys

settings_path = "${CLAUDE_SETTINGS}"
inject_sh = "${SCRIPT_DIR}/skwhisper-inject.sh"
save_sh = "${SCRIPT_DIR}/skwhisper-save.sh"

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

# --- SessionStart: add skwhisper-inject ---
ss_hooks = hooks.setdefault("SessionStart", [])
# Check if already installed
inject_exists = any(
    any(h.get("command", "").endswith("skwhisper-inject.sh") for h in entry.get("hooks", []))
    for entry in ss_hooks
)
if not inject_exists:
    ss_hooks.append({
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": inject_sh,
            "timeout": 15
        }]
    })
    print("✓ Added SKWhisper inject hook to SessionStart")
else:
    print("→ SKWhisper inject hook already in SessionStart (skipped)")

# --- SessionEnd: add skwhisper-save ---
se_hooks = hooks.setdefault("SessionEnd", [])
save_exists = any(
    any(h.get("command", "").endswith("skwhisper-save.sh") for h in entry.get("hooks", []))
    for entry in se_hooks
)
if not save_exists:
    se_hooks.append({
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": save_sh,
            "timeout": 30
        }]
    })
    print("✓ Added SKWhisper save hook to SessionEnd")
else:
    print("→ SKWhisper save hook already in SessionEnd (skipped)")

# --- PreCompact: also inject fresh context ---
pc_hooks = hooks.setdefault("PreCompact", [])
pc_exists = any(
    any(h.get("command", "").endswith("skwhisper-inject.sh") for h in entry.get("hooks", []))
    for entry in pc_hooks
)
if not pc_exists:
    pc_hooks.append({
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": inject_sh,
            "timeout": 15
        }]
    })
    print("✓ Added SKWhisper inject hook to PreCompact")
else:
    print("→ SKWhisper inject hook already in PreCompact (skipped)")

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("✓ Settings saved")
PYEOF

echo ""
echo "═══ Installation Complete ═══"
echo ""
echo "SKWhisper will now:"
echo "  • Inject whisper.md context on every session start"
echo "  • Re-inject fresh context after compaction"
echo "  • Trigger digest + curate when sessions end"
echo ""
echo "Test: claude --print 'What does your SKWhisper subconscious say?'"
