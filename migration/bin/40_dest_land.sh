#!/usr/bin/env bash
# PHASE 4 — DEST workspace web terminal.
# Lands each mapped folder at its original absolute path so existing references
# resolve unchanged. Existing targets are backed up (renamed), never overwritten.
# This phase is a pure WSFS copy from the already-cloned worktree: it uses NO Git
# and NO Git credential (the dest credential was torn down at the end of phase 3).
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_vars GIT_WORKTREE

echo "== Landing folders at their destination paths =="
while IFS=$'\t' read -r src_abs repo_rel dest_abs; do
  [ -z "${src_abs:-}" ] && continue
  guard_rel "$repo_rel"
  target="${dest_abs:-$src_abs}"           # column 3, or column 1 if omitted
  src="$GIT_WORKTREE/$repo_rel"
  [ -d "$src" ] || { echo "ERROR: not in worktree: $repo_rel" >&2; exit 1; }
  if [ -e "$target" ]; then
    bak="${target}.bak.$(date +%Y%m%d%H%M%S)"
    echo ">> existing $target  ->  backup $bak"
    mv "$target" "$bak"
  fi
  echo ">> landing $repo_rel  ->  $target"
  copy_tree "$src" "$target"
  python3 "$MIGRATION_HOME/lib/validate_copy.py" "$src" "$target" || exit 1
done < <(read_map)

echo "NOTE: open each .dbquery.ipynb / .lvdash.json in the DEST UI and repoint the SQL warehouse."
echo "DONE: landing complete. Remove the staging worktree once validated:"
echo "      rm -rf \"$GIT_WORKTREE\""
