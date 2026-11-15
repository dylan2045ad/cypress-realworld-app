---
name: verify-rwa
description: "Launch, health-check, drive and tear down the Cypress Real World App (React/Vite frontend on :3000, Express/lowdb API on :3001) through its own Cypress harness, capturing evidence that survives cleanup. Use when you need to prove a user-facing behavior of this repo (sign-in, sign-up, transactions, bank accounts, notifications, settings) actually works in a running instance, not just that code compiles."
---

# Verify the Cypress Real World App (RWA)

The primary surface is the web UI at `http://localhost:3000`, backed by the API at `http://localhost:3001` (REST + `/graphql`, plus the test-only `/testData/*` routes the Cypress tasks use). There is no CLI surface. All paths below are relative to the repo root.

Every step is a script in `.cursor/skills/verify-rwa/helpers/`. Run them in order, passing the same `RUN_ID`:

```bash
H=.cursor/skills/verify-rwa/helpers
$H/launch.sh                 # prints RUN_ID=<id> and EVIDENCE_DIR=<dir>
$H/doctor.sh  "$RUN_ID"      # read-only; must print DOCTOR OK
$H/drive-auth.sh "$RUN_ID"   # authentication journey + evidence
$H/cleanup.sh "$RUN_ID"      # always run, also after failures
```

Before driving a feature, read `features/README.md` and the matching feature file.

## Isolation: one instance per machine

Ports are not configurable for verification. `cypress.config.ts` hardcodes `baseUrl: http://localhost:3000` and `apiUrl: http://localhost:3001`, and `cypress/support/e2e.ts` intercepts `http://localhost:3001/**`. All instances share one `data/database.json`, which every seed rewrites. Two instances cannot run side by side. `launch.sh` refuses to start when anything already listens on 3000 or 3001. Do not drive, restart or kill an instance this run did not start.

## Launch

Prerequisites:

- Node exactly as pinned in `.node-version` (`22.20.0`). `package.json` `engines` allows `^22 || ^24`, but use the pin. On Cursor VMs, `/exec-daemon/node` (another version) comes first on `PATH`. `use_pinned_node` in `helpers/common.sh` prepends `~/.nvm/versions/node/v22.20.0/bin`. If that directory is missing, run `nvm install 22.20.0`.
- Yarn Classic 1.x (`packageManager` pins `yarn@1.22.22`). Yarn 2+ is unsupported. The helper installs `yarn@1.22.22` with npm if `yarn` is absent.
- `lsof`, `curl`, `setsid` and `git` on `PATH`.

`helpers/launch.sh [RUN_ID]` does the following:

1. It refuses if port 3000 or 3001 already has a listener.
2. It records the pre-run state in `/tmp/verify-rwa-state/<RUN_ID>/`: git HEAD, whether `data/database.json` is dirty, and whether the generated `src/aws-exports.js` and `aws-exports-es5.js` already exist.
3. It runs `yarn install --frozen-lockfile`. The postinstall hook runs `husky install && patch-package`, which patches `react-virtualized`. It then runs `npx cypress verify`.
4. It starts `yarn dev` with `setsid` in a new process group and writes the group leader PID to `/tmp/verify-rwa-state/<RUN_ID>/dev.pgid`. The output goes to `<EVIDENCE_DIR>/logs/yarn-dev.log`. `yarn dev` first runs `predev`. That runs `db:seed:dev`, which runs `predev:cognito:ci` (`ncp` copies the mock aws-exports files) and then copies `data/database-seed.json` to `data/database.json`. This gives the seed data: 5 users, all with password `s3cret` (`SEED_DEFAULT_USER_PASSWORD` in `.env`). It then runs `concurrently yarn:start:react yarn:start:api:watch`, which starts Vite and the nodemon/ts-node API.
5. It treats the app as ready only when all of these hold. A bare open port is not enough.
   - `GET http://localhost:3000/` returns `<title>Cypress Real World App</title>`.
   - `yarn-dev.log` contains `Backend server running at http://localhost:3001`.
   - `GET http://localhost:3001/testData/users` returns at least one seeded user.
   - `POST http://localhost:3001/login` with that user and `s3cret` returns `200`.

   It polls every 2 s for up to 180 s. A warm start takes about 10 s.

