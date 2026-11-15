# verify-rwa run 20261115-auth-e2e

End-to-end proof of the `verify-rwa` skill, driving the `authentication` feature. Ran on a Cursor Cloud Agent VM (Linux, Node v22.20.0 via nvm, Yarn 1.22.22) at commit `fea3d36` of `cursor/verify-rwa-skill`. The full evidence, including logs and all 6 screenshots, stayed at `$HOME/verify-rwa-evidence/20261115-auth-e2e/` after cleanup. This folder is a trimmed copy.

| Step    | Command                                                                                                                       | Exit                                                                       |
| ------- | ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Launch  | `helpers/launch.sh 20261115-auth-e2e`: `yarn install --frozen-lockfile`, `npx cypress verify`, `setsid yarn dev` (PGID 10519) | 0 (ready after 4 polls, about 8 s)                                         |
| Doctor  | `helpers/doctor.sh 20261115-auth-e2e`                                                                                         | 0 (10 of 10 PASS)                                                          |
| Drive   | `yarn cypress:run --spec cypress/tests/ui/auth.spec.ts` (unmodified repo spec)                                                | 0 (8 tests, 0 failures)                                                    |
| Drive   | `yarn cypress:run --spec .cursor/skills/verify-rwa/helpers/auth-evidence.cy.js`, `retries=0`                                  | 0 (4 tests, 0 failures)                                                    |
| Cleanup | `helpers/cleanup.sh 20261115-auth-e2e`: SIGTERM to PGID 10519 only                                                            | 0 (group stopped, ports 3000 and 3001 free, `data/database.json` restored) |

## Invalid-credentials check

- Repo assertion (`cypress/tests/ui/auth.spec.ts`, "should error for an invalid user" and "should error for an invalid password for existing user"): `cy.getBySel("signin-error").should("be.visible").and("have.text", "Username or password is invalid")`. The selector resolves to `[data-test=signin-error]`, the MUI `Alert` in `src/components/SignInForm.tsx`.
- Both repo tests passed. The evidence spec repeated the same assertion with retries off, and also asserted that `@loginUser` (`POST /login`) returned `401` and that the pathname stayed `/signin`.
- Screenshots: `screenshots/auth-invalid-user-before.png` shows the empty sign-in form. `screenshots/auth-invalid-user-after.png` and `screenshots/auth-invalid-password-after.png` show the red "Username or password is invalid" banner.

## Post-cleanup confirmation

After `cleanup.sh`, `lsof -iTCP:3000 -iTCP:3001 -sTCP:LISTEN` returned nothing, and no `yarn dev`, `vite`, `nodemon` or `ts-node` processes remained. `git status` was clean apart from the new skill files, and the evidence dir was still listable.
