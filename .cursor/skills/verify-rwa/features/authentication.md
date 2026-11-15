# Authentication

A visitor signs in with a username and password, can ask to be remembered for 30 days, sees inline validation errors for incomplete forms, and sees a single error banner when credentials are wrong. A new visitor can sign up, complete bank-account onboarding, and sign out. Protected routes send unauthenticated visitors to the sign-in page. Source of truth: `cypress/tests/ui/auth.spec.ts`.

## Sub-features

- `auth-redirect`: an unauthenticated visit to a protected route (`/personal`) lands on `/signin`.
- `auth-login`: a seeded user with password `s3cret` lands on `/`.
- `auth-remember`: with `Remember me` checked, the `connect.sid` cookie has an `expiry` (30 days, set by `backend/auth.ts`).
- `auth-logout`: `sidenav-signout` returns the user to `/signin`.
- `auth-login-validation`: an empty username shows `Username is required`, a 3-character password shows `Password must contain at least 4 characters`, and submit is disabled.
- `auth-signup-validation`: empty or mismatched sign-up fields show per-field errors, and submit is disabled.
- `auth-invalid-user`: an unknown username shows `Username or password is invalid`.
- `auth-invalid-password`: a seeded username with a wrong password shows `Username or password is invalid`.
- `auth-signup-onboarding`: sign up, sign in, create a bank account in the onboarding dialog, see `You're all set!`, then reach the transaction list.

## How to get to it (user POV)

- Open `http://localhost:3000/signin` directly.
- Open any protected route, such as `/`, `/personal` or `/user/settings`, while signed out. The app redirects to `/signin`.
- From `/signin`, choose the `Don't have an account? Sign Up` link (`[data-test=signup]`) to reach `/signup`.
- Open `http://localhost:3000/signup` directly.
- While signed in, choose `Logout` in the side nav (`[data-test=sidenav-signout]`). On mobile widths (414 px or less), open it with `[data-test=sidenav-toggle]` first.

## Driving it with Cypress

Preconditions:

- `helpers/launch.sh` printed `READY`, and `helpers/doctor.sh "$RUN_ID"` printed `DOCTOR OK`.
- Each test starts with `cy.task("db:seed")`, so there are 5 seeded users with password `s3cret`, and `PainterJoy90` does not exist yet.
- Viewport 1280x1000 (the `cypress.config.ts` default), so the side nav is visible without `sidenav-toggle`.

Run the whole feature with `.cursor/skills/verify-rwa/helpers/drive-auth.sh "$RUN_ID"`. Each sub-feature, with its exact command and observable result:

- **Redirect (`auth-redirect`).** Visit a protected route while signed out with `cy.visit("/personal")`. Result: `cy.location("pathname").should("equal", "/signin")`.
- **Sign in (`auth-login`).** Use `cy.database("find", "users").then((user) => cy.login(user.username, "s3cret", { rememberUser: true }))`. `cy.login` types into `[data-test=signin-username]` and `[data-test=signin-password]`, checks the input inside `[data-test=signin-remember-me]`, clicks `[data-test=signin-submit]`, and waits on `@loginUser` (`POST /login`). Result: `cy.location("pathname").should("equal", "/")`, and the `@loginUser` response status is `200`.
- **Remember me (`auth-remember`).** After signing in with `rememberUser: true`, run `cy.getCookie("connect.sid").should("have.property", "expiry")`.
- **Sign out (`auth-logout`).** Run `cy.getBySel("sidenav-signout").click()`. Result: `cy.location("pathname").should("eq", "/signin")`.
- **Sign-in validation (`auth-login-validation`).** On `/`, type `User` into `signin-username`, clear the inner `input`, and blur it. Result: `cy.get("#username-helper-text").should("be.visible").and("contain", "Username is required")`. Then type `abc` into `signin-password` and blur it. Result: `cy.get("#password-helper-text")` contains `Password must contain at least 4 characters`, and `cy.getBySel("signin-submit").should("be.disabled")`.
- **Sign-up validation (`auth-signup-validation`).** Use `cy.visit("/signup")`. For each of `signup-first-name`, `signup-last-name`, `signup-username` and `signup-password`, type a value, clear the inner `input` and blur it. Results:
  - `#firstName-helper-text` shows `First Name is required`.
  - `#lastName-helper-text` shows `Last Name is required`.
  - `#username-helper-text` shows `Username is required`.
  - `#password-helper-text` shows `Enter your password`.
  - Typing `DIFFERENT PASSWORD` into `signup-confirmPassword` and blurring makes `#confirmPassword-helper-text` show `Password does not match`.
  - `cy.getBySel("signup-submit").should("be.disabled")`.
