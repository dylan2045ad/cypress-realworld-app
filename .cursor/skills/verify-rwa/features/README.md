# Cypress Real World App verification map

This directory is the maintained source for verifying the user-facing behavior of the Cypress Real World App (RWA). Read this index before driving the app, then use the matching feature file as the recipe.

## Baseline preconditions

- Launch with `.cursor/skills/verify-rwa/helpers/launch.sh`. The frontend runs on `http://localhost:3000` and the API on `http://localhost:3001`. Both ports are fixed.
- Run `.cursor/skills/verify-rwa/helpers/doctor.sh "$RUN_ID"` and require `DOCTOR OK` before any drive.
- Seed data comes from `data/database-seed.json`: 5 users (`yarn list:dev:users` lists them), and every seeded user's password is `s3cret`.
- Every repo spec runs `cy.task("db:seed")` in `beforeEach`, so each test starts from the seed.
- Never drive an instance that this verification run did not start. Only one instance can run per machine.

## Driving conventions

- Use the repo's Cypress harness: `cy.getBySel` (`[data-test=…]`), `cy.getBySelLike` (`[data-test*=…]`), `cy.login`, `cy.database` and `cy.task("db:seed")` from `cypress/support/commands.ts` and `cypress.config.ts`.
- Prefer `data-test` handles. Use MUI helper-text ids (`#username-helper-text`, and so on) only where the repo's specs do.
- Keep the repo's assertions verbatim. Never weaken one to get a pass.
- Produce evidence with `retries=0`. The repo config retries twice in run mode.

## Proof and skip reporting

- Capture the user action and the resulting state as before/after screenshots under `$EVIDENCE_DIR/screenshots/`.
- Record exit codes in `$EVIDENCE_DIR/commands.tsv` and per-test results in `$EVIDENCE_DIR/junit/`.
- Verify the server-side effect, such as a response status, a cookie or a row in `/testData/<entity>`, alongside the visible result.
- Record the feature ID and entry point used with every artifact.
- Report an unreachable path with the attempted command and the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order:

1. `Sub-features` lists short IDs, one line per behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with Cypress` starts with `Preconditions:` and pairs each user action with an exact command and an observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

## Features

- [Authentication](./authentication.md) covers the protected-route redirect, sign-in, remember-me, sign-in and sign-up validation errors, invalid credentials, sign-up with onboarding, and sign-out. Its driver is `helpers/drive-auth.sh`.

### Found but not yet mapped

These features have specs in `cypress/tests/ui/` and routes in `src/containers/PrivateRoutesContainer.tsx`, but no feature file yet. Until a file exists, drive them with the repo spec as-is (see "Drive" in `SKILL.md`).

| Feature | Route | Repo spec |
| --- | --- | --- |
| Transaction feeds | `/`, `/public`, `/contacts`, `/personal` | `cypress/tests/ui/transaction-feeds.spec.ts` |
| New transaction | `/transaction/new` | `cypress/tests/ui/new-transaction.spec.ts` |
| Transaction view | `/transaction/:transactionId` | `cypress/tests/ui/transaction-view.spec.ts` |
| Bank accounts | `/bankaccounts*` | `cypress/tests/ui/bankaccounts.spec.ts` |
| Notifications | `/notifications` | `cypress/tests/ui/notifications.spec.ts` |
| User settings | `/user/settings` | `cypress/tests/ui/user-settings.spec.ts` |

Third-party sign-in variants (Auth0, Okta, Cognito, Google; `cypress/tests/ui-auth-providers/`) need provider credentials and a swapped `src/index.tsx`. They are out of scope for this skill.