It prints `READY`, `RUN_ID=…` and `EVIDENCE_DIR=…`. Export `RUN_ID` for the next steps.

Teardown is `helpers/cleanup.sh` (below). Do not use Ctrl-C or `pkill`.

## Doctor

`helpers/doctor.sh RUN_ID` is read-only. It writes `doctor-<HHMMSS>.txt` to the evidence dir and exits 0 only if every line is `PASS`:

| Check | Meaning |
| --- | --- |
| `process` | The recorded PGID leader's cmdline is `yarn dev`. |
| `process-cwd` | The leader's `/proc/<pid>/cwd` is this repo root. |
| `port-3000-owner`, `port-3001-owner` | `lsof -t -iTCP:<port> -sTCP:LISTEN` gives a PID whose PGID is the recorded one. |
| `port-*-node` | That listener runs Node `v$(cat .node-version)`. |
| `version-git` | `git rev-parse HEAD` still equals the HEAD recorded at launch. If it differs, relaunch. |
| `version-package` | `package.json` is `cypress-realworld-app@1.0.0`. |
| `frontend` | `:3000` serves the RWA title. |
| `api-seed` | `GET /testData/users` returns more than 0 users. |

Run it first whenever anything looks off. If it prints `DOCTOR FAILED`, do not drive. Run cleanup, then launch again.

## Drive

The harness is the repo's Cypress 16 setup: `cypress.config.ts`, `cypress/support/e2e.ts` and `cypress/support/commands.ts`. Use the repo's commands and selectors. Do not invent new handles:

- `cy.getBySel(x)` resolves to `[data-test=x]`. `cy.getBySelLike(x)` resolves to `[data-test*=x]`.
- `cy.login(username, password, { rememberUser })` visits `/signin` unless already there, types into `signin-username` and `signin-password`, optionally checks `signin-remember-me`, clicks `signin-submit`, and waits on the intercept alias `@loginUser` (`POST /login`).
- `cy.task("db:seed")` calls `POST http://localhost:3001/testData/seed` and resets `data/database.json`.
- `cy.database("find" | "filter", entity, query)` reads `GET /testData/<entity>`.
- `cy.visualSnapshot()` is Percy. Without `PERCY_TOKEN` it does nothing, so it is not evidence.

To run any repo spec as-is:

```bash
yarn cypress:run --spec cypress/tests/ui/<name>.spec.ts \
  --config "screenshotsFolder=$EVIDENCE_DIR/screenshots/<name>,video=false" \
  --reporter junit --reporter-options "mochaFile=$EVIDENCE_DIR/junit/<name>.xml"
```

The `precypress:run` hook first runs `wait-on --timeout 60s http://localhost:3000 http://localhost:3001`.

`helpers/drive-auth.sh RUN_ID` drives the authentication feature (`features/authentication.md`):

1. It runs `doctor.sh` and aborts if the doctor fails.
2. It runs the unmodified `cypress/tests/ui/auth.spec.ts` (8 tests).
3. It runs `helpers/auth-evidence.cy.js` (4 tests) with `retries=0`. This spec reuses the same commands and assertions and screenshots each before and after state. It sits outside `cypress/tests/`, so the script passes `--config specPattern=.cursor/skills/verify-rwa/helpers/*.cy.js`.
4. It writes `drive-auth-summary.txt`, which lists both exit codes, the JUnit totals and the screenshot list.

For a new feature, copy the pattern: a `.cy.js` file in `helpers/` using `getBySel` handles from the feature file, plus a `drive-<feature>.sh` wrapper that calls `doctor.sh` first. Keep the repo's assertions verbatim, and never loosen them to get a pass.

## Evidence

