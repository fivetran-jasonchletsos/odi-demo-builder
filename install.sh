#!/usr/bin/env bash
# Install the odi-demo-builder skill into ~/.claude/skills in the layout Claude Code expects.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/skills/odi-demo-builder/SKILL.md"
DEST_DIR="$HOME/.claude/skills/odi-demo-builder"
DEST="$DEST_DIR/SKILL.md"

if [[ ! -f "$SRC" ]]; then
  echo "error: cannot find $SRC" >&2
  exit 1
fi

# Remove any old loose file that would shadow / confuse discovery.
if [[ -f "$HOME/.claude/skills/odi-demo-builder.md" ]]; then
  echo "removing stale loose file ~/.claude/skills/odi-demo-builder.md"
  rm -f "$HOME/.claude/skills/odi-demo-builder.md"
fi

mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST"

echo "installed: $DEST"
echo "restart Claude Code, then verify with: claude skill list | grep odi-demo-builder"
