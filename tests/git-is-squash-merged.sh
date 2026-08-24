#!/bin/bash
# Scenario tests for scripts/git-is-squash-merged.
#
# Usage: tests/git-is-squash-merged.sh [script-under-test]
#
# Defaults to the sibling scripts/git-is-squash-merged. Pass a path to compare
# another copy, e.g. the installed ~/.claude/scripts/git-is-squash-merged.
#
# Each case builds a throwaway repo under the system temp dir and asserts the exit
# code: 0 merged, 1 not merged. Exits non-zero if any case fails.
#
# The cases matter because the verdict drives branch deletion in the
# `git-cleanup-merged` skill. False negatives leave dead branches around; false
# positives destroy work. Both directions are covered, and both must stay covered.
set -uo pipefail

DEFAULT_SCRIPT="$(cd "$(dirname "$0")/../scripts" && pwd)/git-is-squash-merged"
SCRIPT_ARG="${1:-$DEFAULT_SCRIPT}"
SCRIPT="$(cd "$(dirname "$SCRIPT_ARG")" && pwd)/$(basename "$SCRIPT_ARG")"

if [ ! -x "$SCRIPT" ]; then
  echo "error: not executable: $SCRIPT" >&2
  exit 2
fi
echo "testing: $SCRIPT"
PASS=0
FAIL=0

# All scratch repos live under one root so the trap can remove them together.
# newrepo runs inside a command substitution, so it must not rely on a counter in
# the parent shell: a subshell increment would be lost and every case would reuse
# one directory. mktemp picks the unique name instead.
WORK_ROOT=$(mktemp -d)
trap 'rm -rf "$WORK_ROOT"' EXIT

newrepo() {
  local r
  r=$(mktemp -d -p "$WORK_ROOT")
  git -C "$r" init -q -b main .
  git -C "$r" config user.email t@t
  git -C "$r" config user.name t
  printf 'l1\nl2\nl3\n' > "$r/f.txt"
  git -C "$r" add -A
  git -C "$r" commit -qm base
  printf '%s' "$r"
}

check() {
  local name="$1" repo="$2" want="$3" out rc=0
  out=$(cd "$repo" && "$SCRIPT" main feat 2>&1) || rc=$?
  if [ "$rc" = "$want" ]; then
    PASS=$((PASS + 1))
    printf 'PASS  %-46s rc=%s %s\n' "$name" "$rc" "$out"
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL  %-46s want rc=%s got rc=%s %s\n' "$name" "$want" "$rc" "$out"
  fi
}

# feat: two commits touching f.txt, forked from base.
mkfeat() {
  local r="$1"
  git -C "$r" checkout -qb feat
  printf 'l1\nl2-branch\nl3\n' > "$r/f.txt"
  git -C "$r" commit -qam "feat c1"
  printf 'l1\nl2-branch\nl3\nl4\n' > "$r/f.txt"
  git -C "$r" commit -qam "feat c2"
  git -C "$r" checkout -q main
}

squash_in() {
  local r="$1"
  git -C "$r" merge -q --squash feat >/dev/null 2>&1
  git -C "$r" commit -qm "squash: feat (#1)"
}

advance_same_file() {
  local r="$1"
  printf 'l1\nl2-branch-edited\nl3\nl4\nl5\n' > "$r/f.txt"
  git -C "$r" commit -qam "later work on same file"
}

advance_other_file() {
  local r="$1"
  echo x > "$r/other.txt"
  git -C "$r" add -A
  git -C "$r" commit -qm "unrelated work"
}

# 1. squashed, target untouched since.
R=$(newrepo); mkfeat "$R"; squash_in "$R"
check "squashed, target untouched" "$R" 0

# 2. squashed, target then advanced over the SAME file (the reported regression).
R=$(newrepo); mkfeat "$R"; squash_in "$R"; advance_same_file "$R"
check "squashed, target advanced on same file" "$R" 0

# 3. squashed, target then advanced on an unrelated file.
R=$(newrepo); mkfeat "$R"; squash_in "$R"; advance_other_file "$R"
check "squashed, target advanced elsewhere" "$R" 0

# 4. squashed, then many later commits over the same file.
R=$(newrepo); mkfeat "$R"; squash_in "$R"; advance_same_file "$R"; advance_other_file "$R"
printf 'rewritten\n' > "$R/f.txt"; git -C "$R" commit -qam "rewrite f.txt"
check "squashed, file later rewritten" "$R" 0

# 5. never merged.
R=$(newrepo); mkfeat "$R"; advance_other_file "$R"
check "never merged" "$R" 1

# 6. squashed then reverted — work is gone from target.
R=$(newrepo); mkfeat "$R"; squash_in "$R"
git -C "$R" revert --no-edit HEAD >/dev/null 2>&1
check "squashed then reverted" "$R" 1

# 7. squashed, reverted, re-applied — work is present again.
R=$(newrepo); mkfeat "$R"; squash_in "$R"
git -C "$R" revert --no-edit HEAD >/dev/null 2>&1
git -C "$R" merge -q --squash feat >/dev/null 2>&1
git -C "$R" commit -qm "re-apply feat"
check "squashed, reverted, re-applied" "$R" 0

# 8. squashed then reverted, and target advanced afterwards.
R=$(newrepo); mkfeat "$R"; squash_in "$R"
git -C "$R" revert --no-edit HEAD >/dev/null 2>&1
advance_other_file "$R"
check "reverted, then target advanced" "$R" 1

