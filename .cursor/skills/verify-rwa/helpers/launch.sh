#!/usr/bin/env bash
# Usage: launch.sh [RUN_ID]
# Installs deps, starts `yarn dev` in its own process group, waits until the
# app is usable, and prints the RUN_ID that doctor/drive/cleanup need.
source "$(dirname "$0")/common.sh"

RUN_ID="${1:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
STATE_DIR="$STATE_ROOT/$RUN_ID"
EVIDENCE_DIR="$EVIDENCE_ROOT/$RUN_ID"
[ -e "$STATE_DIR" ] && die "RUN_ID $RUN_ID already used ($STATE_DIR exists)"
mkdir -p "$STATE_DIR" "$EVIDENCE_DIR/logs"
printf 'utc\texit\tcommand\n' >"$EVIDENCE_DIR/commands.tsv"

for port in "$FRONTEND_PORT" "$API_PORT"; do
  pid="$(listener_pid "$port")"
  if [ -n "$pid" ]; then
    die "port $port is already owned by PID $pid ($(ps -o cmd= -p "$pid")). Not ours; refusing to double-drive. Stop it yourself or use the existing instance's owner."
  fi
done

use_pinned_node
cd "$REPO_ROOT"

# Record pre-run state so cleanup only reverts what this run changed.
git rev-parse HEAD >"$STATE_DIR/git-head"
git status --porcelain -- data/database.json >"$STATE_DIR/database-json-status"
for f in src/aws-exports.js aws-exports-es5.js; do
  [ -e "$f" ] && echo "$f" >>"$STATE_DIR/preexisting-generated"
done
touch "$STATE_DIR/preexisting-generated"
{
  echo "run_id=$RUN_ID"
  echo "repo=$REPO_ROOT"
  echo "git_head=$(cat "$STATE_DIR/git-head")"
  echo "node=$(node -v)"
  echo "yarn=$(yarn -v)"
  echo "started_utc=$(date -u +%FT%TZ)"
} >"$EVIDENCE_DIR/run-info.txt"

run_logged yarn-install yarn install --frozen-lockfile || die "yarn install failed"
run_logged cypress-verify npx cypress verify || die "Cypress binary missing; run: npx cypress install"

# `yarn dev` runs the predev hook first: predev:cognito:ci writes the
# gitignored src/aws-exports.js + aws-exports-es5.js, then db:seed:dev copies
# data/database-seed.json over data/database.json.
# Started with `&` from a non-interactive shell, so setsid does not fork and
# $$ below is the new session/process-group leader.
setsid bash -c 'echo $$ >"$1"; exec yarn dev' _ "$STATE_DIR/dev.pgid" \
  >"$EVIDENCE_DIR/logs/yarn-dev.log" 2>&1 </dev/null &
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "started" "setsid yarn dev (background)" >>"$EVIDENCE_DIR/commands.tsv"

for _ in $(seq 1 50); do [ -s "$STATE_DIR/dev.pgid" ] && break; sleep 0.1; done
PGID="$(cat "$STATE_DIR/dev.pgid" 2>/dev/null)"
[ -n "$PGID" ] || die "yarn dev did not record its PID"
echo "yarn dev started: PGID=$PGID"

# Ready = frontend serves the RWA shell, API answered with seeded users, and a
# seeded user can actually log in. A bare open port is not enough.
ready=0
for i in $(seq 1 90); do
  if ! kill -0 "$PGID" 2>/dev/null; then
    tail -30 "$EVIDENCE_DIR/logs/yarn-dev.log"
    die "yarn dev exited during startup"
  fi
  if curl -fsS "$FRONTEND_URL/" 2>/dev/null | grep -q '<title>Cypress Real World App</title>' \
    && grep -q 'Backend server running at http://localhost:3001' "$EVIDENCE_DIR/logs/yarn-dev.log"; then
    user="$(curl -fsS "$API_URL/testData/users" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const r=JSON.parse(s).results;process.stdout.write(r.length?r[0].username:"")}catch(e){}})')"
    if [ -n "$user" ]; then
      code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
        -d "{\"username\":\"$user\",\"password\":\"s3cret\"}" "$API_URL/login")"
      if [ "$code" = 200 ]; then ready=1; break; fi
    fi
  fi
  sleep 2
done
[ "$ready" = 1 ] || die "app not usable after 180s; see $EVIDENCE_DIR/logs/yarn-dev.log"

echo "ready_after_polls=$i seeded_login_user=$user" | tee -a "$EVIDENCE_DIR/run-info.txt"
echo "READY  frontend=$FRONTEND_URL api=$API_URL"
echo "RUN_ID=$RUN_ID"
echo "EVIDENCE_DIR=$EVIDENCE_DIR"
