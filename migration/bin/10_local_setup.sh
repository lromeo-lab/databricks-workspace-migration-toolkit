#!/usr/bin/env bash
# PHASE 1 — LOCAL laptop terminal.
# Ephemeral mode: mints collision-free temporary CLI profiles, uses them to
# register a Git credential in each workspace, records the credential IDs into
# config.env, then removes the temporary local profiles (they are only needed
# to mint the credential). The server-side credentials live on until phase 20
# (source) and phase 30 (dest) tear them down by id.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"
require_vars SRC_WS_URL DST_WS_URL GIT_PROVIDER GIT_USERNAME GIT_EMAIL

if [ "$EPHEMERAL_ENABLED" != "true" ]; then
  echo "EPHEMERAL_ENABLED != true — set it to 'true' in config.env to use this script." >&2
  exit 1
fi

# --- Clean up any credentials left by a PRIOR run recorded in config.env -----
if [ -n "$SRC_CRED_ID" ] || [ -n "$DST_CRED_ID" ]; then
  echo "== Cleaning up credentials from a previous run =="
  [ -n "$RUN_ID" ] && { PREV_SRC_PROF="$(ephemeral_profile src)"; PREV_DST_PROF="$(ephemeral_profile dst)"; }
  # Recreate short-lived profiles only if needed to delete the old creds.
  if [ -n "$SRC_CRED_ID" ]; then
    databricks auth login --host "$SRC_WS_URL" --profile "prev-src-cleanup" >/dev/null 2>&1 || true
    delete_git_credential "$SRC_CRED_ID" "prev-src-cleanup"
    delete_local_profile "prev-src-cleanup"
  fi
  if [ -n "$DST_CRED_ID" ]; then
    databricks auth login --host "$DST_WS_URL" --profile "prev-dst-cleanup" >/dev/null 2>&1 || true
    delete_git_credential "$DST_CRED_ID" "prev-dst-cleanup"
    delete_local_profile "prev-dst-cleanup"
  fi
  persist_config SRC_CRED_ID ""; persist_config DST_CRED_ID ""
  SRC_CRED_ID=""; DST_CRED_ID=""
fi

# --- Fresh run id + collision-free ephemeral profile names -------------------
RUN_ID="$(gen_run_id)"; persist_config RUN_ID "$RUN_ID"
SRC_PROFILE="$(ephemeral_profile src)"
DST_PROFILE="$(ephemeral_profile dst)"
echo "== Run id: $RUN_ID =="
echo "   ephemeral profiles: $SRC_PROFILE , $DST_PROFILE"

# Make sure no stale stanzas with these names exist (extremely unlikely).
delete_local_profile "$SRC_PROFILE" >/dev/null 2>&1 || true
delete_local_profile "$DST_PROFILE" >/dev/null 2>&1 || true

echo "== Authenticating workspaces (browser will open twice) =="
databricks auth login --host "$SRC_WS_URL" --profile "$SRC_PROFILE"
databricks auth login --host "$DST_WS_URL" --profile "$DST_PROFILE"

echo "== Registering ephemeral Git credential in both workspaces =="
# read -s waits SILENTLY: paste the PAT and press Enter.
read -s -p "Paste your Git PAT, then press Enter: " GIT_PAT; echo
[ -n "$GIT_PAT" ] || { echo "ERROR: empty PAT" >&2; exit 1; }

SRC_CRED_ID="$(create_git_credential "$SRC_PROFILE")" || { echo "ERROR: source credential create failed" >&2; unset GIT_PAT; exit 1; }
DST_CRED_ID="$(create_git_credential "$DST_PROFILE")" || { echo "ERROR: dest credential create failed" >&2; unset GIT_PAT; exit 1; }
unset GIT_PAT

[ -n "$SRC_CRED_ID" ] || { echo "ERROR: could not read source credential_id" >&2; exit 1; }
[ -n "$DST_CRED_ID" ] || { echo "ERROR: could not read dest credential_id" >&2; exit 1; }
persist_config SRC_CRED_ID "$SRC_CRED_ID"
persist_config DST_CRED_ID "$DST_CRED_ID"
echo "   source credential_id: $SRC_CRED_ID"
echo "   dest   credential_id: $DST_CRED_ID"

# --- Remove the temporary LOCAL profiles: they are no longer needed ----------
# (The server-side credentials remain and are torn down in phases 20 and 30.)
echo "== Removing temporary local CLI profiles =="
delete_local_profile "$SRC_PROFILE"
delete_local_profile "$DST_PROFILE"

cat <<EOF

DONE: local setup complete.
NEXT: copy the UPDATED config.env (it now contains RUN_ID + credential IDs) to:
  - the SOURCE workspace web terminal, then run: bash migration/bin/20_source_package.sh
  - the DEST   workspace web terminal, then run: bash migration/bin/30_dest_clone.sh
                                              and bash migration/bin/40_dest_land.sh
The source credential is deleted at the end of phase 20; the dest credential at
the end of phase 30. Set KEEP_EPHEMERAL="true" to skip teardown for debugging.
EOF