- **Invalid user (`auth-invalid-user`).** Run `cy.login("invalidUserName", "invalidPa$$word")`. Result: `cy.getBySel("signin-error").should("be.visible").and("have.text", "Username or password is invalid")`. The `@loginUser` response status is `401`, and the pathname stays `/signin`.
- **Invalid password (`auth-invalid-password`).** Run `cy.database("find", "users").then((user) => cy.login(user.username, "INVALID"))`. Result: the same `signin-error` assertion, with exact text `Username or password is invalid`, and `@loginUser` status `401`.
- **Sign up and onboard (`auth-signup-onboarding`).**
  - Sign up: on `/`, click `signup`, and check that `signup-title` contains `Sign Up`. Fill `signup-first-name` (`Bob`), `signup-last-name` (`Ross`), `signup-username` (`PainterJoy90`), `signup-password` (`s3cret`) and `signup-confirmPassword` (`s3cret`). Click `signup-submit` and wait on `@signup` (`POST /users`).
  - Sign in and onboard: run `cy.login("PainterJoy90", "s3cret")`. Check that `user-onboarding-dialog` is visible, then click `user-onboarding-next`. `user-onboarding-dialog-title` contains `Create Bank Account`.
  - Create the bank account: fill `getBySelLike("bankName-input")`, `getBySelLike("accountNumber-input")` and `getBySelLike("routingNumber-input")`, click `getBySelLike("submit")`, and wait on the GraphQL `CreateBankAccount` alias.
  - Result: `user-onboarding-dialog-title` contains `Finished`, `user-onboarding-dialog-content` contains `You're all set!`, and after `user-onboarding-next`, `transaction-list` is visible.
- **Proof.** `drive-auth.sh` runs the unmodified `auth.spec.ts`, which covers all 9 sub-features in 8 tests. It also runs `helpers/auth-evidence.cy.js` with `retries=0`, which covers `auth-redirect`, `auth-invalid-user`, `auth-invalid-password`, `auth-login`, `auth-remember` and `auth-logout`. That spec writes `auth-redirect-signin.png`, `auth-invalid-user-before.png`, `auth-invalid-user-after.png`, `auth-invalid-password-after.png`, `auth-login-home.png` and `auth-logout-signin.png` under `$EVIDENCE_DIR/screenshots/auth-evidence/`. It also writes JUnit results to `$EVIDENCE_DIR/junit/`.

## Gotchas

- `signin-error` is rendered only after a failed `POST /login`. The text comes from `src/machines/authMachine.ts`, not from the server's 401 body. Wait for `@loginUser` before asserting.
- `signin-username` and the other `data-test` handles sit on the MUI `TextField` wrapper. Use `.find("input")` to clear, blur or check the real input, as the spec does.
- `cy.login` only visits `/signin` when the current path differs. Visiting `/signin` first, to take a "before" screenshot, does not double-load the page.
- `auth-signup-onboarding` creates user `PainterJoy90`. Without `cy.task("db:seed")` first, a rerun fails because the username already exists.
- `cy.visualSnapshot` is a Percy call and does nothing without `PERCY_TOKEN`. It is not evidence; use `cy.screenshot`.
- The repo config sets `retries.runMode: 2`. A green repo run can hide a first-attempt failure, so the evidence spec runs with `retries=0`.
- On mobile viewports the side nav is collapsed. Click `sidenav-toggle` before `sidenav-signout`, as the spec's `isMobile()` branch does.
- The spec and `cy.login` intercept `/login` and `checkAuth` relative to `baseUrl`. If the ports change, the intercepts in `cypress/support/e2e.ts` (`http://localhost:3001/**`) silently stop matching.
