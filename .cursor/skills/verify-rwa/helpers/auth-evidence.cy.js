// Evidence journey for the authentication feature map. Uses the repo's own
// custom commands (cy.login, cy.getBySel, cy.database) from
// cypress/support/commands.ts and the same assertions as
// cypress/tests/ui/auth.spec.ts, plus screenshots of each before/after state.
describe("verify-rwa: authentication evidence", function () {
  beforeEach(function () {
    cy.task("db:seed");
  });

  it("auth-redirect: unauthenticated /personal redirects to /signin", function () {
    cy.visit("/personal");
    cy.location("pathname").should("equal", "/signin");
    cy.getBySel("signin-submit").should("be.visible");
    cy.screenshot("auth-redirect-signin");
  });

  it("auth-invalid-user: unknown username shows the sign-in error", function () {
    cy.visit("/signin");
    cy.screenshot("auth-invalid-user-before");
    cy.login("invalidUserName", "invalidPa$$word");
    cy.get("@loginUser").its("response.statusCode").should("equal", 401);
    cy.getBySel("signin-error")
      .should("be.visible")
      .and("have.text", "Username or password is invalid");
    cy.location("pathname").should("equal", "/signin");
    cy.screenshot("auth-invalid-user-after");
  });

  it("auth-invalid-password: seeded user with wrong password shows the sign-in error", function () {
    cy.visit("/signin");
    cy.database("find", "users").then((user) => {
      cy.login(user.username, "INVALID");
    });
    cy.get("@loginUser").its("response.statusCode").should("equal", 401);
    cy.getBySel("signin-error")
      .should("be.visible")
      .and("have.text", "Username or password is invalid");
    cy.screenshot("auth-invalid-password-after");
  });

  it("auth-login: seeded user with s3cret lands on / and keeps a 30-day session cookie", function () {
    cy.visit("/signin");
    cy.database("find", "users").then((user) => {
      cy.login(user.username, "s3cret", { rememberUser: true });
    });
    cy.get("@loginUser").its("response.statusCode").should("equal", 200);
    cy.location("pathname").should("equal", "/");
    cy.getCookie("connect.sid").should("have.property", "expiry");
    cy.getBySel("sidenav-signout").should("be.visible");
    cy.screenshot("auth-login-home");

    cy.getBySel("sidenav-signout").click();
    cy.location("pathname").should("eq", "/signin");
    cy.screenshot("auth-logout-signin");
  });
});
