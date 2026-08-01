# common.sh — sourced by every phase script. Loads config + shared helpers.
# NOTE: we do NOT use `set -e` here because these scripts are sometimes pasted
# into interactive web terminals; a single failing command should not kill the
# whole session. Each script checks the results it cares about explicitly.

set -uo pipefail

# Resolve the toolkit root (parent of lib/) regardless of caller CWD.
MIGRATION_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MIGRATION_HOME

# Load configuration.
if [ -f "$MIGRATION_HOME/config.env" ]; then
  # shellcheck disable=SC1091
  . "$MIGRATION_HOME/config.env"
else
  echo "ERROR: config.env not found in $MIGRATION_HOME" >&2
  return 1 2>/dev/null || exit 1
fi

FOLDERS_MAP="${FOLDERS_MAP:-$MIGRATION_HOME/folders.tsv}"
export FOLDERS_MAP

# Ephemeral defaults (in case an older config.env predates ephemeral mode).
export EPHEMERAL_ENABLED="${EPHEMERAL_ENABLED:-false}"
export KEEP_EPHEMERAL="${KEEP_EPHEMERAL:-false}"
export EPHEMERAL_PROFILE_PREFIX="${EPHEMERAL_PROFILE_PREFIX:-mig}"
export RUN_ID="${RUN_ID:-}"
export SRC_CRED_ID="${SRC_CRED_ID:-}"
export DST_CRED_ID="${DST_CRED_ID:-}"

# require_vars VAR1 VAR2 ... -> exits if any is empty.
require_vars() {
  local v missing=0
  for v in "$@"; do
    if [ -z "${!v:-}" ]; then
      echo "ERROR: required variable '$v' is empty. Check config.env." >&2
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || exit 1
}

# copy_tree SRC DST -> faithful WSFS byte copy, excludes nested .git, keeps hidden files.
copy_tree() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude='.git/' "$src/" "$dst/"
  else
    tar -C "$src" --exclude='./.git' -cf - . | tar -C "$dst" -xf -
  fi
}

# read_map -> emits valid TSV rows (skips comments/blanks). Fields: src_abs, repo_rel, dest_abs?
read_map() {
  require_vars FOLDERS_MAP
  [ -f "$FOLDERS_MAP" ] || { echo "ERROR: map file $FOLDERS_MAP not found" >&2; exit 1; }
  grep -vE '^[[:space:]]*(#|$)' "$FOLDERS_MAP"
}

# guard_rel REL -> rejects absolute or traversal paths in the repo-relative column.
guard_rel() {
  case "$1" in
    /*|*..*) echo "ERROR: invalid repo-relative path: $1" >&2; exit 1 ;;
  esac
}

# ============================================================================
# Ephemeral-mode helpers
# ============================================================================

# gen_run_id -> collision-free id for this run (UTC timestamp + short random).
gen_run_id() {
  local rnd
  rnd="$( (od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d ' ') || echo $$ )"
  printf '%s-%s' "$(date -u +%Y%m%d%H%M%S)" "$rnd"
}

# ephemeral_profile src|dst -> the collision-free local CLI profile name.
ephemeral_profile() {
  printf '%s-%s-%s' "$EPHEMERAL_PROFILE_PREFIX" "$1" "$RUN_ID"
}

# persist_config KEY VALUE -> update (or append) `export KEY="VALUE"` in config.env.
persist_config() {
  local key="$1" val="$2"
  python3 - "$MIGRATION_HOME/config.env" "$key" "$val" <<'PY'
import re, sys
path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    text = f.read()
line = f'export {key}="{val}"'
pat = re.compile(rf'^export {re.escape(key)}=.*$', re.M)
text = pat.sub(line, text) if pat.search(text) else text.rstrip('\n') + '\n' + line + '\n'
with open(path, 'w') as f:
    f.write(text)
PY
}

# create_git_credential PROFILE -> prints the created credential_id (or empty on failure).
create_git_credential() {
  local prof="$1" out
  out=$(databricks git-credentials create "$GIT_PROVIDER" \
        --git-username "$GIT_USERNAME" \
        --git-email "$GIT_EMAIL" \
        --personal-access-token "$GIT_PAT" \
        --profile "$prof" -o json 2>/dev/null) || return 1
  printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("credential_id",""))' 2>/dev/null
}

# delete_git_credential ID [PROFILE] -> best-effort delete by id (never fails the run).
# Deletes STRICTLY the id we captured, so it never touches a user's other credentials.
delete_git_credential() {
  local id="$1" prof="${2:-}"
  [ -n "$id" ] || { echo "  (no credential id recorded — nothing to delete)"; return 0; }
  if [ -n "$prof" ]; then
    databricks git-credentials delete "$id" --profile "$prof" >/dev/null 2>&1 \
      && echo "  deleted ephemeral Git credential $id (profile $prof)" \
      || echo "  WARN: could not delete Git credential $id (profile $prof) — remove manually if it lingers"
  else
    databricks git-credentials delete "$id" >/dev/null 2>&1 \
      && echo "  deleted ephemeral Git credential $id" \
      || echo "  WARN: could not delete Git credential $id — run: databricks git-credentials delete $id"
  fi
}

# delete_local_profile NAME -> remove one profile stanza from ~/.databrickscfg (local only).
delete_local_profile() {
  local name="$1" cfg="${DATABRICKS_CONFIG_FILE:-$HOME/.databrickscfg}"
  [ -f "$cfg" ] || { echo "  (no $cfg — nothing to remove)"; return 0; }
  python3 - "$cfg" "$name" <<'PY'
import configparser, sys
cfg, name = sys.argv[1], sys.argv[2]
cp = configparser.ConfigParser()
try:
    cp.read(cfg)
except Exception:
    print(f"  (could not parse {cfg}; leaving profile [{name}] untouched)"); raise SystemExit(0)
if cp.has_section(name):
    cp.remove_section(name)
    with open(cfg, "w") as f:
        cp.write(f)
    print(f"  removed local profile [{name}]")
else:
    print(f"  local profile [{name}] not present (ok)")
PY
}
