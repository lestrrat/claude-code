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

# Install the repo's own git hooks. Symlinked into whatever core.hooksPath
# resolves to, so an existing custom hooks directory is respected.
hooks_dir="$(git -C "$this_dir" config --get core.hooksPath || true)"
if [ -z "$hooks_dir" ]; then
  hooks_dir="$(git -C "$this_dir" rev-parse --git-common-dir)/hooks"
fi

if [ -d "$hooks_dir" ]; then
  hook_link="$hooks_dir/pre-commit"
  if [ -L "$hook_link" ]; then
    rm "$hook_link"
  fi

  if [ -e "$hook_link" ]; then
    echo "WARNING: $hook_link already exists and is not a symlink; skipping" >&2
  else
    ln -s "$this_dir/githooks/pre-commit" "$hook_link"
    echo "Linked $hook_link -> $this_dir/githooks/pre-commit"
  fi
else
  echo "WARNING: git hooks dir $hooks_dir not found; skipping pre-commit install" >&2
fi

echo "Done."
