#!/usr/bin/env bash
# Symlink every skill in this repo into the agents' skill directories so the same
# SKILL.md files serve Claude Code (~/.claude/skills) and Codex (~/.codex/skills).
# Idempotent: re-running refreshes links; existing non-good-fellow skills are left
# alone, and a real directory with the same name is never overwritten.

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGETS=("$HOME/.claude/skills" "$HOME/.codex/skills")

for target in "${TARGETS[@]}"; do
  mkdir -p "$target"
  for skill_dir in "$REPO_DIR"/skills/*/; do
    name="$(basename "$skill_dir")"
    link="$target/$name"
    if [[ -L "$link" ]]; then
      ln -sfn "${skill_dir%/}" "$link"
      echo "refreshed $link"
    elif [[ -e "$link" ]]; then
      echo "SKIP: $link exists and is not a symlink (not touching it)" >&2
    else
      ln -s "${skill_dir%/}" "$link"
      echo "linked   $link"
    fi
  done
done

chmod +x "$REPO_DIR"/scripts/*.sh
echo
echo "Installed. Next step: run the 'onboard' skill (e.g. /onboard in Claude Code)"
echo "to set up gh login, your instruction gist, and the 30-minute cron job."
