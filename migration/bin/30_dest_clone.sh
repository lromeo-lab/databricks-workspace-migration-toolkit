#!/usr/bin/env bash
# PHASE 3 — DEST workspace web terminal.
# Clones (or fast-forwards) the repo into the destination staging worktree and
# verifies every mapped folder is present. This is the LAST phase that uses Git
# in the destination (phase 40 is a pure WSFS copy), so in ephemeral mode the
# DEST Git credential is torn down here, by id, once the clone is verified.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_vars GIT_URL GIT_BRANCH GIT_WORKTREE GIT_STAGING_PARENT

echo "== Cloning repo into destination staging: $GIT_WORKTREE =="
mkdir -p "$GIT_STAGING_PARENT"
if [ ! -e "$GIT_WORKTREE/.git" ]; then
  git clone --branch "$GIT_BRANCH" --single-branch "$GIT_URL" "$GIT_WORKTREE"
else
  git -C "$GIT_WORKTREE" checkout "$GIT_BRANCH"
  git -C "$GIT_WORKTREE" pull --ff-only origin "$GIT_BRANCH"
fi
echo "DEST_COMMIT=$(git -C "$GIT_WORKTREE" rev-parse HEAD)"

echo "== Verifying mapped folders are present in the clone =="
rc=0
while IFS=$'\t' read -r src_abs repo_rel dest_abs; do
  [ -z "${src_abs:-}" ] && continue
  guard_rel "$repo_rel"
  if [ -d "$GIT_WORKTREE/$repo_rel" ]; then
    q=$(find "$GIT_WORKTREE/$repo_rel" -type f -name '*.dbquery.ipynb' | wc -l | tr -d ' ')
    echo "OK       $repo_rel (dbquery files: $q)"
  else
    echo "MISSING  $repo_rel"; rc=1
  fi
done < <(read_map)

if [ "$rc" -ne 0 ]; then
  echo "ERROR: some folders missing — NOT tearing down the credential so you can re-pull." >&2
  exit 1
fi
echo "destination clone verified."

# --- Ephemeral teardown: dest Git credential no longer needed (phase 40 uses no Git) ---
if [ "$EPHEMERAL_ENABLED" = "true" ] && [ "$KEEP_EPHEMERAL" != "true" ]; then
  echo "== Tearing down the DEST ephemeral Git credential =="
  delete_git_credential "$DST_CRED_ID"
fi
echo "DONE: destination clone complete. Next: bash migration/bin/40_dest_land.sh"
