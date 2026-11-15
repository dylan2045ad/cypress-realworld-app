# Sourced by the other verify-rwa helpers. Not meant to be run directly.
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"
FRONTEND_PORT=3000
API_PORT=3001
FRONTEND_URL="http://localhost:${FRONTEND_PORT}"
API_URL="http://localhost:${API_PORT}"
STATE_ROOT="/tmp/verify-rwa-state"
EVIDENCE_ROOT="${VERIFY_RWA_EVIDENCE_ROOT:-$HOME/verify-rwa-evidence}"

die() { echo "verify-rwa: $*" >&2; exit 1; }

require_run_id() {
  RUN_ID="${1:-${RUN_ID:-}}"
  [ -n "$RUN_ID" ] || die "pass RUN_ID as the first argument (printed by launch.sh)"
  STATE_DIR="$STATE_ROOT/$RUN_ID"
  EVIDENCE_DIR="$EVIDENCE_ROOT/$RUN_ID"
  [ -d "$EVIDENCE_DIR" ] || die "no evidence dir $EVIDENCE_DIR; was launch.sh run with this RUN_ID?"
}

# The repo pins Node in .node-version. /exec-daemon/node and other system
# nodes can shadow nvm, so put the pinned nvm build first on PATH.
use_pinned_node() {
  local want="v$(cat "$REPO_ROOT/.node-version")"
  local nvm_bin="${NVM_DIR:-$HOME/.nvm}/versions/node/$want/bin"
  if [ "$(node -v 2>/dev/null)" != "$want" ] && [ -x "$nvm_bin/node" ]; then
    export PATH="$nvm_bin:$PATH"
    hash -r
  fi
  [ "$(node -v 2>/dev/null)" = "$want" ] || die "need Node $want (run: nvm install $(cat "$REPO_ROOT/.node-version"))"
  if ! yarn -v 2>/dev/null | grep -q '^1\.'; then
    npm install --global yarn@1.22.22 >/dev/null 2>&1 || die "could not install Yarn Classic"
    hash -r
  fi
  yarn -v | grep -q '^1\.' || die "need Yarn Classic 1.x, got $(yarn -v 2>&1)"
}

# Runs a command from the repo root, tees output to a log under the evidence
# dir, and appends "<utc time>\t<exit>\t<command>" to commands.tsv.
run_logged() {
  local logname="$1"; shift
  local log="$EVIDENCE_DIR/logs/$logname.log"
  mkdir -p "$EVIDENCE_DIR/logs"
  echo "\$ $*" | tee "$log"
  (cd "$REPO_ROOT" && "$@") >>"$log" 2>&1
  local rc=$?
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$rc" "$*" >>"$EVIDENCE_DIR/commands.tsv"
  echo "exit=$rc (log: $log)"
  return $rc
}

listener_pid() {
  lsof -nP -t -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | head -n1
}
