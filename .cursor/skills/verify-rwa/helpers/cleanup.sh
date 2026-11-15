#!/usr/bin/env bash
# Usage: cleanup.sh RUN_ID
# Stops only the process group launch.sh recorded for this RUN_ID, reverts
# scratch files this run changed, and leaves the evidence dir in place.
source "$(dirname "$0")/common.sh"
require_run_id "${1:-}"
cd "$REPO_ROOT"

log="$EVIDENCE_DIR/cleanup.txt"
{
  PGID="$(cat "$STATE_DIR/dev.pgid" 2>/dev/null)"
  if [ -z "$PGID" ]; then
    echo "no PGID recorded for $RUN_ID; nothing to stop"
  elif ! ps -o pid= -g "$PGID" >/dev/null 2>&1; then
    echo "process group $PGID already gone"
  else
    # Guard against PID reuse: only signal a group whose leader is still our
    # `yarn dev` in this checkout, or whose leader exited but left members.
    leader_cmd="$(tr '\0' ' ' <"/proc/$PGID/cmdline" 2>/dev/null)"
    leader_cwd="$(readlink "/proc/$PGID/cwd" 2>/dev/null)"
    if [ -n "$leader_cmd" ] && { [[ "$leader_cmd" != *yarn*dev* ]] || [ "$leader_cwd" != "$REPO_ROOT" ]; }; then
      echo "PGID $PGID now belongs to '$leader_cmd' in $leader_cwd; NOT ours, not signalling"
    else
      echo "members before: $(ps -o pid= -g "$PGID" | tr '\n' ' ')"
      kill -TERM -- "-$PGID" 2>/dev/null
      for _ in $(seq 1 15); do ps -o pid= -g "$PGID" >/dev/null 2>&1 || break; sleep 1; done
      if ps -o pid= -g "$PGID" >/dev/null 2>&1; then
        echo "still alive after 15s, sending SIGKILL to group $PGID"
        kill -KILL -- "-$PGID" 2>/dev/null
        sleep 1
      fi
      ps -o pid= -g "$PGID" >/dev/null 2>&1 && echo "WARN: group $PGID still has members" || echo "process group $PGID stopped"
    fi
  fi

  for port in "$FRONTEND_PORT" "$API_PORT"; do
    pid="$(listener_pid "$port")"
    [ -z "$pid" ] && echo "port $port free" || echo "WARN: port $port still owned by PID $pid ($(ps -o cmd= -p "$pid")); not ours to kill"
  done

  # data/database.json is rewritten by the predev seed and by POST /testData/seed.
  if [ ! -s "$STATE_DIR/database-json-status" ]; then
    git checkout -- data/database.json && echo "restored data/database.json (was clean before launch)"
  else
    echo "data/database.json had local changes before launch; left as is"
  fi
  for f in src/aws-exports.js aws-exports-es5.js; do
    if [ -e "$f" ] && ! grep -qx "$f" "$STATE_DIR/preexisting-generated" 2>/dev/null; then
      rm -f "$f" && echo "removed generated $f (created by this run)"
    fi
  done

  [ -d "$STATE_DIR" ] && cp -r "$STATE_DIR" "$EVIDENCE_DIR/state" && rm -rf "$STATE_DIR" && echo "removed state dir $STATE_DIR (copy kept in evidence/state)"
  echo "finished_utc=$(date -u +%FT%TZ)"
} 2>&1 | tee "$log"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "0" "cleanup.sh $RUN_ID" >>"$EVIDENCE_DIR/commands.tsv"

echo "Evidence kept at: $EVIDENCE_DIR"
ls -1 "$EVIDENCE_DIR"
