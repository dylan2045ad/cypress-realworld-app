#!/usr/bin/env bash
# Usage: drive-auth.sh RUN_ID
# Runs doctor, then (1) the repo's unmodified cypress/tests/ui/auth.spec.ts
# and (2) helpers/auth-evidence.cy.js with screenshots, retries disabled.
# Both write screenshots, logs and JUnit results into the evidence dir.
source "$(dirname "$0")/common.sh"
require_run_id "${1:-}"
use_pinned_node

"$SKILL_DIR/helpers/doctor.sh" "$RUN_ID" || die "doctor failed; not driving"

rel_skill="${SKILL_DIR#"$REPO_ROOT"/}"
SHOTS="$EVIDENCE_DIR/screenshots"
mkdir -p "$SHOTS" "$EVIDENCE_DIR/junit"

run_logged cypress-auth-spec yarn cypress:run \
  --spec cypress/tests/ui/auth.spec.ts \
  --config "screenshotsFolder=$SHOTS/auth-spec,video=false" \
  --reporter junit --reporter-options "mochaFile=$EVIDENCE_DIR/junit/auth-spec.xml"
spec_rc=$?

run_logged cypress-auth-evidence yarn cypress:run \
  --spec "$rel_skill/helpers/auth-evidence.cy.js" \
  --config "specPattern=$rel_skill/helpers/*.cy.js,screenshotsFolder=$SHOTS/auth-evidence,video=false,retries=0" \
  --reporter junit --reporter-options "mochaFile=$EVIDENCE_DIR/junit/auth-evidence.xml"
evidence_rc=$?

{
  echo "auth.spec.ts exit=$spec_rc"
  echo "auth-evidence.cy.js exit=$evidence_rc"
  for f in "$EVIDENCE_DIR"/junit/*.xml; do
    node -e '
      const x=require("fs").readFileSync(process.argv[1],"utf8");
      const m=x.match(/<testsuites[^>]*tests="(\d+)"[^>]*failures="(\d+)"/);
      console.log(require("path").basename(process.argv[1]) + (m ? ` tests=${m[1]} failures=${m[2]}` : " (no totals)"));
    ' "$f"
  done
  echo "screenshots:"
  (cd "$SHOTS" && find . -name '*.png' | sort)
} | tee "$EVIDENCE_DIR/drive-auth-summary.txt"

[ "$spec_rc" = 0 ] && [ "$evidence_rc" = 0 ]
