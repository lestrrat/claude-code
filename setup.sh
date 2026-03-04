#!/bin/bash
set -eu

this_dir="$(cd "$(dirname "$0")"; pwd)"

echo "Setting up Claude Code symlinks..."

mkdir -p ~/.claude

for item in CLAUDE.md docs skills settings.json; do
  target="$this_dir/$item"
  link="$HOME/.claude/$item"

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
