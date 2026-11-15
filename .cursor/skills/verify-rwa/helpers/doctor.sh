#!/usr/bin/env bash
# Usage: doctor.sh RUN_ID
# Read-only. Exits 0 only if the instance on 3000/3001 is the one this run
# started, from this checkout, on the pinned Node, and is serving seeded data.
source "$(dirname "$0")/common.sh"
require_run_id "${1:-}"

fail=0
out="$EVIDENCE_DIR/doctor-$(date -u +%H%M%S).txt"
check() {
  local name="$1" ok="$2" detail="$3"
  if [ "$ok" = 1 ]; then echo "PASS  $name  $detail"; else echo "FAIL  $name  $detail"; fail=1; fi
}

{
  PGID="$(cat "$STATE_DIR/dev.pgid" 2>/dev/null)"
  leader_cmd="$( [ -n "$PGID" ] && tr '\0' ' ' <"/proc/$PGID/cmdline" 2>/dev/null)"
  leader_cwd="$( [ -n "$PGID" ] && readlink "/proc/$PGID/cwd" 2>/dev/null)"
  case "$leader_cmd" in *yarn*dev*) cmd_ok=1 ;; *) cmd_ok=0 ;; esac
  check "process" "$cmd_ok" "PGID=${PGID:-none} cmd='${leader_cmd}'"
  check "process-cwd" "$([ "$leader_cwd" = "$REPO_ROOT" ] && echo 1 || echo 0)" "cwd=${leader_cwd:-none} want=$REPO_ROOT"

  for port in "$FRONTEND_PORT" "$API_PORT"; do
    pid="$(listener_pid "$port")"
    owner_pgid="$( [ -n "$pid" ] && ps -o pgid= -p "$pid" | tr -d ' ')"
    check "port-$port-owner" "$([ -n "$pid" ] && [ "$owner_pgid" = "$PGID" ] && echo 1 || echo 0)" \
      "listener PID=${pid:-none} PGID=${owner_pgid:-none} want PGID=$PGID"
    if [ -n "$pid" ]; then
      want_node="v$(cat "$REPO_ROOT/.node-version")"
      got_node="$("/proc/$pid/exe" -v 2>/dev/null)"
      check "port-$port-node" "$([ "$got_node" = "$want_node" ] && echo 1 || echo 0)" "node=$got_node want=$want_node"
    fi
  done

  head_now="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  head_launch="$(cat "$STATE_DIR/git-head" 2>/dev/null)"
  check "version-git" "$([ "$head_now" = "$head_launch" ] && echo 1 || echo 0)" "HEAD=$head_now launched_at=$head_launch"
  pkg="$(node -p 'const p=require(process.argv[1]);p.name+"@"+p.version' "$REPO_ROOT/package.json")"
  check "version-package" "$([ "$pkg" = "cypress-realworld-app@1.0.0" ] && echo 1 || echo 0)" "$pkg"

  title_ok=0
  curl -fsS "$FRONTEND_URL/" 2>/dev/null | grep -q '<title>Cypress Real World App</title>' && title_ok=1
  check "frontend" "$title_ok" "$FRONTEND_URL serves <title>Cypress Real World App</title>"

  users="$(curl -fsS "$API_URL/testData/users" 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).results.length))}catch(e){process.stdout.write("0")}})')"
  check "api-seed" "$([ "${users:-0}" -gt 0 ] && echo 1 || echo 0)" "GET $API_URL/testData/users -> ${users:-0} users"
} | tee "$out"

grep -q '^FAIL' "$out" && fail=1
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$fail" "doctor.sh $RUN_ID" >>"$EVIDENCE_DIR/commands.tsv"
[ "$fail" = 0 ] && echo "DOCTOR OK" || echo "DOCTOR FAILED: do not drive this instance"
exit "$fail"