# 9. rebase-merge shape: each branch commit landed individually. The unrelated
# commit first is what stops the cherry-pick fast-forwarding into identical shas.
R=$(newrepo); mkfeat "$R"; advance_other_file "$R"
git -C "$R" cherry-pick feat~1 feat >/dev/null 2>&1
advance_same_file "$R"
check "rebase-merged, target advanced" "$R" 0

# 10. rebase-merge shape, then reverted one commit at a time.
R=$(newrepo); mkfeat "$R"; advance_other_file "$R"
git -C "$R" cherry-pick feat~1 feat >/dev/null 2>&1
git -C "$R" revert --no-edit HEAD HEAD~1 >/dev/null 2>&1
check "rebase-merged then reverted per commit" "$R" 1

# 10b. rebase-merge shape, then reverted as one combined commit.
R=$(newrepo); mkfeat "$R"; advance_other_file "$R"
git -C "$R" cherry-pick feat~1 feat >/dev/null 2>&1
git -C "$R" revert --no-edit --no-commit HEAD HEAD~1 >/dev/null 2>&1
git -C "$R" commit -qm "revert feat entirely"
check "rebase-merged then reverted in one commit" "$R" 1

# 11. branch has extra unmerged work on top of a squashed base.
R=$(newrepo); mkfeat "$R"; squash_in "$R"; advance_same_file "$R"
git -C "$R" checkout -q feat
echo new > "$R/g.txt"; git -C "$R" add -A; git -C "$R" commit -qm "unmerged extra"
git -C "$R" checkout -q main
check "branch has extra unmerged commit" "$R" 1

# 12. branch identical to target (ancestor, nothing to merge).
R=$(newrepo); git -C "$R" branch feat
check "branch is an ancestor of target" "$R" 0

# 13. ordinary merge commit, target advanced.
R=$(newrepo); mkfeat "$R"
git -C "$R" merge -q --no-ff -m "merge feat" feat
advance_same_file "$R"
check "merge-committed, target advanced" "$R" 0

# 14. two branches squashed in sequence, both touching the same file.
R=$(newrepo); mkfeat "$R"; squash_in "$R"
git -C "$R" checkout -qb feat2
printf 'l1\nl2-branch\nl3\nl4\nl5-from-feat2\n' > "$R/f.txt"
git -C "$R" commit -qam "feat2 c1"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash feat2 >/dev/null 2>&1
git -C "$R" commit -qm "squash: feat2 (#2)"
check "earlier branch, later branch on same file" "$R" 0

# 15. branch renames a file; target advances over the renamed path afterwards.
R=$(newrepo); git -C "$R" checkout -qb feat
git -C "$R" mv f.txt renamed.txt
printf 'l1\nl2-branch\nl3\n' > "$R/renamed.txt"
git -C "$R" commit -qam "feat renames f.txt"
git -C "$R" checkout -q main
squash_in "$R"
printf 'l1\nl2-branch\nl3\nl4\n' > "$R/renamed.txt"
git -C "$R" commit -qam "later work on renamed path"
check "branch renamed a file, target advanced" "$R" 0

# 16. branch carries an internal merge, then is squashed; target advances.
R=$(newrepo)
git -C "$R" checkout -qb side
echo side > "$R/side.txt"; git -C "$R" add -A; git -C "$R" commit -qm "side work"
git -C "$R" checkout -q main
mkfeat "$R"
git -C "$R" checkout -q feat
git -C "$R" merge -q --no-ff -m "merge side into feat" side
git -C "$R" checkout -q main
squash_in "$R"
advance_same_file "$R"
check "branch with internal merge, target advanced" "$R" 0

# 17. run from a subdirectory — pathspec scoping must stay repo-root anchored.
R=$(newrepo)
mkdir -p "$R/sub"
echo nested > "$R/sub/deep.txt"; git -C "$R" add -A; git -C "$R" commit -qm "add sub"
mkfeat "$R"; squash_in "$R"; advance_same_file "$R"
SUBRC=0
(cd "$R/sub" && "$SCRIPT" main feat >/dev/null 2>&1) || SUBRC=$?
if [ "$SUBRC" = 0 ]; then
  PASS=$((PASS + 1)); printf 'PASS  %-46s rc=0\n' "invoked from a subdirectory"
else
  FAIL=$((FAIL + 1)); printf 'FAIL  %-46s want rc=0 got rc=%s\n' "invoked from a subdirectory" "$SUBRC"
fi

# 18. unmerged branch whose files the target churned heavily — must stay unmerged.
R=$(newrepo); mkfeat "$R"
printf 'totally\ndifferent\ncontent\n' > "$R/f.txt"; git -C "$R" commit -qam "main churn 1"
printf 'more\nchurn\nhere\nl4\n' > "$R/f.txt"; git -C "$R" commit -qam "main churn 2"
check "unmerged branch, target churned same file" "$R" 1

# 19. two unrelated branches, one merged: the other must not inherit the verdict.
R=$(newrepo)
git -C "$R" checkout -qb other
echo other > "$R/other-only.txt"; git -C "$R" add -A; git -C "$R" commit -qm "other work"
git -C "$R" checkout -q main
mkfeat "$R"; squash_in "$R"; advance_same_file "$R"
OTHRC=0
(cd "$R" && "$SCRIPT" main other >/dev/null 2>&1) || OTHRC=$?
if [ "$OTHRC" = 1 ]; then
  PASS=$((PASS + 1)); printf 'PASS  %-46s rc=1\n' "sibling branch stays unmerged"
else
  FAIL=$((FAIL + 1)); printf 'FAIL  %-46s want rc=1 got rc=%s\n' "sibling branch stays unmerged" "$OTHRC"
fi

echo "----"
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" = 0 ]
