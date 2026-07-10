#!/bin/bash
set -eu

this_dir="$(cd "$(dirname "$0")"; pwd)"
claude_dir="${1:-$HOME/.claude}"

echo "Setting up Claude Code symlinks in $claude_dir..."

mkdir -p "$claude_dir"

for item in CLAUDE.md.global docs scripts skills settings.json; do
  target="$this_dir/$item"
  link_name="$item"
  if [ "$item" = "CLAUDE.md.global" ]; then
    link_name="CLAUDE.md"
  fi
  link="$claude_dir/$link_name"

  if [ -L "$link" ]; then
    rm "$link"
  elif [ -e "$link" ]; then
    echo "WARNING: $link already exists and is not a symlink; skipping" >&2
    continue
  fi

  ln -s "$target" "$link"
  echo "Linked $link -> $target"
done

echo "Done."
