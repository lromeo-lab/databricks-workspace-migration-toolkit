#!/usr/bin/env bash
# PHASE 2 — SOURCE workspace web terminal.
# Clones the repo into a staging worktree, copies every mapped folder into it
# (originals untouched), validates each copy, then commits + pushes to main.
# Finally, in ephemeral mode, tears down the SOURCE Git credential by id.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_vars GIT_URL GIT_BRANCH GIT_WORKTREE GIT_STAGING_PARENT \
             GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL

echo "== Preparing staging worktree: $GIT_WORKTREE =="
mkdir -p "$GIT_STAGING_PARENT"
if [ ! -e "$GIT_WORKTREE/.git" ]; then
  git clone --branch "$GIT_BRANCH" --single-branch "$GIT_URL" "$GIT_WORKTREE"
fi
git -C "$GIT_WORKTREE" config user.name "$GIT_AUTHOR_NAME"
git -C "$GIT_WORKTREE" config user.email "$GIT_AUTHOR_EMAIL"
git -C "$GIT_WORKTREE" checkout "$GIT_BRANCH"
git -C "$GIT_WORKTREE" pull --ff-only origin "$GIT_BRANCH" || true

echo "== Packaging folders from the map =="
while IFS=$'\t' read -r src_abs repo_rel dest_abs; do
  [ -z "${src_abs:-}" ] && continue
  guard_rel "$repo_rel"
  [ -d "$src_abs" ] || { echo "ERROR: missing source folder: $src_abs" >&2; exit 1; }
  echo ">> $src_abs  ->  $GIT_WORKTREE/$repo_rel"
  copy_tree "$src_abs" "$GIT_WORKTREE/$repo_rel"
  python3 "$MIGRATION_HOME/lib/validate_copy.py" "$src_abs" "$GIT_WORKTREE/$repo_rel" || exit 1
  # Saved-query sanity check.
  s=$(find "$src_abs" -type f -name '*.dbquery.ipynb' | wc -l | tr -d ' ')
  t=$(find "$GIT_WORKTREE/$repo_rel" -type f -name '*.dbquery.ipynb' | wc -l | tr -d ' ')
  echo "   dbquery files: source=$s target=$t"
  [ "$s" -eq "$t" ] || { echo "ERROR: query count mismatch in $repo_rel" >&2; exit 1; }
done < <(read_map)

echo "== Commit and push to $GIT_BRANCH =="
cd "$GIT_WORKTREE"
git add --all
if git diff --cached --quiet; then
  echo "No changes to commit (repo already up to date)."
else
  git diff --cached --stat
  git commit -m "Package workspace folders for migration ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
  git push origin "$GIT_BRANCH"
fi
echo "SOURCE_COMMIT=$(git rev-parse HEAD)"

# --- Ephemeral teardown: source Git credential no longer needed after push ---
if [ "$EPHEMERAL_ENABLED" = "true" ] && [ "$KEEP_EPHEMERAL" != "true" ]; then
  echo "== Tearing down the SOURCE ephemeral Git credential =="
  delete_git_credential "$SRC_CRED_ID"
fi
echo "DONE: source packaging complete."