Evidence lives at `${VERIFY_RWA_EVIDENCE_ROOT:-$HOME/verify-rwa-evidence}/<RUN_ID>/`, outside the repo and outside `/tmp/verify-rwa-state`. Cleanup never touches it.

| Path | Contents |
| --- | --- |
| `commands.tsv` | UTC time, exit code and command for every step. |
| `run-info.txt` | RUN_ID, repo, git HEAD, Node and Yarn versions, readiness poll count, seeded login user. |
| `logs/*.log` | Full output of yarn install, cypress verify, yarn dev, and each Cypress run. |
| `doctor-*.txt` | Each doctor result. |
| `junit/*.xml` | Per-test results. |
| `screenshots/<spec>/…png` | `cy.screenshot` captures, plus Cypress failure screenshots. |
| `drive-auth-summary.txt` | Exit codes, test totals and the screenshot list. |
| `cleanup.txt`, `state/` | What cleanup stopped and reverted, and a copy of the run state. |

Proof standards:

- Drive the real user path through the UI, meaning the sign-in form at `/signin`. `cy.task("db:seed")` and `cy.database` are only for setting up and reading state, never for proving behavior.
- Capture the action and the resulting state. Screenshots come in before/after pairs, and the assertion on the visible element is in the JUnit report.
- Verify the side effect next to the UI. For login, assert the `@loginUser` response status (`401` invalid, `200` valid) and the `connect.sid` cookie.
- Run with retries off (`retries=0`) when producing evidence. The repo config sets `retries.runMode: 2`, which can hide a flaky first attempt.
- Report a failing journey as failing, with its log and screenshot. Never edit app code, specs or assertions to get a pass.

To keep a summary in git, copy the small text files (`commands.tsv`, `drive-auth-summary.txt`, `doctor-*.txt`, `cleanup.txt`) to `.cursor/skills/verify-rwa/evidence/<RUN_ID>/`. Add screenshots only if they are small.

## Cleanup

`helpers/cleanup.sh RUN_ID` writes `cleanup.txt` to the evidence dir:

1. It reads the PGID recorded by `launch.sh`. If the group leader still exists, it must still be `yarn dev` with cwd at this repo root; otherwise the script refuses, as a guard against PID reuse. It sends `SIGTERM` to that process group only (`kill -TERM -- -<PGID>`), waits up to 15 s, then sends `SIGKILL` to the same group. It never kills by process name and never touches listeners outside the group. It reports any foreign process still on 3000 or 3001 but does not kill it.
2. It confirms ports 3000 and 3001 are free.
3. If `data/database.json` was clean before launch, it runs `git checkout -- data/database.json`. Seeding rewrites that file and drops its trailing newline. It removes `src/aws-exports.js` and `aws-exports-es5.js` only if this run created them. Both are gitignored.
4. It moves `/tmp/verify-rwa-state/<RUN_ID>` into `<EVIDENCE_DIR>/state/` and lists the evidence dir to show it survived.

Run cleanup after every failed attempt too, so broken runs do not strand processes or ports. Cypress runs in the foreground and exits on its own, so it needs no cleanup.

## Helpers

All helpers are executable bash scripts (`chmod +x`) that source `helpers/common.sh`:

| Helper | Invocation |
| --- | --- |
| `launch.sh` | `.cursor/skills/verify-rwa/helpers/launch.sh [RUN_ID]` |
| `doctor.sh` | `.cursor/skills/verify-rwa/helpers/doctor.sh RUN_ID` |
| `drive-auth.sh` | `.cursor/skills/verify-rwa/helpers/drive-auth.sh RUN_ID` |
| `cleanup.sh` | `.cursor/skills/verify-rwa/helpers/cleanup.sh RUN_ID` |
| `auth-evidence.cy.js` | Run by `drive-auth.sh`. To run it alone: `yarn cypress:run --spec .cursor/skills/verify-rwa/helpers/auth-evidence.cy.js --config "specPattern=.cursor/skills/verify-rwa/helpers/*.cy.js,retries=0"` |

Set `VERIFY_RWA_EVIDENCE_ROOT` to move the evidence root.
